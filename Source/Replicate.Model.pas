unit Replicate.Model;

// TReplicateModel - the Replicate.com workflow ENGINE.
//
// An observable object (see the book, ch. 10): inputs and outputs are plain
// published properties refreshed via TBindings.Notify, so a property->property
// binding  ModelA.OutputImage -> ModelB.InputImage  is a normal, writable
// LiveBindings link - the workflow edge, with no virtual-member wall.
//
// Since the SmartCore mesh, the provider-agnostic half (canonical inputs,
// observer recipe, listeners, events, the published surface) lives in
// TAICustomEngine (AI.Engine.pas). This unit implements the Replicate
// specifics: REST + polling, the OpenAPI schema (input typing and canonical
// prompt/image name resolution), output parsing/flattening, and versions.
// The class name, unit name, and full published surface are unchanged -
// existing forms and samples load and behave identically.
//
// Reuses the URL->bitmap converter, LoadUrlOrFileToBitmap and the debug hook
// from Replicate.BindSource.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.Threading,
  System.Generics.Collections,
  System.NetEncoding,
  System.IOUtils,
  Data.Bind.Components,
  Data.DB,
  FireDAC.Comp.Client,      // TFDMemTable - the OutputItems dataset
  AI.Engine,
  Replicate.BindSource;     // converters, LoadUrlOrFileToBitmap, debug hook

type
  [ObservableMember('InputImage')]
  TReplicateModel = class(TAICustomEngine)
  private
    FVersion: string;
    FActualVersion: string;
    FIsRunning: Boolean;

    FInputTypes: TDictionary<string, string>;  // raw name -> json type (from schema)
    FPromptName: string;                       // schema name canonical 'prompt' maps to
    FImageName: string;                        // schema name canonical 'image' maps to

    FOutput: string;
    FOutputImage: string;
    FOutputText: string;
    FStatus: string;
    FErrorMessage: string;
    FLogs: string;
    FLastOutputJSON: string;                   // raw output value, for path mapping
    FOutputItems: TFDMemTable;                 // output array/object as rows

    procedure ParseSchemaInputs;
    procedure ResolveCanonicalNames;
    procedure DebugLog(const AMsg: string);

    procedure FetchSchema;
    function SerializeInputs: TJSONObject;
    procedure ExecutePrediction;
    procedure UpdateState(const AStatus, ALogs, AError: string; AOutputVal: TJSONValue);
    procedure ParseOutput(AOutputVal: TJSONValue);
    procedure FillOutputItems(AOutputVal: TJSONValue);
  protected
    function GetStatus: string; override;
    function GetErrorMessage: string; override;
    function GetLogs: string; override;
    function GetOutput: string; override;
    function GetOutputImage: string; override;
    function GetOutputText: string; override;
    function GetOutputJSON: string; override;
    function GetIsRunning: Boolean; override;
    function GetOutputItemsTable: TFDMemTable; override;
    function MapInputName(const AName: string): string; override;
    procedure SchemaChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure LoadSchema; override;
    procedure Run; override;

    property ActualVersion: string read FActualVersion;

    // The prediction's output value as raw JSON (array/object/string), for
    // path-based mapping ('output[0]', 'output.text').
    property LastOutputJSON: string read FLastOutputJSON;

    // Schema-resolved names the canonical InputPrompt/InputImage map to.
    property PromptInputName: string read FPromptName;
    property ImageInputName: string read FImageName;
  published
    property Version: string read FVersion write FVersion;
  end;

procedure Register;

implementation

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

{ TReplicateModel }

constructor TReplicateModel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FInputTypes := TDictionary<string, string>.Create;

  FOutputItems := TFDMemTable.Create(Self);
  FOutputItems.Name := 'OutputItems';
  FOutputItems.SetSubComponent(True);
  FOutputItems.FieldDefs.Add('ItemIndex', ftInteger);
  FOutputItems.FieldDefs.Add('Name', ftString, 100);
  FOutputItems.FieldDefs.Add('Value', ftString, 4000);
  FOutputItems.CreateDataSet;
end;

destructor TReplicateModel.Destroy;
begin
  FInputTypes.Free;
  inherited;   // FOutputItems is owned - freed by ownership
end;

function TReplicateModel.GetStatus: string;
begin
  Result := FStatus;
end;

function TReplicateModel.GetErrorMessage: string;
begin
  Result := FErrorMessage;
end;

function TReplicateModel.GetLogs: string;
begin
  Result := FLogs;
end;

function TReplicateModel.GetOutput: string;
begin
  Result := FOutput;
end;

function TReplicateModel.GetOutputImage: string;
begin
  Result := FOutputImage;
end;

function TReplicateModel.GetOutputText: string;
begin
  Result := FOutputText;
end;

function TReplicateModel.GetOutputJSON: string;
begin
  Result := FLastOutputJSON;
end;

function TReplicateModel.GetIsRunning: Boolean;
begin
  Result := FIsRunning;
end;

function TReplicateModel.GetOutputItemsTable: TFDMemTable;
begin
  Result := FOutputItems;
end;

procedure TReplicateModel.DebugLog(const AMsg: string);
begin
  if FDebug then
    ReplicateDebugLog('[Model] ' + AMsg);
end;

procedure TReplicateModel.SchemaChanged;
begin
  // CachedSchema was assigned (code or .fmx streaming): parse immediately so
  // no HTTP fetch is needed at run.
  ParseSchemaInputs;
end;

procedure TReplicateModel.LoadSchema;
begin
  DebugLog(Format('LoadSchema: model="%s"', [FModel]));
  FetchSchema;
end;

procedure TReplicateModel.FetchSchema;
var
  LHTTP: THTTPClient;
  LURL: string;
  LResponse: IHTTPResponse;
  LJSON, LLatestVer: TJSONObject;
  LVal: TJSONValue;
  LOwner, LName, LVerId: string;
begin
  if FModel = '' then Exit;
  if FApiToken = '' then
    FApiToken := GetEnvironmentVariable('REPLICATE_API_TOKEN');
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

    LResponse := LHTTP.Get(LURL);
    DebugLog(Format('FetchSchema: HTTP %d', [LResponse.StatusCode]));
    if LResponse.StatusCode <> 200 then
      raise Exception.CreateFmt('Failed to fetch schema: %d %s', [LResponse.StatusCode, LResponse.ContentAsString]);

    LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
    if LJSON = nil then Exit;
    try
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

      ParseSchemaInputs;
    finally
      LJSON.Free;
    end;
  finally
    LHTTP.Free;
  end;
end;

procedure TReplicateModel.ParseSchemaInputs;
var
  LSchemaJSON, LComponents, LSchemas, LInput, LProperties: TJSONObject;
  LPair: TJSONPair;
begin
  // Record input names + types from the cached schema: types drive correct
  // JSON typing on Run, names drive the canonical prompt/image mapping.
  FInputTypes.Clear;
  FPromptName := '';
  FImageName := '';
  if FCachedSchema = '' then Exit;

  LSchemaJSON := TJSONObject.ParseJSONValue(FCachedSchema) as TJSONObject;
  if LSchemaJSON = nil then Exit;
  try
    LComponents := LSchemaJSON.GetValue('components') as TJSONObject;
    LInput := nil;
    if LComponents <> nil then
    begin
      LSchemas := LComponents.GetValue('schemas') as TJSONObject;
      if LSchemas <> nil then LInput := LSchemas.GetValue('Input') as TJSONObject;
    end
    else
      LInput := LSchemaJSON;
    if LInput <> nil then
    begin
      LProperties := LInput.GetValue('properties') as TJSONObject;
      if LProperties <> nil then
        for LPair in LProperties do
          FInputTypes.AddOrSetValue(LPair.JsonString.Value,
            (LPair.JsonValue as TJSONObject).GetValue<string>('type', 'string'));
    end;
  finally
    LSchemaJSON.Free;
  end;

  ResolveCanonicalNames;
end;

procedure TReplicateModel.ResolveCanonicalNames;

  function PickName(const AExact: array of string;
                    const AContains: array of string): string;
  var
    LName, LKey, LFrag: string;
  begin
    for LName in AExact do
      if FInputTypes.ContainsKey(LName) then Exit(LName);
    for LKey in FInputTypes.Keys do
    begin
      // 'system_prompt' and 'negative_prompt' CONTAIN 'prompt' but are never
      // the user's text - fuzzy matching must not land on them.
      if LKey.ToLower.Contains('system') or LKey.ToLower.Contains('negative') then
        Continue;
      for LFrag in AContains do
        if LKey.ToLower.Contains(LFrag) then Exit(LKey);
    end;
    Result := '';
  end;

begin
  // Different models name the same conceptual input differently. Resolve what
  // THIS model calls its text and image inputs so the canonical bindable
  // members InputPrompt/InputImage land on the right schema field.
  FPromptName := PickName(['prompt', 'message', 'text', 'input_text', 'caption'],
                          ['prompt', 'message', 'text']);
  FImageName := PickName(['image', 'img', 'input_image', 'image_path',
                          'init_image', 'source_image', 'face_image', 'input'],
                         ['image', 'img']);
  DebugLog(Format('Input mapping: prompt->"%s" image->"%s"',
    [FPromptName, FImageName]));
end;

function TReplicateModel.MapInputName(const AName: string): string;
begin
  Result := AName;
  if SameText(AName, 'prompt') and (FPromptName <> '') then Result := FPromptName
  else if SameText(AName, 'image') and (FImageName <> '') then Result := FImageName;
end;

function TReplicateModel.SerializeInputs: TJSONObject;
var
  LInputJSON: TJSONObject;
  LAll: TDictionary<string, string>;
  LPair: TPair<string, string>;
  LType, LStrVal, LName: string;
  I: Integer;
begin
  // Merge the static design-time Inputs list with programmatic/chained values.
  // Canonical keys ('prompt'/'image') are translated to the model's real
  // schema names here, at the last moment, so mapping works no matter when
  // the schema arrived. Chained values override static ones on collision.
  LAll := TDictionary<string, string>.Create;
  LInputJSON := TJSONObject.Create;
  try
    try
      for I := 0 to FInputsList.Count - 1 do
      begin
        LName := FInputsList.Names[I];
        if LName <> '' then
          LAll.AddOrSetValue(LName, FInputsList.ValueFromIndex[I]);
      end;
      for LPair in FInputs do
        LAll.AddOrSetValue(MapInputName(LPair.Key), LPair.Value);

      for LPair in LAll do
      begin
        LStrVal := LPair.Value;
        if LStrVal = '' then Continue;
        if not FInputTypes.TryGetValue(LPair.Key, LType) then LType := 'string';
        if LType = 'integer' then
          LInputJSON.AddPair(LPair.Key, TJSONNumber.Create(StrToInt64Def(LStrVal, 0)))
        else if LType = 'number' then
          LInputJSON.AddPair(LPair.Key, TJSONNumber.Create(StrToFloatDef(LStrVal, 0.0)))
        else if LType = 'boolean' then
        begin
          if SameText(LStrVal, 'true') then LInputJSON.AddPair(LPair.Key, TJSONTrue.Create)
          else LInputJSON.AddPair(LPair.Key, TJSONFalse.Create);
        end
        else
        begin
          if TFile.Exists(LStrVal) then LStrVal := FileToBase64URI(LStrVal);
          LInputJSON.AddPair(LPair.Key, LStrVal);
        end;
      end;
      Result := LInputJSON;
    except
      LInputJSON.Free;
      raise;
    end;
  finally
    LAll.Free;
  end;
end;

procedure TReplicateModel.Run;
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
  NotifyOutputs;
  FireStateChanged;

  DebugLog(Format('Run: model="%s"', [FModel]));

  System.Threading.TTask.Run(
    procedure
    begin
      try
        // No schema yet (no design-time load, no streamed CachedSchema):
        // fetch it now so input typing and prompt/image name mapping are
        // correct. Non-fatal - on failure canonical names pass through as-is.
        if FInputTypes.Count = 0 then
          try
            FetchSchema;
          except
            on E: Exception do
              DebugLog('Pre-run schema fetch failed (continuing): ' + E.Message);
          end;
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
              FStatus := 'failed';
              FErrorMessage := LErrMsg;
              FLogs := 'ERROR: ' + LErrMsg;
              NotifyOutputs;
              FireStateChanged;
            end);
        end;
      end;
    end);
end;

procedure TReplicateModel.ExecutePrediction;
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
    DebugLog('POST ' + LPostURL + ' ' + TruncS(LPostData.ToJSON, 500));

    LStream := TStringStream.Create(LPostData.ToJSON, TEncoding.UTF8);
    try
      LResponse := LHTTP.Post(LPostURL, LStream);
    finally
      LStream.Free;
    end;

    DebugLog(Format('HTTP %d %s', [LResponse.StatusCode, TruncS(LResponse.ContentAsString, 300)]));
    if LResponse.StatusCode <> 201 then
      raise Exception.CreateFmt('Failed to start prediction: %d %s', [LResponse.StatusCode, LResponse.ContentAsString]);

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
        end;
      end;
    finally
      LRespJSON.Free;
    end;
  finally
    LPostData.Free;
    LHTTP.Free;
  end;
end;

procedure TReplicateModel.UpdateState(const AStatus, ALogs, AError: string; AOutputVal: TJSONValue);
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
        FStatus := AStatus;
        FLogs := ALogs;
        if AError <> '' then
        begin
          FErrorMessage := AError;
          if FLogs <> '' then FLogs := FLogs + sLineBreak;
          FLogs := FLogs + 'ERROR: ' + AError;
        end;
        if (AStatus = 'succeeded') or (AStatus = 'failed') or (AStatus = 'canceled') then
          FIsRunning := False;

        if LOutputCopy <> nil then
          ParseOutput(LOutputCopy);

        NotifyOutputs;
        FireStateChanged;
        if AStatus = 'succeeded' then
        begin
          NotifyOutputListeners;   // items sources, schema links - before user code
          FireCompleted;
        end;
      finally
        LOutputCopy.Free;
      end;
    end);
end;

procedure TReplicateModel.FillOutputItems(AOutputVal: TJSONValue);

  function ValStr(AVal: TJSONValue): string;
  begin
    if (AVal is TJSONObject) or (AVal is TJSONArray) then
      Result := AVal.ToJSON
    else
      Result := AVal.Value;
  end;

  procedure AddRow(AIndex: Integer; const AName, AValue: string);
  begin
    FOutputItems.Append;
    FOutputItems.FieldByName('ItemIndex').AsInteger := AIndex;
    FOutputItems.FieldByName('Name').AsString := AName;
    FOutputItems.FieldByName('Value').AsString := AValue.Substring(0, 4000);
    FOutputItems.Post;
  end;

var
  LArr: TJSONArray;
  LPair: TJSONPair;
  I: Integer;
begin
  // Flatten the output value to rows so multi-output models (image arrays,
  // token lists) are bindable to grids/lists via a bind source - the FireDAC
  // normalize-to-dataset pattern.
  if not FOutputItems.Active then Exit;
  FOutputItems.EmptyDataSet;

  if AOutputVal is TJSONArray then
  begin
    LArr := AOutputVal as TJSONArray;
    for I := 0 to LArr.Count - 1 do
      AddRow(I, '', ValStr(LArr.Items[I]));
  end
  else if AOutputVal is TJSONObject then
  begin
    I := 0;
    for LPair in (AOutputVal as TJSONObject) do
    begin
      AddRow(I, LPair.JsonString.Value, ValStr(LPair.JsonValue));
      Inc(I);
    end;
  end
  else
    AddRow(0, '', ValStr(AOutputVal));

  FOutputItems.First;
end;

procedure TReplicateModel.ParseOutput(AOutputVal: TJSONValue);
var
  LArr: TJSONArray;
  LObj: TJSONObject;
  LPair: TJSONPair;
  LStr: string;
  I: Integer;
begin
  if AOutputVal = nil then Exit;

  FLastOutputJSON := AOutputVal.ToJSON;
  FillOutputItems(AOutputVal);

  if AOutputVal is TJSONArray then
  begin
    LArr := AOutputVal as TJSONArray;
    if LArr.Count > 0 then
    begin
      FOutput := LArr.Items[0].Value;
      FOutputImage := LArr.Items[0].Value;
      // LLMs on Replicate stream their answer as an array of raw text CHUNKS
      // split mid-word ("intri","cate") - concatenate verbatim, no separator.
      LStr := '';
      for I := 0 to LArr.Count - 1 do
        LStr := LStr + LArr.Items[I].Value;
      FOutputText := LStr;
    end;
  end
  else if AOutputVal is TJSONObject then
  begin
    LObj := AOutputVal as TJSONObject;
    FOutput := LObj.ToJSON;
    for LPair in LObj do
    begin
      if SameText(LPair.JsonString.Value, 'image') then FOutputImage := LPair.JsonValue.Value;
      if SameText(LPair.JsonString.Value, 'text') then FOutputText := LPair.JsonValue.Value;
    end;
  end
  else
  begin
    LStr := AOutputVal.Value;
    FOutput := LStr;
    FOutputImage := LStr;
    FOutputText := LStr;
  end;
end;

procedure Register;
begin
  RegisterComponents('Replicate', [TReplicateModel]);
end;

initialization
  // Design-time RegisterComponents doesn't run in a built app; register the
  // class so a form streaming it from an .fmx can instantiate it at runtime.
  RegisterClass(TReplicateModel);
  RegisterAIBindableMembers(TReplicateModel);

finalization
  UnregisterAIBindableMembers(TReplicateModel);
  UnRegisterClass(TReplicateModel);

end.
