unit AI.SmartCore.Engine;

// TSmartCoreChatEngine - a workflow engine over Embarcadero's SmartCore AI
// Component Pack (RAD Studio 13+, GetIt).
//
// SmartCore supplies the provider transport: TAIConnection + a driver
// (OpenAI/Claude/Gemini/Ollama) + TAIChatRequest. What it does NOT supply is
// LiveBindings citizenship or workflow semantics - its request components are
// plain TComponents with events (invisible to the designer), and its own
// LiveBindings support (TAIChatBindSource) is a read-only
// transcript adapter. This engine wraps a chat request in the TAICustomEngine
// contract, which buys it the entire workflow layer for free:
//
//   * front it with a TAIEngineNode -> designer block, drawable lines
//   * chain it: NodeChat.OutputText -> NodeGen.InputPrompt (AutoRun cascade)
//   * relay/schema-map its raw response JSON (OutputJSON + InputPath)
//   * stream tokens into any bound control via the Logs member
//
// Wiring: drop a TAIConnection + driver (configure via the Connection
// Wizard or code - driver params are runtime-only), point this engine's
// Connection at it, set SystemPrompt/InputPrompt, Run.
//
// Threading: SmartCore drivers deliver events on the main thread when
// SynchronizeEvents is True (the default). Leave it True - this engine
// publishes bound state directly from the callbacks.
//
// This unit ships in the OPTIONAL LiveAISmartCore package so the core suite
// keeps building without SmartCore installed.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  SmartCoreAI.Comp.Connection,
  SmartCoreAI.Comp.Chat,
  AI.Engine;

type
  [ObservableMember('InputPrompt')]
  TSmartCoreChatEngine = class(TAICustomEngine)
  private
    FConnection: TAIConnection;
    FChat: TAIChatRequest;
    FSystemPrompt: string;
    FStatus: string;
    FErrorMessage: string;
    FLogs: string;
    FOutputText: string;
    FResponseJSON: string;
    FIsRunning: Boolean;
    procedure SetConnection(const AValue: TAIConnection);
    procedure HandleResponse(Sender: TObject; const Text: string);
    procedure HandleFullResponse(Sender: TObject; const FullJsonResponse: string);
    procedure HandlePartialResponse(Sender: TObject; const PartialText: string);
    procedure HandleError(Sender: TObject; const ErrorMessage: string);
  protected
    function GetStatus: string; override;
    function GetErrorMessage: string; override;
    function GetLogs: string; override;
    function GetOutput: string; override;
    function GetOutputImage: string; override;
    function GetOutputText: string; override;
    function GetOutputJSON: string; override;
    function GetIsRunning: Boolean; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;

    // Sends SystemPrompt + InputPrompt through the connection's driver.
    // Asynchronous; state publishes through the standard engine path, so
    // chaining, relays, schema links and node faces all work unmodified.
    procedure Run; override;
  published
    // The SmartCore connection (with its driver) this engine speaks through.
    property Connection: TAIConnection read FConnection write SetConnection;

    // Prepended to InputPrompt on every run - the node's standing instruction
    // ("You are a prompt engineer. Reply with the image prompt only.").
    property SystemPrompt: string read FSystemPrompt write FSystemPrompt;
  end;

procedure Register;

implementation

{ TSmartCoreChatEngine }

constructor TSmartCoreChatEngine.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChat := TAIChatRequest.Create(Self);
  FChat.SetSubComponent(True);
  FChat.OnResponse := HandleResponse;
  FChat.OnFullResponse := HandleFullResponse;
  FChat.OnPartialResponse := HandlePartialResponse;
  FChat.OnError := HandleError;
end;

procedure TSmartCoreChatEngine.SetConnection(const AValue: TAIConnection);
begin
  if FConnection = AValue then Exit;
  if FConnection <> nil then FConnection.RemoveFreeNotification(Self);
  FConnection := AValue;
  if FConnection <> nil then FConnection.FreeNotification(Self);
end;

procedure TSmartCoreChatEngine.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FConnection) then
    FConnection := nil;
end;

function TSmartCoreChatEngine.GetStatus: string;
begin
  Result := FStatus;
end;

function TSmartCoreChatEngine.GetErrorMessage: string;
begin
  Result := FErrorMessage;
end;

function TSmartCoreChatEngine.GetLogs: string;
begin
  Result := FLogs;
end;

function TSmartCoreChatEngine.GetOutput: string;
begin
  Result := FOutputText;
end;

function TSmartCoreChatEngine.GetOutputImage: string;
begin
  Result := '';   // chat engines produce text; image engines are a follow-up
end;

function TSmartCoreChatEngine.GetOutputText: string;
begin
  Result := FOutputText;
end;

function TSmartCoreChatEngine.GetOutputJSON: string;
begin
  Result := FResponseJSON;
end;

function TSmartCoreChatEngine.GetIsRunning: Boolean;
begin
  Result := FIsRunning;
end;

procedure TSmartCoreChatEngine.Run;
var
  LPrompt: string;
begin
  if FIsRunning then
    raise Exception.Create('Chat request is already running.');
  if FConnection = nil then
    raise Exception.Create('Connection is not assigned.');

  LPrompt := InputPrompt;
  if Trim(LPrompt) = '' then
    raise Exception.Create('InputPrompt is empty.');
  if FSystemPrompt <> '' then
    LPrompt := FSystemPrompt + sLineBreak + sLineBreak + LPrompt;

  FIsRunning := True;
  FStatus := 'running';
  FErrorMessage := '';
  FLogs := '';
  FOutputText := '';
  FResponseJSON := '';
  NotifyOutputs;
  FireStateChanged;

  FChat.Connection := FConnection;
  FChat.Chat(LPrompt);   // async; the driver calls back into the handlers
end;

procedure TSmartCoreChatEngine.HandlePartialResponse(Sender: TObject;
  const PartialText: string);
begin
  // Streamed tokens accumulate in Logs - bind Logs to a memo and watch the
  // response arrive live.
  FLogs := FLogs + PartialText;
  NotifyOutputs;
end;

procedure TSmartCoreChatEngine.HandleFullResponse(Sender: TObject;
  const FullJsonResponse: string);
begin
  // The provider's raw response document - relay/schema-link paths can pick
  // fields out of it (e.g. 'content[0].text' for Claude).
  FResponseJSON := FullJsonResponse;
end;

procedure TSmartCoreChatEngine.HandleResponse(Sender: TObject; const Text: string);
var
  LStr: TJSONString;
begin
  FOutputText := Text;
  if FResponseJSON = '' then
  begin
    // No full document delivered: publish the text as a JSON string value so
    // relay paths ('output') still resolve.
    LStr := TJSONString.Create(Text);
    try
      FResponseJSON := LStr.ToJSON;
    finally
      LStr.Free;
    end;
  end;
  FStatus := 'succeeded';
  FIsRunning := False;

  NotifyOutputs;
  FireStateChanged;
  NotifyOutputListeners;   // items sources, schema links - before user code
  FireCompleted;
end;

procedure TSmartCoreChatEngine.HandleError(Sender: TObject;
  const ErrorMessage: string);
begin
  FErrorMessage := ErrorMessage;
  if FLogs <> '' then FLogs := FLogs + sLineBreak;
  FLogs := FLogs + 'ERROR: ' + ErrorMessage;
  FStatus := 'failed';
  FIsRunning := False;
  NotifyOutputs;
  FireStateChanged;
end;

procedure Register;
begin
  RegisterComponents('Replicate', [TSmartCoreChatEngine]);
end;

initialization
  RegisterClass(TSmartCoreChatEngine);
  RegisterAIBindableMembers(TSmartCoreChatEngine);

finalization
  UnregisterAIBindableMembers(TSmartCoreChatEngine);
  UnRegisterClass(TSmartCoreChatEngine);

end.
