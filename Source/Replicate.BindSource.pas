unit Replicate.BindSource;

interface

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.Threading,
  System.SyncObjs,
  System.Generics.Collections,
  System.TypInfo,
  System.Rtti,
  System.NetEncoding,
  System.IOUtils,
  Data.Bind.Components,
  Data.Bind.ObjectScope,
  System.Bindings.Outputs,
  System.Bindings.Helper;

type
  TReplicateDebugEvent = procedure(Sender: TObject; const AMessage: string) of object;

  TReplicateParam = class
  private
    FName: string;
    FJsonType: string;
    FValue: TValue;
    FIsReadOnly: Boolean;
    FDefaultValue: TValue;
    FAssigned: Boolean;
    procedure SetValue(const AValue: TValue);
  public
    constructor Create(const AName, AJsonType: string; AIsReadOnly: Boolean);
    // Safe accessors for binding getters: never raise EInvalidCast,
    // fall back to the type's zero value on an empty or mismatched TValue.
    function AsStringValue: string;
    function AsIntegerValue: Integer;
    function AsFloatValue: Double;
    function AsBooleanValue: Boolean;
    procedure ResetToDefault;
    property Name: string read FName write FName;
    property JsonType: string read FJsonType write FJsonType;
    property Value: TValue read FValue write SetValue;
    property IsReadOnly: Boolean read FIsReadOnly write FIsReadOnly;
    property DefaultValue: TValue read FDefaultValue write FDefaultValue;
    // True once a value has been written (schema default or user/API),
    // so unset inputs can be omitted from the prediction request.
    property IsAssigned: Boolean read FAssigned;
  end;

  TReplicateAdapter = class(TBindSourceAdapter)
  private
    FParams: TObjectList<TReplicateParam>;
  protected
    procedure CreateReadOnlyField<T>(const AFieldName: string;
      const AGetMemberObject: IGetMemberObject; AMemberType: TScopeMemberType;
      const AGetterFunc: TFunc<T>);
    procedure CreateReadWriteField<T>(const AFieldName: string;
      const AGetMemberObject: IGetMemberObject; AMemberType: TScopeMemberType;
      const AGetterFunc: TFunc<T>; const ASetterProc: TProc<T>);
  public
    constructor Create(AOwner: TComponent); override;
    procedure AddFields;
    function GetCanActivate: Boolean; override;
    function GetCanModify: Boolean; override;
    function GetCount: Integer; override;
  end;

  TReplicateBindSource = class(TBaseObjectBindSource)
  private
    FAdapter: TReplicateAdapter;
    FParams: TObjectList<TReplicateParam>;
    FApiToken: string;
    FModel: string;
    FVersion: string;
    FActualVersion: string;
    FCachedSchema: string;
    FIsRunning: Boolean;
    FStatus: string;
    FErrorMessage: string;
    FLogs: string;
    FOnCompleted: TNotifyEvent;
    FOnStatusChanged: TNotifyEvent;
    FDebug: Boolean;
    FOnDebugLog: TReplicateDebugEvent;

    procedure SetModel(const AValue: string);
    procedure SetVersion(const AValue: string);
    procedure SetCachedSchema(const AValue: string);
    procedure SetApiToken(const AValue: string);
    procedure SetDebug(const AValue: Boolean);
    procedure DebugLog(const AMsg: string);
    procedure FetchSchema;
    function SerializeInputs: TJSONObject;
    procedure ExecutePrediction;
    procedure UpdatePredictionState(const AStatus, ALogs, AError: string; AOutputVal: TJSONValue);
    procedure ParseOutputValue(AOutputVal: TJSONValue);
    procedure SetOutputParamValue(const AName: string; const AValue: TValue);
    function EnsureParam(const AName, AJsonType: string; AReadOnly: Boolean): TReplicateParam;
  protected
    function GetInternalAdapter: TBindSourceAdapter; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure RebuildFromSchema;
    procedure LoadSchema;
    procedure Loaded; override;
    procedure Run;
    procedure NotifyChanged;

    procedure SetInputValue(const AName: string; const AValue: TValue);
    function GetOutputValue(const AName: string): TValue;

    property ActualVersion: string read FActualVersion;
  published
    property ApiToken: string read FApiToken write SetApiToken;
    property Model: string read FModel write SetModel;
    property Version: string read FVersion write SetVersion;
    property CachedSchema: string read FCachedSchema write SetCachedSchema;
    
    property IsRunning: Boolean read FIsRunning;
    property Status: string read FStatus;
    property ErrorMessage: string read FErrorMessage;
    property Logs: string read FLogs;
    property OnCompleted: TNotifyEvent read FOnCompleted write FOnCompleted;
    // Fired on the main thread whenever Status/Logs/ErrorMessage/output change
    // (initial 'starting', each poll, and the terminal state). The reliable way
    // to push async results into the UI: read Status/Logs/GetOutputValue and
    // assign to controls, or LoadUrlOrFileToBitmap for an image URL. This does
    // not depend on LiveBindings and always reflects the current values.
    property OnStatusChanged: TNotifyEvent read FOnStatusChanged write FOnStatusChanged;
    property Debug: Boolean read FDebug write SetDebug default False;
    property OnDebugLog: TReplicateDebugEvent read FOnDebugLog write FOnDebugLog;
  end;

procedure Register;

// Global debug sink shared by the component, its adapter and the URL->bitmap
// converters. Assign ReplicateDebugHook to receive every diagnostic line
// (always delivered on the main thread), or set TReplicateBindSource.Debug to
// True to emit lines via OutputDebugString (IDE Event Log on Windows).
var
  ReplicateDebugHook: TProc<string>;
  ReplicateDebugEnabled: Boolean = False;

procedure ReplicateDebugLog(const AMsg: string);

// Loads a URL (downloaded) or local file into any object that exposes a
// LoadFromStream method (FMX TBitmap, VCL TBitmap, VCL TPicture, ...).
// This is the same routine the registered LiveBindings converters use;
// call it directly if you prefer not to rely on converter registration.
procedure LoadUrlOrFileToBitmap(const AUrlOrFile: string; ABitmap: TObject);

implementation

var
  GConverterRegInfo: string = 'URL converters: not yet registered';

function TruncS(const S: string; AMax: Integer): string;
begin
  if Length(S) <= AMax then
    Result := S
  else
    Result := S.Substring(0, AMax) + Format('...(%d chars total)', [Length(S)]);
end;

procedure ReplicateDebugLog(const AMsg: string);
var
  LLine: string;
begin
  if not ReplicateDebugEnabled and not Assigned(ReplicateDebugHook) then
    Exit;
  LLine := FormatDateTime('[hh:nn:ss.zzz] ', Now) + AMsg;
{$IFDEF MSWINDOWS}
  if ReplicateDebugEnabled then
    OutputDebugString(PChar('LiveReplicate ' + LLine));
{$ENDIF}
  if Assigned(ReplicateDebugHook) then
  begin
    if TThread.CurrentThread.ThreadID = MainThreadID then
      ReplicateDebugHook(LLine)
    else
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(ReplicateDebugHook) then
            ReplicateDebugHook(LLine);
        end);
  end;
end;

{ TReplicateParam }

constructor TReplicateParam.Create(const AName, AJsonType: string; AIsReadOnly: Boolean);
begin
  FName := AName;
  FJsonType := AJsonType;
  FIsReadOnly := AIsReadOnly;
  // Seed with a typed zero value so binding getters never see TValue.Empty,
  // which cannot be cast to string/Integer/Double/Boolean (EInvalidCast).
  if AJsonType = 'integer' then
    FDefaultValue := TValue.From<Integer>(0)
  else if AJsonType = 'number' then
    FDefaultValue := TValue.From<Double>(0.0)
  else if AJsonType = 'boolean' then
    FDefaultValue := TValue.From<Boolean>(False)
  else
    FDefaultValue := TValue.From<string>('');
  FValue := FDefaultValue;
  FAssigned := False;
end;

procedure TReplicateParam.SetValue(const AValue: TValue);
begin
  FValue := AValue;
  FAssigned := True;
end;

procedure TReplicateParam.ResetToDefault;
begin
  FValue := FDefaultValue;
  FAssigned := False;
end;

function TReplicateParam.AsStringValue: string;
begin
  if FValue.IsEmpty or not FValue.TryAsType<string>(Result) then
    Result := '';
end;

function TReplicateParam.AsIntegerValue: Integer;
begin
  if FValue.IsEmpty or not FValue.TryAsType<Integer>(Result) then
    Result := 0;
end;

function TReplicateParam.AsFloatValue: Double;
begin
  if FValue.IsEmpty or not FValue.TryAsType<Double>(Result) then
    Result := 0.0;
end;

function TReplicateParam.AsBooleanValue: Boolean;
begin
  if FValue.IsEmpty or not FValue.TryAsType<Boolean>(Result) then
    Result := False;
end;

{ TReplicateAdapter }

constructor TReplicateAdapter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
end;

procedure TReplicateAdapter.AddFields;
var
  P: TReplicateParam;
  LGetMemberObject: IGetMemberObject;
begin
  if FParams = nil then Exit;

  LGetMemberObject := TBindSourceAdapterGetMemberObject.Create(Self);

  for P in FParams do
  begin
    var LParam := P; // local capture for closures

    // Additive: never destroy existing fields. If a field already exists for
    // this param name, a link may be bound to it - recreating it would orphan
    // that link, leaving it reading an empty, dead object forever. Skip so
    // bound fields persist and keep reading live values from their param.
    if FindField(LParam.Name) <> nil then
      Continue;

    if LParam.IsReadOnly then
    begin
      if LParam.JsonType = 'string' then
      begin
        CreateReadOnlyField<string>(LParam.Name, LGetMemberObject, TScopeMemberType.mtText,
          function: string
          begin
            Result := LParam.AsStringValue;
          end);
      end
      else if LParam.JsonType = 'integer' then
      begin
        CreateReadOnlyField<Integer>(LParam.Name, LGetMemberObject, TScopeMemberType.mtInteger,
          function: Integer
          begin
            Result := LParam.AsIntegerValue;
          end);
      end
      else if LParam.JsonType = 'number' then
      begin
        CreateReadOnlyField<Double>(LParam.Name, LGetMemberObject, TScopeMemberType.mtFloat,
          function: Double
          begin
            Result := LParam.AsFloatValue;
          end);
      end
      else if LParam.JsonType = 'boolean' then
      begin
        CreateReadOnlyField<Boolean>(LParam.Name, LGetMemberObject, TScopeMemberType.mtBoolean,
          function: Boolean
          begin
            Result := LParam.AsBooleanValue;
          end);
      end;
    end
    else
    begin
      if LParam.JsonType = 'string' then
      begin
        CreateReadWriteField<string>(LParam.Name, LGetMemberObject, TScopeMemberType.mtText,
          function: string
          begin
            Result := LParam.AsStringValue;
          end,
          procedure(AValue: string)
          begin
            LParam.Value := TValue.From<string>(AValue);
          end);
      end
      else if LParam.JsonType = 'integer' then
      begin
        CreateReadWriteField<Integer>(LParam.Name, LGetMemberObject, TScopeMemberType.mtInteger,
          function: Integer
          begin
            Result := LParam.AsIntegerValue;
          end,
          procedure(AValue: Integer)
          begin
            LParam.Value := TValue.From<Integer>(AValue);
          end);
      end
      else if LParam.JsonType = 'number' then
      begin
        CreateReadWriteField<Double>(LParam.Name, LGetMemberObject, TScopeMemberType.mtFloat,
          function: Double
          begin
            Result := LParam.AsFloatValue;
          end,
          procedure(AValue: Double)
          begin
            LParam.Value := TValue.From<Double>(AValue);
          end);
      end
      else if LParam.JsonType = 'boolean' then
      begin
        CreateReadWriteField<Boolean>(LParam.Name, LGetMemberObject, TScopeMemberType.mtBoolean,
          function: Boolean
          begin
            Result := LParam.AsBooleanValue;
          end,
          procedure(AValue: Boolean)
          begin
            LParam.Value := TValue.From<Boolean>(AValue);
          end);
      end;
    end;
  end;

  ReplicateDebugLog(Format('Adapter.AddFields: %d bindable fields present', [Fields.Count]));
end;

procedure TReplicateAdapter.CreateReadOnlyField<T>(const AFieldName: string;
  const AGetMemberObject: IGetMemberObject; AMemberType: TScopeMemberType;
  const AGetterFunc: TFunc<T>);
var
  LField: TBindSourceAdapterReadField<T>;
  LParamReader: TValueReader<T>;
  LTypeInfo: PTypeInfo;
begin
  LParamReader := TValueReaderFunc<T>.Create(AFieldName,
    function(AName: string): T
    begin
      Result := AGetterFunc();
    end);

  LTypeInfo := System.TypeInfo(T);
  LField := TBindSourceAdapterReadField<T>.Create(Self, AFieldName,
    TBindSourceAdapterFieldType.Create(LTypeInfo.NameFld.ToString, LTypeInfo.Kind),
    AGetMemberObject, LParamReader, AMemberType);

  Fields.Add(LField);
end;

procedure TReplicateAdapter.CreateReadWriteField<T>(const AFieldName: string;
  const AGetMemberObject: IGetMemberObject; AMemberType: TScopeMemberType;
  const AGetterFunc: TFunc<T>; const ASetterProc: TProc<T>);
var
  LField: TBindSourceAdapterReadWriteField<T>;
  LParamReader: TValueReader<T>;
  LParamWriter: TValueWriter<T>;
  LTypeInfo: PTypeInfo;
begin
  LParamReader := TValueReaderFunc<T>.Create(AFieldName,
    function(AName: string): T
    begin
      Result := AGetterFunc();
    end);

  LParamWriter := TValueWriterProc<T>.Create(AFieldName,
    procedure(AName: string; AValue: T)
    begin
      ASetterProc(AValue);
    end);

  LTypeInfo := System.TypeInfo(T);
  LField := TBindSourceAdapterReadWriteField<T>.Create(Self, AFieldName,
    TBindSourceAdapterFieldType.Create(LTypeInfo.NameFld.ToString, LTypeInfo.Kind),
    AGetMemberObject, LParamReader, LParamWriter, AMemberType);

  Fields.Add(LField);
end;

function TReplicateAdapter.GetCanActivate: Boolean;
begin
  Result := True;
end;

function TReplicateAdapter.GetCanModify: Boolean;
begin
  Result := True;
end;

function TReplicateAdapter.GetCount: Integer;
begin
  Result := 1;
end;
{ TReplicateBindSource }

constructor TReplicateBindSource.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FParams := TObjectList<TReplicateParam>.Create(True);
  FAdapter := TReplicateAdapter.Create(Self);
  FAdapter.FParams := FParams;
  FAdapter.AutoPost := True;

  FApiToken := '';
  FModel := '';
  FVersion := '';
  FCachedSchema := '';

  FIsRunning := False;
  FStatus := '';
  FErrorMessage := '';
  FLogs := '';

  RebuildFromSchema;
end;

destructor TReplicateBindSource.Destroy;
begin
  FAdapter.Free;
  FParams.Free;
  inherited;
end;

function TReplicateBindSource.GetInternalAdapter: TBindSourceAdapter;
begin
  Result := FAdapter;
  if Result <> nil then
    ConnectAdapter(Result);
end;

procedure TReplicateBindSource.LoadSchema;
begin
  DebugLog(Format('LoadSchema: model="%s" version="%s"', [FModel, FVersion]));
  FetchSchema;
  RebuildFromSchema;
end;

procedure TReplicateBindSource.Loaded;
begin
  inherited;
  RebuildFromSchema;
end;

procedure TReplicateBindSource.SetDebug(const AValue: Boolean);
begin
  FDebug := AValue;
  if AValue then
  begin
    ReplicateDebugEnabled := True;
    ReplicateDebugLog(GConverterRegInfo);
  end;
end;

procedure TReplicateBindSource.DebugLog(const AMsg: string);
var
  LMsg: string;
begin
  if not (FDebug or Assigned(FOnDebugLog)) then
    Exit;
  ReplicateDebugLog(AMsg);
  if Assigned(FOnDebugLog) then
  begin
    if TThread.CurrentThread.ThreadID = MainThreadID then
      FOnDebugLog(Self, AMsg)
    else
    begin
      LMsg := AMsg;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(FOnDebugLog) then
            FOnDebugLog(Self, LMsg);
        end);
    end;
  end;
end;

procedure TReplicateBindSource.SetApiToken(const AValue: string);
begin
  FApiToken := AValue;
end;

procedure ParseModelString(const AModelStr: string; out AOwner, AName, AVerId: string);
var
  LParts: TArray<string>;
  LSubParts: TArray<string>;
begin
  AOwner := '';
  AName := '';
  AVerId := '';
  
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

procedure TReplicateBindSource.FetchSchema;
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
  if LVerId = '' then
    LVerId := FVersion;

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
      DebugLog(Format('FetchSchema: cached schema %d chars, actual version "%s"', [Length(FCachedSchema), FActualVersion]));
    end
    else
      raise Exception.CreateFmt('Failed to fetch Replicate schema: %d %s', [LResponse.StatusCode, LResponse.ContentAsString]);
  finally
    LHTTP.Free;
  end;
end;

function TReplicateBindSource.EnsureParam(const AName, AJsonType: string; AReadOnly: Boolean): TReplicateParam;
var
  P: TReplicateParam;
begin
  // Reuse an existing param object by name so any field/link already bound to
  // it stays live; only create one when it does not exist yet.
  for P in FParams do
    if P.Name = AName then
      Exit(P);
  Result := TReplicateParam.Create(AName, AJsonType, AReadOnly);
  FParams.Add(Result);
end;

procedure TReplicateBindSource.RebuildFromSchema;
var
  LJSON, LComponents, LSchemas, LInput, LProperties, LOutput: TJSONObject;
  LPair: TJSONPair;
  LParam: TReplicateParam;
  LPropObj: TJSONObject;
  LType: string;
begin
  // CRITICAL: do NOT destroy and recreate the param objects. Property links
  // (TLinkPropertyToField, designer bindings) resolve the adapter's FIELD
  // objects once, and each field's getter captures a specific param object.
  // Freeing the params (or clearing the fields) leaves bound links pointing at
  // dead objects that read empty forever - the exact cause of the bound image
  // and status label never updating despite the data being present. Instead we
  // REUSE every param by name (EnsureParam) and only add missing ones, so all
  // params - and the fields/links bound to them - live for the whole component
  // lifetime and keep delivering live values. Params from a previous model
  // simply linger; harmless for the single-model case.

  // State params (reused if already present)
  EnsureParam('Status', 'string', True);
  EnsureParam('IsRunning', 'boolean', True);
  EnsureParam('ErrorMessage', 'string', True);
  EnsureParam('Logs', 'string', True);

  // Default output params (always exposed for bindings designer safety)
  EnsureParam('Output', 'string', True);
  EnsureParam('Output.value', 'string', True);
  EnsureParam('Output.image', 'string', True);
  EnsureParam('Output.text', 'string', True);
  EnsureParam('Output.0', 'string', True);
  EnsureParam('Output.1', 'string', True);

  if FCachedSchema <> '' then
  begin
    try
      LJSON := TJSONObject.ParseJSONValue(FCachedSchema) as TJSONObject;
      if LJSON <> nil then
      begin
        try
          LComponents := LJSON.GetValue('components') as TJSONObject;
          LInput := nil;
          LSchemas := nil;
          if LComponents <> nil then
          begin
            LSchemas := LComponents.GetValue('schemas') as TJSONObject;
            if LSchemas <> nil then
              LInput := LSchemas.GetValue('Input') as TJSONObject;
          end
          else
          begin
            LInput := LJSON;
          end;

          if LInput <> nil then
          begin
            LProperties := LInput.GetValue('properties') as TJSONObject;
            if LProperties <> nil then
            begin
              for LPair in LProperties do
              begin
                LPropObj := LPair.JsonValue as TJSONObject;
                if LPropObj <> nil then
                begin
                  LType := LPropObj.GetValue<string>('type', 'string');
                  if LType = 'number' then LType := 'number'
                  else if LType = 'integer' then LType := 'integer'
                  else if LType = 'boolean' then LType := 'boolean'
                  else LType := 'string';

                  LParam := EnsureParam('Input.' + LPair.JsonString.Value, LType, False);

                  var LDefaultVal := LPropObj.GetValue('default');
                  if LDefaultVal <> nil then
                  begin
                    if LType = 'integer' then
                      LParam.DefaultValue := TValue.From<Integer>(StrToIntDef(LDefaultVal.Value, 0))
                    else if LType = 'number' then
                      LParam.DefaultValue := TValue.From<Double>(StrToFloatDef(LDefaultVal.Value, 0.0))
                    else if LType = 'boolean' then
                      LParam.DefaultValue := TValue.From<Boolean>(LDefaultVal.Value.ToBoolean)
                    else
                      LParam.DefaultValue := TValue.From<string>(LDefaultVal.Value);
                      
                    LParam.Value := LParam.DefaultValue;
                  end;
                  // Note: EnsureParam already added LParam to FParams.
                end;
              end;
            end;
          end;

          if LSchemas <> nil then
          begin
            LOutput := LSchemas.GetValue('Output') as TJSONObject;
            if LOutput <> nil then
            begin
              LProperties := LOutput.GetValue('properties') as TJSONObject;
              if LProperties <> nil then
              begin
                for LPair in LProperties do
                begin
                  LPropObj := LPair.JsonValue as TJSONObject;
                  if LPropObj <> nil then
                  begin
                    LType := LPropObj.GetValue<string>('type', 'string');
                    if LType = 'number' then LType := 'number'
                    else if LType = 'integer' then LType := 'integer'
                    else if LType = 'boolean' then LType := 'boolean'
                    else LType := 'string';

                    EnsureParam('Output.' + LPair.JsonString.Value, LType, True);
                  end;
                end;
              end;
            end;
          end;

        finally
          LJSON.Free;
        end;
      end;
    except
      on E: Exception do
        DebugLog('RebuildFromSchema: schema parse failed - ' + E.Message);
    end;
  end;

  if FAdapter <> nil then
  begin
    FAdapter.Active := False;
    FAdapter.AddFields;   // additive: existing (bound) fields are preserved
    FAdapter.Active := True;
  end;

  DebugLog(Format('RebuildFromSchema: %d params defined', [FParams.Count]));
end;
procedure TReplicateBindSource.SetModel(const AValue: string);
begin
  if FModel <> AValue then
  begin
    FModel := AValue;
    if (csDesigning in ComponentState) and not (csLoading in ComponentState) then
    begin
      if FApiToken = '' then
        FApiToken := GetEnvironmentVariable('REPLICATE_API_TOKEN');

      if FApiToken <> '' then
      begin
        try
          FetchSchema;
          RebuildFromSchema;
        except
          on E: Exception do
            raise Exception.Create('Error fetching Replicate schema: ' + E.Message);
        end;
      end
      else
      begin
        if FCachedSchema <> '' then
          RebuildFromSchema;
      end;
    end;
  end;
end;

procedure TReplicateBindSource.SetVersion(const AValue: string);
begin
  if FVersion <> AValue then
  begin
    FVersion := AValue;
    if (csDesigning in ComponentState) and not (csLoading in ComponentState) and (FModel <> '') and (FApiToken <> '') then
    begin
      try
        FetchSchema;
        RebuildFromSchema;
      except
        on E: Exception do
          raise Exception.Create('Error fetching Replicate schema for version: ' + E.Message);
      end;
    end;
  end;
end;

procedure TReplicateBindSource.SetCachedSchema(const AValue: string);
begin
  if FCachedSchema <> AValue then
  begin
    FCachedSchema := AValue;
    RebuildFromSchema;
  end;
end;

function FileToBase64URI(const AFilePath: string): string;
var
  LFileStream: TFileStream;
  LBytes: TBytes;
  LBase64: string;
  LMimeType: string;
  LExt: string;
begin
  Result := AFilePath;
  if not TFile.Exists(AFilePath) then
    Exit;

  LExt := TPath.GetExtension(AFilePath).ToLower;
  if (LExt = '.png') then LMimeType := 'image/png'
  else if (LExt = '.jpg') or (LExt = '.jpeg') then LMimeType := 'image/jpeg'
  else if (LExt = '.webp') then LMimeType := 'image/webp'
  else if (LExt = '.gif') then LMimeType := 'image/gif'
  else if (LExt = '.txt') then LMimeType := 'text/plain'
  else LMimeType := 'application/octet-stream';

  LFileStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(LBytes, LFileStream.Size);
    if LFileStream.Size > 0 then
      LFileStream.ReadBuffer(LBytes[0], LFileStream.Size);
  finally
    LFileStream.Free;
  end;

  LBase64 := TNetEncoding.Base64.EncodeBytesToString(LBytes).Replace(#13, '').Replace(#10, '');
  Result := Format('data:%s;base64,%s', [LMimeType, LBase64]);
end;

function TReplicateBindSource.SerializeInputs: TJSONObject;
var
  P: TReplicateParam;
  LInputJSON: TJSONObject;
  LName: string;
  LStrVal: string;
begin
  LInputJSON := TJSONObject.Create;
  try
    for P in FParams do
    begin
      if (not P.IsReadOnly) and P.Name.StartsWith('Input.') then
      begin
        LName := P.Name.Substring(6); // Remove 'Input.'
        if P.IsAssigned and not P.Value.IsEmpty then
        begin
          case P.Value.Kind of
            tkInteger: LInputJSON.AddPair(LName, TJSONNumber.Create(P.Value.AsInteger));
            tkFloat: LInputJSON.AddPair(LName, TJSONNumber.Create(P.Value.AsType<Double>));
            tkInt64: LInputJSON.AddPair(LName, TJSONNumber.Create(P.Value.AsInt64));
            tkEnumeration:
              begin
                if P.Value.IsType<Boolean> then
                begin
                  if P.Value.AsBoolean then
                    LInputJSON.AddPair(LName, TJSONTrue.Create)
                  else
                    LInputJSON.AddPair(LName, TJSONFalse.Create);
                end
                else
                  LInputJSON.AddPair(LName, P.Value.ToString);
              end;
            else
              begin
                LStrVal := P.Value.ToString;
                if TFile.Exists(LStrVal) then
                  LStrVal := FileToBase64URI(LStrVal);
                LInputJSON.AddPair(LName, LStrVal);
              end;
          end;
        end;
      end;
    end;
    Result := LInputJSON;
  except
    LInputJSON.Free;
    raise;
  end;
end;

procedure TReplicateBindSource.Run;
var
  LQueueProc: TThreadProcedure;
begin
  if FIsRunning then
    raise Exception.Create('Prediction is already running.');

  if FApiToken = '' then
    FApiToken := GetEnvironmentVariable('REPLICATE_API_TOKEN');

  if FApiToken = '' then
    raise Exception.Create('Replicate API Token is not configured.');

  FIsRunning := True;
  FStatus := 'starting';
  FErrorMessage := '';
  FLogs := '';

  SetOutputParamValue('Status', FStatus);
  SetOutputParamValue('IsRunning', FIsRunning);
  SetOutputParamValue('ErrorMessage', FErrorMessage);
  SetOutputParamValue('Logs', FLogs);
  NotifyChanged;
  if Assigned(FOnStatusChanged) then
    FOnStatusChanged(Self);

  DebugLog(Format('Run: model="%s" actualVersion="%s" versionProp="%s"', [FModel, FActualVersion, FVersion]));

  System.Threading.TTask.Run(
    procedure
    begin
      try
        ExecutePrediction;
      except
        on E: Exception do
        begin
          // Copy the message NOW: TThread.Queue runs after this except block
          // exits and the exception object is destroyed, so capturing E itself
          // would dereference a freed object and kill the update silently.
          var LErrMsg := E.Message;
          DebugLog('Run: FAILED - ' + LErrMsg);
          LQueueProc := procedure
            begin
              FIsRunning := False;
              FStatus := 'failed';
              FErrorMessage := LErrMsg;
              // Surface the error in Logs too, so UIs that only bind the
              // Logs field (like the sample's memo) show what went wrong.
              if FLogs <> '' then
                FLogs := FLogs + sLineBreak;
              FLogs := FLogs + 'ERROR: ' + LErrMsg;
              SetOutputParamValue('Status', FStatus);
              SetOutputParamValue('IsRunning', FIsRunning);
              SetOutputParamValue('ErrorMessage', FErrorMessage);
              SetOutputParamValue('Logs', FLogs);
              NotifyChanged;
              if Assigned(FOnStatusChanged) then
                FOnStatusChanged(Self);
            end;
          TThread.Queue(nil, LQueueProc);
        end;
      end;
    end);
end;

procedure TReplicateBindSource.ExecutePrediction;
var
  LHTTP: THTTPClient;
  LPostData: TJSONObject;
  LInputJSON: TJSONObject;
  LResponse: IHTTPResponse;
  LRespJSON: TJSONObject;
  LStatus: string;
  LId: string;
  LPollURL: string;
  LUrls: TJSONObject;
  LOutputVal: TJSONValue;
  LErrVal: TJSONValue;
  LLogsVal: TJSONValue;
  LPostVersion: string;
  LPostURL: string;
  LOwner, LName, LVerId: string;
  LStream: TStringStream;
begin
  LHTTP := THTTPClient.Create;
  LPostData := TJSONObject.Create;
  try
    LHTTP.CustomHeaders['Authorization'] := 'Bearer ' + FApiToken;
    LHTTP.CustomHeaders['Content-Type'] := 'application/json';
    LHTTP.ContentType := 'application/json';

    ParseModelString(FModel, LOwner, LName, LVerId);

    // Version precedence: fetched at runtime > pinned in the Model string
    // ('owner/name:version') > the Version property.
    LPostVersion := FActualVersion;
    if LPostVersion = '' then
      LPostVersion := LVerId;
    if LPostVersion = '' then
      LPostVersion := FVersion;

    if LPostVersion <> '' then
    begin
      LPostData.AddPair('version', LPostVersion);
      LPostURL := 'https://api.replicate.com/v1/predictions';
    end
    else
    begin
      // No version known (e.g. only a design-time CachedSchema is present,
      // since ActualVersion is not persisted). Fall back to the model-scoped
      // endpoint, which runs the latest version without needing a schema
      // fetch first and is the recommended route for official models.
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

    DebugLog(Format('ExecutePrediction: HTTP %d %s', [LResponse.StatusCode, TruncS(LResponse.ContentAsString, 400)]));

    if LResponse.StatusCode <> 201 then
    begin
      raise Exception.CreateFmt('Failed to start Replicate prediction: %d %s', [LResponse.StatusCode, LResponse.ContentAsString]);
    end;

    LRespJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
    try
      LId := LRespJSON.GetValue<string>('id', '');
      LStatus := LRespJSON.GetValue<string>('status', 'starting');
      
      LPollURL := 'https://api.replicate.com/v1/predictions/' + LId;
      if LRespJSON.TryGetValue<TJSONObject>('urls', LUrls) then
      begin
        LPollURL := LUrls.GetValue<string>('get', LPollURL);
      end;

      UpdatePredictionState(LStatus, '', '', nil);

      while (LStatus = 'starting') or (LStatus = 'processing') do
      begin
        TThread.Sleep(1500);

        LResponse := LHTTP.Get(LPollURL);
        if LResponse.StatusCode = 200 then
        begin
          var LPollJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
          if LPollJSON <> nil then
          begin
            try
              LStatus := LPollJSON.GetValue<string>('status', 'starting');
              
              // JSON null must be treated as absent: TJSONNull.Value returns
              // the string 'null', which would otherwise flow into Logs and
              // ErrorMessage ("ERROR: null" on every poll tick).
              var LLogs := '';
              LLogsVal := LPollJSON.GetValue('logs');
              if (LLogsVal <> nil) and not (LLogsVal is TJSONNull) then
                LLogs := LLogsVal.Value;

              var LErr := '';
              LErrVal := LPollJSON.GetValue('error');
              if (LErrVal <> nil) and not (LErrVal is TJSONNull) then
                LErr := LErrVal.Value;

              LOutputVal := LPollJSON.GetValue('output');
              if LOutputVal is TJSONNull then
                LOutputVal := nil;

              DebugLog(Format('Poll: status="%s" logs=%d chars error="%s" hasOutput=%s',
                [LStatus, Length(LLogs), TruncS(LErr, 200), BoolToStr(LOutputVal <> nil, True)]));

              UpdatePredictionState(LStatus, LLogs, LErr, LOutputVal);
            finally
              LPollJSON.Free;
            end;
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

procedure TReplicateBindSource.UpdatePredictionState(const AStatus, ALogs, AError: string; AOutputVal: TJSONValue);
var
  LOutputCopy: TJSONValue;
  LQueueProc: TThreadProcedure;
begin
  LOutputCopy := nil;
  if AOutputVal <> nil then
    LOutputCopy := AOutputVal.Clone as TJSONValue;

  LQueueProc := procedure
    begin
      try
        FStatus := AStatus;
        FLogs := ALogs;

        if AError <> '' then
        begin
          FErrorMessage := AError;
          // Mirror the error into Logs so a UI that only binds Logs
          // (like the sample's memo) still shows the failure reason.
          if FLogs <> '' then
            FLogs := FLogs + sLineBreak;
          FLogs := FLogs + 'ERROR: ' + AError;
        end;

        if AStatus = 'succeeded' then
        begin
          FIsRunning := False;
          FErrorMessage := '';
        end
        else if (AStatus = 'failed') or (AStatus = 'canceled') then
        begin
          FIsRunning := False;
        end;

        SetOutputParamValue('Status', FStatus);
        SetOutputParamValue('IsRunning', FIsRunning);
        SetOutputParamValue('ErrorMessage', FErrorMessage);
        SetOutputParamValue('Logs', FLogs);

        if LOutputCopy <> nil then
        begin
          ParseOutputValue(LOutputCopy);
        end;

        NotifyChanged;

        // Event-driven UI update (main thread): reliable regardless of whether
        // LiveBindings links refresh. Handlers read Status/Logs/GetOutputValue.
        if Assigned(FOnStatusChanged) then
          FOnStatusChanged(Self);

        if (AStatus = 'succeeded') and Assigned(FOnCompleted) then
          FOnCompleted(Self);

      finally
        LOutputCopy.Free;
      end;
    end;

  TThread.Queue(nil, LQueueProc);
end;

procedure TReplicateBindSource.ParseOutputValue(AOutputVal: TJSONValue);
var
  LStr: string;
  LArr: TJSONArray;
  LPair: TJSONPair;
  LObj: TJSONObject;
  P: TReplicateParam;
begin
  if AOutputVal = nil then Exit;

  for P in FParams do
  begin
    if P.IsReadOnly and P.Name.StartsWith('Output.') then
      P.ResetToDefault;
  end;

  if AOutputVal is TJSONArray then
  begin
    LArr := AOutputVal as TJSONArray;
    DebugLog(Format('ParseOutput: array with %d item(s)', [LArr.Count]));
    if LArr.Count > 0 then
    begin
      SetOutputParamValue('Output', LArr.Items[0].Value);
      SetOutputParamValue('Output.value', LArr.Items[0].Value);
      SetOutputParamValue('Output.image', LArr.Items[0].Value);
      SetOutputParamValue('Output.0', LArr.Items[0].Value);
      
      LStr := '';
      for var i := 0 to LArr.Count - 1 do
      begin
        if i > 0 then LStr := LStr + ' ';
        LStr := LStr + LArr.Items[i].Value;
        SetOutputParamValue('Output.' + i.ToString, LArr.Items[i].Value);
      end;
      SetOutputParamValue('Output.text', LStr);
    end;
  end
  else if AOutputVal is TJSONObject then
  begin
    LObj := AOutputVal as TJSONObject;
    DebugLog('ParseOutput: object ' + TruncS(LObj.ToJSON, 300));
    for LPair in LObj do
    begin
      SetOutputParamValue('Output.' + LPair.JsonString.Value, LPair.JsonValue.Value);
    end;
    SetOutputParamValue('Output', LObj.ToJSON);
  end
  else
  begin
    LStr := AOutputVal.Value;
    DebugLog('ParseOutput: value ' + TruncS(LStr, 300));
    SetOutputParamValue('Output', LStr);
    SetOutputParamValue('Output.value', LStr);
    SetOutputParamValue('Output.image', LStr);
    SetOutputParamValue('Output.text', LStr);
  end;
end;
procedure TReplicateBindSource.SetOutputParamValue(const AName: string; const AValue: TValue);
var
  P: TReplicateParam;
begin
  for P in FParams do
  begin
    if P.Name = AName then
    begin
      P.Value := AValue;
      Exit;
    end;
  end;
  DebugLog(Format('SetOutputParamValue: no param named "%s"', [AName]));
end;

procedure TReplicateBindSource.SetInputValue(const AName: string; const AValue: TValue);
var
  P: TReplicateParam;
  LFullName: string;
begin
  if AName.StartsWith('Input.') then
    LFullName := AName
  else
    LFullName := 'Input.' + AName;

  for P in FParams do
  begin
    if (not P.IsReadOnly) and (P.Name = LFullName) then
    begin
      P.Value := AValue;
      DebugLog(Format('SetInputValue: %s := %s', [LFullName, TruncS(AValue.ToString, 200)]));
      NotifyChanged;
      Exit;
    end;
  end;
  DebugLog(Format('SetInputValue: input "%s" not found', [AName]));
  raise Exception.CreateFmt('Input property "%s" not found.', [AName]);
end;

function TReplicateBindSource.GetOutputValue(const AName: string): TValue;
var
  P: TReplicateParam;
  LFullName: string;
begin
  if (AName = 'Output') or AName.StartsWith('Output.') then
    LFullName := AName
  else
    LFullName := 'Output.' + AName;

  for P in FParams do
  begin
    if P.Name = LFullName then
    begin
      Result := P.Value;
      Exit;
    end;
  end;
  Result := TValue.Empty;
end;

procedure TReplicateBindSource.NotifyChanged;
var
  LField: TBindSourceAdapterField;
begin
  if FAdapter = nil then Exit;

  // Params and their fields are now persistent (see RebuildFromSchema), so a
  // plain adapter change notification reaches the still-bound links. Notify
  // the expression engine per field as well so each property link re-reads
  // its live value and runs any registered converter (e.g. URL -> bitmap).
  FAdapter.DataSetChanged;
  for LField in FAdapter.Fields do
    TBindings.Notify(LField, '');
end;

// Small bounded URL->bytes cache so repeated converter invocations for the same
// URL (a single dataset Post triggers several) do not re-download the image.
var
  GUrlCache: TDictionary<string, TBytes>;
  GUrlCacheOrder: TList<string>;
  GUrlCacheLock: TCriticalSection;
  // Last URL loaded into each target bitmap, so the redundant second (and
  // later) converter invocations per dataset Post skip download AND decode.
  GTargetUrl: TDictionary<Pointer, string>;

const
  CUrlCacheMax = 4;    // keep only a few recent images (they can be several MB)
  CTargetUrlMax = 64;  // small map of target-bitmap -> last url

function TargetAlreadyHas(ATarget: TObject; const AUrl: string): Boolean;
var
  LLast: string;
begin
  Result := False;
  if GUrlCacheLock = nil then Exit;
  GUrlCacheLock.Enter;
  try
    Result := (GTargetUrl <> nil) and GTargetUrl.TryGetValue(Pointer(ATarget), LLast) and (LLast = AUrl);
  finally
    GUrlCacheLock.Leave;
  end;
end;

procedure MarkTarget(ATarget: TObject; const AUrl: string);
begin
  if GUrlCacheLock = nil then Exit;
  GUrlCacheLock.Enter;
  try
    if GTargetUrl = nil then Exit;
    if GTargetUrl.Count >= CTargetUrlMax then
      GTargetUrl.Clear; // bounded; simplest eviction
    GTargetUrl.AddOrSetValue(Pointer(ATarget), AUrl);
  finally
    GUrlCacheLock.Leave;
  end;
end;

function TryGetCachedUrl(const AUrl: string; out ABytes: TBytes): Boolean;
begin
  Result := False;
  if GUrlCacheLock = nil then Exit;
  GUrlCacheLock.Enter;
  try
    Result := (GUrlCache <> nil) and GUrlCache.TryGetValue(AUrl, ABytes);
  finally
    GUrlCacheLock.Leave;
  end;
end;

procedure PutCachedUrl(const AUrl: string; const ABytes: TBytes);
begin
  if GUrlCacheLock = nil then Exit;
  GUrlCacheLock.Enter;
  try
    if (GUrlCache = nil) or GUrlCache.ContainsKey(AUrl) then Exit;
    while GUrlCacheOrder.Count >= CUrlCacheMax do
    begin
      GUrlCache.Remove(GUrlCacheOrder[0]);
      GUrlCacheOrder.Delete(0);
    end;
    GUrlCache.Add(AUrl, ABytes);
    GUrlCacheOrder.Add(AUrl);
  finally
    GUrlCacheLock.Leave;
  end;
end;

procedure LoadUrlOrFileToBitmap(const AUrlOrFile: string; ABitmap: TObject);
var
  LHTTP: THTTPClient;
  LStream: TMemoryStream;
  LResponse: IHTTPResponse;
  LContext: TRttiContext;
  LType: TRttiType;
  LMethod: TRttiMethod;
  LBytes: TBytes;
begin
  if AUrlOrFile = '' then
  begin
    // Links evaluate with the typed empty default before a prediction has
    // produced output; log it so converter invocations are always visible.
    ReplicateDebugLog('Converter: called with empty path, skipped');
    Exit;
  end;

  // A single dataset Post fires more than one LiveBindings notification, so the
  // converter is invoked repeatedly with the same URL for the same target. If
  // this bitmap already holds this URL, skip download AND decode entirely.
  if TargetAlreadyHas(ABitmap, AUrlOrFile) then
  begin
    ReplicateDebugLog('Converter: already current, skipped ' + TruncS(AUrlOrFile, 200));
    Exit;
  end;

  LStream := TMemoryStream.Create;
  try
    if AUrlOrFile.StartsWith('http://', True) or AUrlOrFile.StartsWith('https://', True) then
    begin
      // A single dataset Post fires more than one LiveBindings notification, so
      // the converter is invoked repeatedly with the same URL. Cache the bytes
      // so those repeats do not re-download the (multi-MB) image.
      if TryGetCachedUrl(AUrlOrFile, LBytes) then
      begin
        ReplicateDebugLog('Converter: cache hit ' + TruncS(AUrlOrFile, 200));
        if Length(LBytes) > 0 then
        begin
          LStream.WriteBuffer(LBytes[0], Length(LBytes));
          LStream.Position := 0;
        end;
      end
      else
      begin
        ReplicateDebugLog('Converter: loading ' + TruncS(AUrlOrFile, 200));
        LHTTP := THTTPClient.Create;
        try
          LResponse := LHTTP.Get(AUrlOrFile);
          if LResponse.StatusCode = 200 then
          begin
            LStream.CopyFrom(LResponse.ContentStream, 0);
            LStream.Position := 0;
            SetLength(LBytes, LStream.Size);
            if LStream.Size > 0 then
              Move(LStream.Memory^, LBytes[0], LStream.Size);
            PutCachedUrl(AUrlOrFile, LBytes);
          end;
        finally
          LHTTP.Free;
        end;
      end;
    end
    else if TFile.Exists(AUrlOrFile) then
    begin
      ReplicateDebugLog('Converter: loading ' + TruncS(AUrlOrFile, 200));
      LStream.LoadFromFile(AUrlOrFile);
      LStream.Position := 0;
    end;

    ReplicateDebugLog(Format('Converter: %d bytes ready for %s', [LStream.Size, ABitmap.ClassName]));

    if LStream.Size > 0 then
    begin
      LContext := TRttiContext.Create;
      LType := LContext.GetType(ABitmap.ClassType);
      if LType <> nil then
      begin
        LMethod := LType.GetMethod('LoadFromStream');
        if LMethod <> nil then
        begin
          LMethod.Invoke(ABitmap, [LStream]);
          MarkTarget(ABitmap, AUrlOrFile); // remember what this bitmap now holds
        end
        else
          ReplicateDebugLog('Converter: ' + ABitmap.ClassName + ' has no LoadFromStream method');
      end;
    end;
  finally
    LStream.Free;
  end;
end;

procedure RegisterUrlConverters;
var
  LContext: TRttiContext;
  LFmxBitmapType, LVclBitmapType, LVclPictureType: TRttiType;
  LInfo: string;
begin
  LInfo := '';
  LContext := TRttiContext.Create;
  LFmxBitmapType := LContext.FindType('FMX.Graphics.TBitmap');
  LVclBitmapType := LContext.FindType('Vcl.Graphics.TBitmap');
  LVclPictureType := LContext.FindType('Vcl.Graphics.TPicture');
  
  if LFmxBitmapType <> nil then
  begin
    TValueRefConverterFactory.RegisterConversion(
      TypeInfo(string),
      LFmxBitmapType.Handle,
      TConverterDescription.Create(
        procedure(const InValue: TValue; var OutValue: TValue)
        begin
          if not InValue.IsEmpty then
          begin
            var LUrl := InValue.AsString;
            var LBitmapObj := OutValue.AsObject;
            if LBitmapObj <> nil then
              LoadUrlOrFileToBitmap(LUrl, LBitmapObj)
            else
              ReplicateDebugLog('UrlToFmxBitmap: target object is nil');
          end
          else
            ReplicateDebugLog('UrlToFmxBitmap: input value is empty');
        end,
        'UrlToFmxBitmap',
        'URL/File to FMX Bitmap',
        'Replicate.BindSource',
        True,
        'Downloads a URL or loads a file into an FMX TBitmap',
        TPersistentClass(nil)
      )
    );
    LInfo := LInfo + ' UrlToFmxBitmap';
  end;

  if LVclBitmapType <> nil then
  begin
    TValueRefConverterFactory.RegisterConversion(
      TypeInfo(string),
      LVclBitmapType.Handle,
      TConverterDescription.Create(
        procedure(const InValue: TValue; var OutValue: TValue)
        begin
          if not InValue.IsEmpty then
          begin
            var LUrl := InValue.AsString;
            var LBitmapObj := OutValue.AsObject;
            if LBitmapObj <> nil then
              LoadUrlOrFileToBitmap(LUrl, LBitmapObj)
            else
              ReplicateDebugLog('UrlToVclBitmap: target object is nil');
          end
          else
            ReplicateDebugLog('UrlToVclBitmap: input value is empty');
        end,
        'UrlToVclBitmap',
        'URL/File to VCL TBitmap',
        'Replicate.BindSource',
        True,
        'Downloads a URL or loads a file into a VCL TBitmap',
        TPersistentClass(nil)
      )
    );
    LInfo := LInfo + ' UrlToVclBitmap';
  end;

  if LVclPictureType <> nil then
  begin
    TValueRefConverterFactory.RegisterConversion(
      TypeInfo(string),
      LVclPictureType.Handle,
      TConverterDescription.Create(
        procedure(const InValue: TValue; var OutValue: TValue)
        begin
          if not InValue.IsEmpty then
          begin
            var LUrl := InValue.AsString;
            var LPictureObj := OutValue.AsObject;
            if LPictureObj <> nil then
              LoadUrlOrFileToBitmap(LUrl, LPictureObj)
            else
              ReplicateDebugLog('UrlToVclPicture: target object is nil');
          end
          else
            ReplicateDebugLog('UrlToVclPicture: input value is empty');
        end,
        'UrlToVclPicture',
        'URL/File to VCL TPicture',
        'Replicate.BindSource',
        True,
        'Downloads a URL or loads a file into a VCL TPicture',
        TPersistentClass(nil)
      )
    );
    LInfo := LInfo + ' UrlToVclPicture';
  end;

  if LInfo <> '' then
    GConverterRegInfo := 'URL converters registered:' + LInfo
  else
    GConverterRegInfo := 'URL converters: no bitmap types found, nothing registered';
end;

procedure UnregisterUrlConverters;
begin
  TValueRefConverterFactory.UnRegisterConversion('UrlToFmxBitmap');
  TValueRefConverterFactory.UnRegisterConversion('UrlToVclBitmap');
  TValueRefConverterFactory.UnRegisterConversion('UrlToVclPicture');
end;

procedure Register;
begin
  RegisterComponents('Replicate', [TReplicateBindSource]);
end;

initialization
  GUrlCacheLock := TCriticalSection.Create;
  GUrlCache := TDictionary<string, TBytes>.Create;
  GUrlCacheOrder := TList<string>.Create;
  GTargetUrl := TDictionary<Pointer, string>.Create;
  RegisterUrlConverters;

finalization
  UnregisterUrlConverters;
  GTargetUrl.Free;
  GUrlCacheOrder.Free;
  GUrlCache.Free;
  GUrlCacheLock.Free;

end.
