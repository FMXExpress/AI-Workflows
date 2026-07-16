unit Replicate.DataBindSource;

// STAGE 1 of the LiveBindings workflow-builder rebuild.
//
// TReplicateDataBindSource is a dataset-backed Replicate bind source: it
// descends from TBindSourceDB over an internal TFDMemTable, exactly the pattern
// every working TLinkControlToField sample in FMXExpress/Cross-Platform-Samples
// uses. Because the source is a real dataset, LiveBindings control links refresh
// on their own (Post fires the notification) and the fields are wire-able in the
// designer - including chaining one component's output field into another's
// input field, which is the workflow-builder goal.
//
// Reuses the REST/schema/converter code from Replicate.BindSource (its
// initialization registers the URL->bitmap converters and exposes
// LoadUrlOrFileToBitmap and the debug hook).
//
// NOTE: not yet compiled here (no Delphi toolchain in the authoring env) -
// expect to iterate on build errors.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.Threading,
  System.Generics.Collections,
  System.Rtti,
  System.NetEncoding,
  System.IOUtils,
  System.StrUtils,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Param,
  FireDAC.Stan.Error,
  FireDAC.DatS,
  FireDAC.Phys.Intf,
  FireDAC.DApt.Intf,
  FireDAC.Stan.Async,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client,
  Data.Bind.DBScope,
  Replicate.BindSource; // reuse converters, LoadUrlOrFileToBitmap, debug hook

type
  TReplicateStatusEvent = procedure(Sender: TObject) of object;

  TReplicateDataBindSource = class(TBindSourceDB)
  private
    FTable: TFDMemTable;
    FDataSource: TDataSource;
    FInputTypes: TDictionary<string, string>; // input field name -> json type

    FApiToken: string;
    FModel: string;
    FVersion: string;
    FActualVersion: string;
    FCachedSchema: string;
    FIsRunning: Boolean;
    FAutoRun: Boolean;
    FDebug: Boolean;
    FSettingInput: Boolean;   // guard: input write came from our own SetInputValue
    FInputRunQueued: Boolean; // guard: an auto-run is already queued

    FOnCompleted: TNotifyEvent;
    FOnStatusChanged: TNotifyEvent;
    FOnInputChanged: TNotifyEvent;
    FChainNotifies: TList<TNotifyEvent>; // edge components observing completion

    procedure SetModel(const AValue: string);
    procedure SetVersion(const AValue: string);
    procedure SetCachedSchema(const AValue: string);
    procedure SetApiToken(const AValue: string);

    procedure BuildTableFromSchema;
    procedure EnsureRow;
    procedure PutField(const AName: string; const AValue: Variant);
    // Batched update: one Edit ... one Post, so bound links (and the image
    // converter) refresh once per state change instead of once per field.
    procedure BeginEdit;
    procedure SetRaw(const AName: string; const AValue: Variant);
    procedure EndEdit;
    function GetFieldStr(const AName: string): string;
    function HasField(const AName: string): Boolean;

    procedure FetchSchema;
    function SerializeInputs: TJSONObject;
    procedure ExecutePrediction;
    procedure UpdateState(const AStatus, ALogs, AError: string; AOutputVal: TJSONValue);
    procedure ParseOutput(AOutputVal: TJSONValue);
    procedure DebugLog(const AMsg: string);
    procedure TableAfterPost(DataSet: TDataSet);
    // Auto-run when an Input_ field is written by a LiveBindings wire (an
    // upstream output field bound to this input field) rather than by our own
    // SetInputValue. This is what makes designer field->field chaining work.
    procedure HookInputFields;
    procedure InputFieldChanged(Sender: TField);
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure LoadSchema;
    procedure RebuildFromSchema;
    procedure Run;

    procedure SetInputValue(const AName: string; const AValue: string);
    procedure TrySetInputValue(const AName, AValue: string);
    function GetOutputValue(const AName: string): string;
    // Edge components (TReplicateWorkflowLink) subscribe here to be notified on
    // successful completion, independently of the public OnCompleted event.
    procedure AddChainNotify(const AHandler: TNotifyEvent);
    procedure RemoveChainNotify(const AHandler: TNotifyEvent);
    function GetInputImage: string;
    procedure SetInputImage(const AValue: string);
    function GetInputPrompt: string;
    procedure SetInputPrompt(const AValue: string);

    property Table: TFDMemTable read FTable;
    property ActualVersion: string read FActualVersion;
    property IsRunning: Boolean read FIsRunning;
  published
    // Bindable input properties for designer-wired workflow chaining: bind an
    // upstream component's OutputImage/OutputText field to InputImage/InputPrompt
    // here with a TLinkPropertyToField (DataSource=upstream, FieldName=Output...,
    // Component=this, ComponentProperty=Input...). Setting them writes the
    // matching schema input field and, with AutoRun, kicks off this stage. Safe
    // no-op if the model has no such input.
    property InputImage: string read GetInputImage write SetInputImage;
    property InputPrompt: string read GetInputPrompt write SetInputPrompt;
    property ApiToken: string read FApiToken write SetApiToken;
    property Model: string read FModel write SetModel;
    property Version: string read FVersion write SetVersion;
    property CachedSchema: string read FCachedSchema write SetCachedSchema;
    property AutoRun: Boolean read FAutoRun write FAutoRun default False;
    property Debug: Boolean read FDebug write FDebug default False;
    property OnCompleted: TNotifyEvent read FOnCompleted write FOnCompleted;
    property OnStatusChanged: TNotifyEvent read FOnStatusChanged write FOnStatusChanged;
    property OnInputChanged: TNotifyEvent read FOnInputChanged write FOnInputChanged;
  end;

  // Workflow-graph edge for chaining in the LiveBindings Designer.
  //
  // Workflow-graph EDGE component. LiveBindings cannot carry a value from one
  // bind source into another on its canvas (a bind source's fields are exposed
  // as read-only virtual members - "virtual members are read only" - and its
  // object properties are invisible as bind targets). So the edge forwards the
  // value itself: it listens to the Source stage's completion and pushes the
  // chosen output into the Target stage's input, which (with Target.AutoRun)
  // launches it.
  //
  // Configure in the Object Inspector - no LiveBindings wire for the edge:
  //   Source       = upstream stage (TReplicateDataBindSource)
  //   SourceOutput = which output to read  ('image' | 'text' | 'Output')
  //   Target       = downstream stage
  //   InputName    = which input to feed   ('image' | 'prompt' | ...)
  // Per-node bindings (output field -> TImage, Status -> control) still use the
  // LiveBindings Designer as normal; only the stage-to-stage edge uses this.
  TReplicateWorkflowLink = class(TComponent)
  private
    FSource: TReplicateDataBindSource;
    FTarget: TReplicateDataBindSource;
    FSourceOutput: string;
    FInputName: string;
    FHooked: Boolean;
    procedure SetSource(const AValue: TReplicateDataBindSource);
    procedure SetTarget(const AValue: TReplicateDataBindSource);
    procedure Hook;
    procedure Unhook;
    procedure SourceCompleted(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Source: TReplicateDataBindSource read FSource write SetSource;
    property SourceOutput: string read FSourceOutput write FSourceOutput;
    property Target: TReplicateDataBindSource read FTarget write SetTarget;
    property InputName: string read FInputName write FInputName;
  end;

procedure Register;

implementation

const
  // Stable fields present regardless of schema. Flat, dot-free names so they
  // map cleanly to dataset field names and LiveBindings FieldName lookups.
  CStateFields: array[0..3] of string = ('Status', 'IsRunning', 'ErrorMessage', 'Logs');
  COutputFields: array[0..2] of string = ('Output', 'OutputImage', 'OutputText');

function TruncS(const S: string; AMax: Integer): string;
begin
  if Length(S) <= AMax then Result := S
  else Result := S.Substring(0, AMax) + Format('...(%d chars)', [Length(S)]);
end;

procedure ParseModelString(const AModelStr: string; out AOwner, AName, AVerId: string);
var
  LParts, LSubParts: TArray<string>;
begin
  AOwner := ''; AName := ''; AVerId := '';
  LParts := AModelStr.Split(['/']);
  if Length(LParts) >= 2 then
  begin
    AOwner := LParts[0];
    LSubParts := LParts[1].Split([':']);
    AName := LSubParts[0];
    if Length(LSubParts) >= 2 then
      AVerId := LSubParts[1];
  end;
end;

function FileToBase64URI(const AFilePath: string): string;
var
  LFileStream: TFileStream;
  LBytes: TBytes;
  LMimeType, LExt: string;
begin
  Result := AFilePath;
  if not TFile.Exists(AFilePath) then Exit;
  LExt := TPath.GetExtension(AFilePath).ToLower;
  if LExt = '.png' then LMimeType := 'image/png'
  else if (LExt = '.jpg') or (LExt = '.jpeg') then LMimeType := 'image/jpeg'
  else if LExt = '.webp' then LMimeType := 'image/webp'
  else if LExt = '.gif' then LMimeType := 'image/gif'
  else if LExt = '.txt' then LMimeType := 'text/plain'
  else LMimeType := 'application/octet-stream';
  LFileStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(LBytes, LFileStream.Size);
    if LFileStream.Size > 0 then
      LFileStream.ReadBuffer(LBytes[0], LFileStream.Size);
  finally
    LFileStream.Free;
  end;
  Result := Format('data:%s;base64,%s',
    [LMimeType, TNetEncoding.Base64.EncodeBytesToString(LBytes).Replace(#13, '').Replace(#10, '')]);
end;

{ TReplicateDataBindSource }

constructor TReplicateDataBindSource.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FInputTypes := TDictionary<string, string>.Create;
  FChainNotifies := TList<TNotifyEvent>.Create;

  FTable := TFDMemTable.Create(Self);
  FTable.Name := ''; // owned, unnamed
  FTable.AfterPost := TableAfterPost;

  FDataSource := TDataSource.Create(Self);
  FDataSource.DataSet := FTable;

  // Wire this bind source to its own internal dataset so it works the moment
  // it is dropped on a form - the LiveBindings designer sees its fields.
  Self.DataSource := FDataSource;

  BuildTableFromSchema; // build stable fields (+ any cached schema) up front
end;

destructor TReplicateDataBindSource.Destroy;
begin
  FInputTypes.Free;
  FChainNotifies.Free;
  inherited;
end;

procedure TReplicateDataBindSource.AddChainNotify(const AHandler: TNotifyEvent);
begin
  if FChainNotifies.IndexOf(AHandler) < 0 then
    FChainNotifies.Add(AHandler);
end;

procedure TReplicateDataBindSource.RemoveChainNotify(const AHandler: TNotifyEvent);
begin
  FChainNotifies.Remove(AHandler);
end;

procedure TReplicateDataBindSource.Loaded;
begin
  inherited;
  BuildTableFromSchema;
end;

procedure TReplicateDataBindSource.DebugLog(const AMsg: string);
begin
  if FDebug then
    ReplicateDebugLog('[Data] ' + AMsg);
end;

procedure TReplicateDataBindSource.TableAfterPost(DataSet: TDataSet);
begin
  // Post is what makes LiveBindings refresh bound controls / downstream links.
  if Assigned(FOnStatusChanged) then
    FOnStatusChanged(Self);
end;

procedure TReplicateDataBindSource.HookInputFields;
var
  I: Integer;
begin
  if not FTable.Active then Exit;
  for I := 0 to FTable.FieldCount - 1 do
    if FTable.Fields[I].FieldName.StartsWith('Input_') then
      FTable.Fields[I].OnChange := InputFieldChanged;
end;

procedure TReplicateDataBindSource.InputFieldChanged(Sender: TField);
begin
  // If the change came from our own SetInputValue, that method handles it.
  // Otherwise the write came from a LiveBindings wire (upstream OutputImage
  // bound to this Input_ field in the designer): fire OnInputChanged and, with
  // AutoRun, launch this stage. Queue the Run so it happens after the current
  // edit/post settles, not mid-write.
  if FSettingInput then Exit;
  if csDesigning in ComponentState then Exit;

  if Assigned(FOnInputChanged) then
    FOnInputChanged(Self);

  if FAutoRun and not FIsRunning and not FInputRunQueued and (Trim(Sender.AsString) <> '') then
  begin
    FInputRunQueued := True;
    TThread.Queue(nil,
      procedure
      begin
        FInputRunQueued := False;
        if FAutoRun and not FIsRunning then
          try
            Run;
          except
            on E: Exception do DebugLog('AutoRun failed: ' + E.Message);
          end;
      end);
  end;
end;

function TReplicateDataBindSource.HasField(const AName: string): Boolean;
begin
  Result := FTable.Active and (FTable.FindField(AName) <> nil);
end;

procedure TReplicateDataBindSource.EnsureRow;
begin
  if not FTable.Active then Exit;
  if FTable.RecordCount = 0 then
  begin
    FTable.Append;
    FTable.Post;
  end;
end;

procedure TReplicateDataBindSource.PutField(const AName: string; const AValue: Variant);
begin
  if not HasField(AName) then Exit;
  BeginEdit;
  SetRaw(AName, AValue);
  EndEdit;
end;

procedure TReplicateDataBindSource.BeginEdit;
begin
  if not FTable.Active then Exit;
  EnsureRow;
  if not (FTable.State in [dsEdit, dsInsert]) then
    FTable.Edit;
end;

procedure TReplicateDataBindSource.SetRaw(const AName: string; const AValue: Variant);
begin
  // Assumes the table is already in edit (BeginEdit). No Post here, so a whole
  // batch of fields commits in a single Post.
  if HasField(AName) and (FTable.State in [dsEdit, dsInsert]) then
    FTable.FieldByName(AName).Value := AValue;
end;

procedure TReplicateDataBindSource.EndEdit;
begin
  if FTable.Active and (FTable.State in [dsEdit, dsInsert]) then
    FTable.Post;
end;

function TReplicateDataBindSource.GetFieldStr(const AName: string): string;
begin
  if HasField(AName) and (FTable.RecordCount > 0) then
    Result := FTable.FieldByName(AName).AsString
  else
    Result := '';
end;

procedure TReplicateDataBindSource.BuildTableFromSchema;

  procedure AddStr(const AName: string; ASize: Integer);
  begin
    if FTable.FieldDefs.IndexOf(AName) < 0 then
      FTable.FieldDefs.Add(AName, ftWideString, ASize);
  end;

  procedure AddMemo(const AName: string);
  begin
    if FTable.FieldDefs.IndexOf(AName) < 0 then
      FTable.FieldDefs.Add(AName, ftWideMemo);
  end;

var
  LJSON, LComponents, LSchemas, LInput, LProperties: TJSONObject;
  LPair: TJSONPair;
  LPropObj: TJSONObject;
  LType, LFieldName: string;
  I: Integer;
begin
  if csDestroying in ComponentState then Exit;

  FInputTypes.Clear;
  FTable.Close;
  FTable.FieldDefs.Clear;

  // Stable state + output fields (always present so the designer can bind them).
  AddStr('Status', 64);
  AddStr('IsRunning', 8);
  AddMemo('ErrorMessage');
  AddMemo('Logs');
  AddMemo('Output');
  AddStr('OutputImage', 2048);
  AddMemo('OutputText');

  // The two most common Replicate inputs, always present so they can be bound in
  // the designer even before a schema is fetched (and so a workflow chain wiring
  // survives with no token). Schema-specific inputs are added below in addition.
  AddMemo('Input_prompt');
  AddStr('Input_image', 2048);

  // Schema-driven input fields (dot-free, prefixed so they never collide with
  // state/output names and read clearly when chaining).
  if FCachedSchema <> '' then
  begin
    try
      LJSON := TJSONObject.ParseJSONValue(FCachedSchema) as TJSONObject;
      if LJSON <> nil then
      try
        LComponents := LJSON.GetValue('components') as TJSONObject;
        LInput := nil;
        if LComponents <> nil then
        begin
          LSchemas := LComponents.GetValue('schemas') as TJSONObject;
          if LSchemas <> nil then
            LInput := LSchemas.GetValue('Input') as TJSONObject;
        end
        else
          LInput := LJSON;

        if LInput <> nil then
        begin
          LProperties := LInput.GetValue('properties') as TJSONObject;
          if LProperties <> nil then
            for LPair in LProperties do
            begin
              LPropObj := LPair.JsonValue as TJSONObject;
              if LPropObj = nil then Continue;
              LType := LPropObj.GetValue<string>('type', 'string');
              LFieldName := 'Input_' + LPair.JsonString.Value;
              FInputTypes.AddOrSetValue(LFieldName, LType);
              AddMemo(LFieldName);
            end;
        end;
      finally
        LJSON.Free;
      end;
    except
      on E: Exception do
        DebugLog('BuildTableFromSchema: parse failed - ' + E.Message);
    end;
  end;

  FTable.CreateDataSet;
  FTable.Append;

  // Seed sensible defaults so bound getters never see null.
  for I := Low(CStateFields) to High(CStateFields) do
    if FTable.FindField(CStateFields[I]) <> nil then
      FTable.FieldByName(CStateFields[I]).AsString := '';
  FTable.FieldByName('IsRunning').AsString := 'false';
  for I := Low(COutputFields) to High(COutputFields) do
    FTable.FieldByName(COutputFields[I]).AsString := '';

  // Input defaults from schema.
  if FCachedSchema <> '' then
  begin
    LJSON := TJSONObject.ParseJSONValue(FCachedSchema) as TJSONObject;
    if LJSON <> nil then
    try
      LComponents := LJSON.GetValue('components') as TJSONObject;
      LInput := nil;
      if LComponents <> nil then
      begin
        LSchemas := LComponents.GetValue('schemas') as TJSONObject;
        if LSchemas <> nil then
          LInput := LSchemas.GetValue('Input') as TJSONObject;
      end
      else
        LInput := LJSON;
      if LInput <> nil then
      begin
        LProperties := LInput.GetValue('properties') as TJSONObject;
        if LProperties <> nil then
          for LPair in LProperties do
          begin
            LPropObj := LPair.JsonValue as TJSONObject;
            if LPropObj = nil then Continue;
            var LDef := LPropObj.GetValue('default');
            LFieldName := 'Input_' + LPair.JsonString.Value;
            if (LDef <> nil) and (FTable.FindField(LFieldName) <> nil) then
              FTable.FieldByName(LFieldName).AsString := LDef.Value;
          end;
      end;
    finally
      LJSON.Free;
    end;
  end;

  FTable.Post;
  HookInputFields; // after defaults are seeded + posted, so seeding does not auto-run
  DebugLog(Format('BuildTableFromSchema: %d fields', [FTable.FieldCount]));
end;

procedure TReplicateDataBindSource.RebuildFromSchema;
begin
  BuildTableFromSchema;
end;

procedure TReplicateDataBindSource.SetApiToken(const AValue: string);
begin
  FApiToken := AValue;
end;

procedure TReplicateDataBindSource.SetModel(const AValue: string);
begin
  if FModel = AValue then Exit;
  FModel := AValue;

  // At design time, fetch the schema as soon as a model is set (e.g. via the
  // model picker) so the input/output fields exist and appear in the
  // LiveBindings Designer. The result is stored in CachedSchema, which persists
  // in the form, so the fields are still there when reopened without a token.
  if (csDesigning in ComponentState) and not (csLoading in ComponentState) and (FModel <> '') then
  begin
    if FApiToken = '' then
      FApiToken := GetEnvironmentVariable('REPLICATE_API_TOKEN');
    if FApiToken <> '' then
    try
      FetchSchema;
      BuildTableFromSchema;
    except
      // Ignore fetch errors at design time - the developer may fix the token
      // and re-pick the model.
    end;
  end;
end;

procedure TReplicateDataBindSource.SetVersion(const AValue: string);
begin
  FVersion := AValue;
end;

procedure TReplicateDataBindSource.SetCachedSchema(const AValue: string);
begin
  if FCachedSchema <> AValue then
  begin
    FCachedSchema := AValue;
    BuildTableFromSchema;
  end;
end;

procedure TReplicateDataBindSource.LoadSchema;
begin
  DebugLog(Format('LoadSchema: model="%s" version="%s"', [FModel, FVersion]));
  FetchSchema;
  BuildTableFromSchema;
end;

procedure TReplicateDataBindSource.FetchSchema;
var
  LHTTP: THTTPClient;
  LURL: string;
  LResponse: IHTTPResponse;
  LJSON, LLatestVer: TJSONObject;
  LVal: TJSONValue;
  LOwner, LName, LVerId: string;
begin
  if FModel = '' then Exit;
  ParseModelString(FModel, LOwner, LName, LVerId);
  if LVerId = '' then LVerId := FVersion;

  LHTTP := THTTPClient.Create;
  try
    LHTTP.CustomHeaders['Authorization'] := 'Bearer ' + FApiToken;
    LHTTP.CustomHeaders['Accept'] := 'application/json';
    if LVerId <> '' then
      LURL := Format('https://api.replicate.com/v1/models/%s/%s/versions/%s', [LOwner, LName, LVerId])
    else
      LURL := Format('https://api.replicate.com/v1/models/%s/%s', [LOwner, LName]);

    DebugLog('FetchSchema: GET ' + LURL);
    LResponse := LHTTP.Get(LURL);
    DebugLog(Format('FetchSchema: HTTP %d', [LResponse.StatusCode]));
    if LResponse.StatusCode = 200 then
    begin
      LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
      try
        if LJSON <> nil then
        begin
          if LVerId <> '' then
          begin
            LVal := LJSON.GetValue('openapi_schema');
            if LVal is TJSONObject then
            begin
              FCachedSchema := LVal.ToJSON;
              FActualVersion := LJSON.GetValue<string>('id', '');
            end;
          end
          else
          begin
            LVal := LJSON.GetValue('latest_version');
            if LVal is TJSONObject then
            begin
              LLatestVer := LVal as TJSONObject;
              LVal := LLatestVer.GetValue('openapi_schema');
              if LVal is TJSONObject then
              begin
                FCachedSchema := LVal.ToJSON;
                FActualVersion := LLatestVer.GetValue<string>('id', '');
              end;
            end;
          end;
        end;
      finally
        LJSON.Free;
      end;
    end
    else
      raise Exception.CreateFmt('Failed to fetch Replicate schema: %d %s',
        [LResponse.StatusCode, LResponse.ContentAsString]);
  finally
    LHTTP.Free;
  end;
end;

function TReplicateDataBindSource.SerializeInputs: TJSONObject;
var
  LInputJSON: TJSONObject;
  LRawName, LStrVal, LType: string;
  I: Integer;
  LField: TField;
begin
  LInputJSON := TJSONObject.Create;
  try
    // Iterate the actual Input_ dataset fields (so the always-present stable
    // inputs are sent too, not only schema-declared ones). Type comes from the
    // schema when known, else defaults to string.
    if FTable.Active then
      for I := 0 to FTable.FieldCount - 1 do
      begin
        LField := FTable.Fields[I];
        if not LField.FieldName.StartsWith('Input_') then Continue;
        LStrVal := LField.AsString;
        if LStrVal = '' then Continue;
        LRawName := LField.FieldName.Substring(Length('Input_'));
        if not FInputTypes.TryGetValue(LField.FieldName, LType) then
          LType := 'string';

        if LType = 'integer' then
          LInputJSON.AddPair(LRawName, TJSONNumber.Create(StrToInt64Def(LStrVal, 0)))
        else if LType = 'number' then
          LInputJSON.AddPair(LRawName, TJSONNumber.Create(StrToFloatDef(LStrVal, 0.0)))
        else if LType = 'boolean' then
        begin
          if SameText(LStrVal, 'true') then
            LInputJSON.AddPair(LRawName, TJSONTrue.Create)
          else
            LInputJSON.AddPair(LRawName, TJSONFalse.Create);
        end
        else
        begin
          if TFile.Exists(LStrVal) then
            LStrVal := FileToBase64URI(LStrVal);
          LInputJSON.AddPair(LRawName, LStrVal);
        end;
      end;
    Result := LInputJSON;
  except
    LInputJSON.Free;
    raise;
  end;
end;

procedure TReplicateDataBindSource.SetInputValue(const AName, AValue: string);
var
  LFieldName: string;
begin
  if AName.StartsWith('Input_') then
    LFieldName := AName
  else
    LFieldName := 'Input_' + AName;
  if HasField(LFieldName) then
  begin
    // Guard so the field OnChange handler does not also fire for our own write
    // (it handles only the designer-binding write path).
    FSettingInput := True;
    try
      PutField(LFieldName, AValue);
    finally
      FSettingInput := False;
    end;
    if Assigned(FOnInputChanged) then
      FOnInputChanged(Self);
    // Only auto-run on a non-empty value: a designer chain binding fires on
    // every upstream Post, including the empty 'starting'/'processing' states,
    // and we must not launch this stage until the real input arrives.
    if FAutoRun and not FIsRunning and (AValue <> '') then
      Run;
  end
  else
    raise Exception.CreateFmt('Input "%s" not found.', [AName]);
end;

procedure TReplicateDataBindSource.TrySetInputValue(const AName, AValue: string);
var
  LFieldName: string;
begin
  // Binding-safe: never raises if the model has no such input (a property
  // setter driven by a LiveBindings link must not throw).
  if AName.StartsWith('Input_') then LFieldName := AName else LFieldName := 'Input_' + AName;
  if HasField(LFieldName) then
    SetInputValue(AName, AValue);
end;

function TReplicateDataBindSource.GetInputImage: string;
begin
  Result := GetFieldStr('Input_image');
end;

procedure TReplicateDataBindSource.SetInputImage(const AValue: string);
begin
  TrySetInputValue('image', AValue);
end;

function TReplicateDataBindSource.GetInputPrompt: string;
begin
  Result := GetFieldStr('Input_prompt');
end;

procedure TReplicateDataBindSource.SetInputPrompt(const AValue: string);
begin
  TrySetInputValue('prompt', AValue);
end;

function TReplicateDataBindSource.GetOutputValue(const AName: string): string;
begin
  if SameText(AName, 'image') then Result := GetFieldStr('OutputImage')
  else if SameText(AName, 'text') then Result := GetFieldStr('OutputText')
  else if AName.StartsWith('Output') then Result := GetFieldStr(AName)
  else Result := GetFieldStr('Output' + AName);
end;

procedure TReplicateDataBindSource.Run;
begin
  if FIsRunning then
    raise Exception.Create('Prediction is already running.');
  if FApiToken = '' then
    FApiToken := GetEnvironmentVariable('REPLICATE_API_TOKEN');
  if FApiToken = '' then
    raise Exception.Create('Replicate API Token is not configured.');

  FIsRunning := True;
  BeginEdit;
  SetRaw('Status', 'starting');
  SetRaw('IsRunning', 'true');
  SetRaw('ErrorMessage', '');
  SetRaw('Logs', '');
  EndEdit;
  if Assigned(FOnStatusChanged) then FOnStatusChanged(Self);

  DebugLog(Format('Run: model="%s" actualVersion="%s"', [FModel, FActualVersion]));

  System.Threading.TTask.Run(
    procedure
    begin
      try
        ExecutePrediction;
      except
        on E: Exception do
        begin
          var LErrMsg := E.Message;
          DebugLog('Run: FAILED - ' + LErrMsg);
          TThread.Queue(nil,
            procedure
            begin
              FIsRunning := False;
              BeginEdit;
              SetRaw('Status', 'failed');
              SetRaw('IsRunning', 'false');
              SetRaw('ErrorMessage', LErrMsg);
              SetRaw('Logs', 'ERROR: ' + LErrMsg);
              EndEdit;
              if Assigned(FOnStatusChanged) then FOnStatusChanged(Self);
            end);
        end;
      end;
    end);
end;

procedure TReplicateDataBindSource.ExecutePrediction;
var
  LHTTP: THTTPClient;
  LPostData, LInputJSON, LRespJSON, LUrls: TJSONObject;
  LResponse: IHTTPResponse;
  LStatus, LId, LPollURL, LPostVersion, LPostURL, LOwner, LName, LVerId: string;
  LOutputVal, LErrVal, LLogsVal: TJSONValue;
  LStream: TStringStream;
begin
  LHTTP := THTTPClient.Create;
  LPostData := TJSONObject.Create;
  try
    LHTTP.CustomHeaders['Authorization'] := 'Bearer ' + FApiToken;
    LHTTP.CustomHeaders['Content-Type'] := 'application/json';
    LHTTP.ContentType := 'application/json';

    ParseModelString(FModel, LOwner, LName, LVerId);
    LPostVersion := FActualVersion;
    if LPostVersion = '' then LPostVersion := LVerId;
    if LPostVersion = '' then LPostVersion := FVersion;

    if LPostVersion <> '' then
    begin
      LPostData.AddPair('version', LPostVersion);
      LPostURL := 'https://api.replicate.com/v1/predictions';
    end
    else
    begin
      if (LOwner = '') or (LName = '') then
        raise Exception.Create('No model configured. Set Model to "owner/name" or "owner/name:version".');
      LPostURL := Format('https://api.replicate.com/v1/models/%s/%s/predictions', [LOwner, LName]);
    end;

    LInputJSON := SerializeInputs;
    LPostData.AddPair('input', LInputJSON);

    DebugLog('ExecutePrediction: POST ' + LPostURL);
    DebugLog('ExecutePrediction: body ' + TruncS(LPostData.ToJSON, 600));

    LStream := TStringStream.Create(LPostData.ToJSON, TEncoding.UTF8);
    try
      LResponse := LHTTP.Post(LPostURL, LStream);
    finally
      LStream.Free;
    end;

    DebugLog(Format('ExecutePrediction: HTTP %d %s',
      [LResponse.StatusCode, TruncS(LResponse.ContentAsString, 400)]));

    if LResponse.StatusCode <> 201 then
      raise Exception.CreateFmt('Failed to start Replicate prediction: %d %s',
        [LResponse.StatusCode, LResponse.ContentAsString]);

    LRespJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
    try
      LId := LRespJSON.GetValue<string>('id', '');
      LStatus := LRespJSON.GetValue<string>('status', 'starting');
      LPollURL := 'https://api.replicate.com/v1/predictions/' + LId;
      if LRespJSON.TryGetValue<TJSONObject>('urls', LUrls) then
        LPollURL := LUrls.GetValue<string>('get', LPollURL);

      UpdateState(LStatus, '', '', nil);

      while (LStatus = 'starting') or (LStatus = 'processing') do
      begin
        TThread.Sleep(1500);
        LResponse := LHTTP.Get(LPollURL);
        if LResponse.StatusCode = 200 then
        begin
          var LPollJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
          if LPollJSON <> nil then
          try
            LStatus := LPollJSON.GetValue<string>('status', 'starting');
            var LLogs := '';
            LLogsVal := LPollJSON.GetValue('logs');
            if (LLogsVal <> nil) and not (LLogsVal is TJSONNull) then LLogs := LLogsVal.Value;
            var LErr := '';
            LErrVal := LPollJSON.GetValue('error');
            if (LErrVal <> nil) and not (LErrVal is TJSONNull) then LErr := LErrVal.Value;
            LOutputVal := LPollJSON.GetValue('output');
            if LOutputVal is TJSONNull then LOutputVal := nil;
            DebugLog(Format('Poll: status="%s" hasOutput=%s', [LStatus, BoolToStr(LOutputVal <> nil, True)]));
            UpdateState(LStatus, LLogs, LErr, LOutputVal);
          finally
            LPollJSON.Free;
          end;
        end
        else
          DebugLog(Format('Poll: HTTP %d', [LResponse.StatusCode]));
      end;
    finally
      LRespJSON.Free;
    end;
  finally
    LPostData.Free;
    LHTTP.Free;
  end;
end;

procedure TReplicateDataBindSource.UpdateState(const AStatus, ALogs, AError: string; AOutputVal: TJSONValue);
var
  LOutputCopy: TJSONValue;
begin
  LOutputCopy := nil;
  if AOutputVal <> nil then
    LOutputCopy := AOutputVal.Clone as TJSONValue;

  TThread.Queue(nil,
    procedure
    begin
      try
        // One batched edit for the whole state update, so the bound image
        // converter refreshes (and downloads) at most once per poll instead of
        // once per field.
        BeginEdit;
        SetRaw('Status', AStatus);
        if AError <> '' then
        begin
          SetRaw('ErrorMessage', AError);
          SetRaw('Logs', ALogs + IfThen(ALogs <> '', sLineBreak, '') + 'ERROR: ' + AError);
        end
        else
          SetRaw('Logs', ALogs);

        if (AStatus = 'succeeded') or (AStatus = 'failed') or (AStatus = 'canceled') then
        begin
          FIsRunning := False;
          SetRaw('IsRunning', 'false');
        end;

        if LOutputCopy <> nil then
          ParseOutput(LOutputCopy); // uses SetRaw, no Post
        EndEdit; // single Post -> single refresh

        if Assigned(FOnStatusChanged) then FOnStatusChanged(Self);
        if AStatus = 'succeeded' then
        begin
          if Assigned(FOnCompleted) then FOnCompleted(Self);
          // Notify edge components (workflow chain) after outputs are posted.
          for var LH in FChainNotifies.ToArray do
            LH(Self);
        end;
      finally
        LOutputCopy.Free;
      end;
    end);
end;

procedure TReplicateDataBindSource.ParseOutput(AOutputVal: TJSONValue);
var
  LArr: TJSONArray;
  LObj: TJSONObject;
  LPair: TJSONPair;
  LStr: string;
  I: Integer;
begin
  if AOutputVal = nil then Exit;

  // NOTE: uses SetRaw (no Post). The caller wraps this in BeginEdit/EndEdit so
  // the whole output commits in a single Post -> one converter refresh.
  if AOutputVal is TJSONArray then
  begin
    LArr := AOutputVal as TJSONArray;
    DebugLog(Format('ParseOutput: array %d item(s)', [LArr.Count]));
    if LArr.Count > 0 then
    begin
      SetRaw('Output', LArr.Items[0].Value);
      SetRaw('OutputImage', LArr.Items[0].Value);
      LStr := '';
      for I := 0 to LArr.Count - 1 do
      begin
        if I > 0 then LStr := LStr + ' ';
        LStr := LStr + LArr.Items[I].Value;
      end;
      SetRaw('OutputText', LStr);
    end;
  end
  else if AOutputVal is TJSONObject then
  begin
    LObj := AOutputVal as TJSONObject;
    DebugLog('ParseOutput: object ' + TruncS(LObj.ToJSON, 200));
    SetRaw('Output', LObj.ToJSON);
    for LPair in LObj do
    begin
      // Map object keys onto dynamic Output_<key> fields when present.
      if HasField('Output_' + LPair.JsonString.Value) then
        SetRaw('Output_' + LPair.JsonString.Value, LPair.JsonValue.Value);
      if SameText(LPair.JsonString.Value, 'image') then SetRaw('OutputImage', LPair.JsonValue.Value);
      if SameText(LPair.JsonString.Value, 'text') then SetRaw('OutputText', LPair.JsonValue.Value);
    end;
  end
  else
  begin
    LStr := AOutputVal.Value;
    DebugLog('ParseOutput: value ' + TruncS(LStr, 200));
    SetRaw('Output', LStr);
    SetRaw('OutputImage', LStr);
    SetRaw('OutputText', LStr);
  end;
end;

{ TReplicateWorkflowLink }

constructor TReplicateWorkflowLink.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FInputName := 'image';
  FSourceOutput := 'image';
end;

destructor TReplicateWorkflowLink.Destroy;
begin
  Unhook;
  inherited;
end;

procedure TReplicateWorkflowLink.Loaded;
begin
  inherited;
  if not (csDesigning in ComponentState) then
    Hook;
end;

procedure TReplicateWorkflowLink.Hook;
begin
  if FHooked or (FSource = nil) then Exit;
  FSource.AddChainNotify(SourceCompleted);
  FHooked := True;
end;

procedure TReplicateWorkflowLink.Unhook;
begin
  if FHooked and (FSource <> nil) then
    FSource.RemoveChainNotify(SourceCompleted);
  FHooked := False;
end;

procedure TReplicateWorkflowLink.SetSource(const AValue: TReplicateDataBindSource);
begin
  if FSource = AValue then Exit;
  Unhook;
  if FSource <> nil then
    FSource.RemoveFreeNotification(Self);
  FSource := AValue;
  if FSource <> nil then
    FSource.FreeNotification(Self);
  if not (csLoading in ComponentState) and not (csDesigning in ComponentState) then
    Hook;
end;

procedure TReplicateWorkflowLink.SetTarget(const AValue: TReplicateDataBindSource);
begin
  if FTarget <> nil then
    FTarget.RemoveFreeNotification(Self);
  FTarget := AValue;
  if FTarget <> nil then
    FTarget.FreeNotification(Self);
end;

procedure TReplicateWorkflowLink.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FSource then begin Unhook; FSource := nil; end;
    if AComponent = FTarget then FTarget := nil;
  end;
end;

procedure TReplicateWorkflowLink.SourceCompleted(Sender: TObject);
var
  LValue: string;
begin
  // Source stage finished: read its chosen output and feed the target's input.
  // Target.AutoRun then launches the next stage. TrySetInputValue is a no-op if
  // the target lacks that input.
  if (FSource = nil) or (FTarget = nil) then Exit;
  LValue := FSource.GetOutputValue(FSourceOutput);
  if LValue <> '' then
    FTarget.TrySetInputValue(FInputName, LValue);
end;

procedure Register;
begin
  RegisterComponents('Replicate', [TReplicateDataBindSource, TReplicateWorkflowLink]);
end;

end.
