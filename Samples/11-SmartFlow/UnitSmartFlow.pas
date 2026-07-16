unit UnitSmartFlow;

// MIXED-PROVIDER workflow: SmartCore (Claude) writes the image prompt,
// Replicate generates and upscales - three designer-drawn stages:
//
//   [NodeChat: TAIEngineNode over TSmartCoreChatEngine]
//        | LinkChatToGen: OutputText -> InputPrompt
//   [NodeGen: TReplicateNode, flux-schnell, AutoRun]
//        | LinkGenToUp: OutputImage -> InputImage
//   [NodeUpscale: TReplicateNode, crisp-upscale, AutoRun]
//
// The chat stage runs on Embarcadero's SmartCore AI pack (RAD Studio 13+,
// GetIt) through TSmartCoreChatEngine; the image stages run on the Replicate
// engine. Because both implement TAICustomEngine, the SAME node faces, chain
// bindings and AutoRun cascade drive all three - the workflow layer neither
// knows nor cares which provider a stage runs on.
//
// NodeChat also streams: LinkStream binds its Logs member to a memo, so you
// watch Claude's tokens arrive live while the workflow runs.
//
// REQUIREMENTS: RAD Studio 13+, SmartCore AI pack installed from GetIt,
// ANTHROPIC_API_KEY and REPLICATE_API_TOKEN (or paste into the edits).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.Graphics,
  FMX.Dialogs,
  FMX.StdCtrls,
  FMX.Controls.Presentation,
  FMX.Edit,
  FMX.ComboEdit,
  FMX.ScrollBox,
  FMX.Memo,
  FMX.Memo.Types,
  FMX.Objects,
  Data.Bind.Components,
  SmartCoreAI.Comp.Connection,
  SmartCoreAI.Driver.Claude,
  AI.SmartCore.ClaudeEx,
  AI.Engine,
  AI.Node,
  AI.SmartCore.Engine,
  Replicate.Model,
  Replicate.Node,
  Replicate.BindSource;   // debug hook + LoadUrlOrFileToBitmap

type
  TFormSmartFlow = class(TForm)
    lblClaudeKey: TLabel;
    edtClaudeKey: TEdit;
    lblReplicateToken: TLabel;
    edtReplicateToken: TEdit;
    lblChatModel: TLabel;
    cmbChatModel: TComboEdit;
    btnLoadModels: TButton;
    lblBrief: TLabel;
    edtBrief: TEdit;
    btnRun: TButton;
    ClaudeDriver1: TAIClaudeDriverEx;
    AIConnection1: TAIConnection;
    ChatEngine: TSmartCoreChatEngine;
    NodeChat: TAIEngineNode;
    NodeGen: TReplicateNode;
    NodeUpscale: TReplicateNode;
    lblChatOut: TLabel;
    edtChatOut: TEdit;
    lblStream: TLabel;
    memStream: TMemo;
    lblLogs: TLabel;
    memLogs: TMemo;
    lblGen: TLabel;
    imgGen: TImage;
    lblFinal: TLabel;
    imgFinal: TImage;
    BindingsList1: TBindingsList;
    LinkChatOut: TBindExpression;
    LinkStream: TBindExpression;
    LinkChatToGen: TBindExpression;
    LinkGenToUp: TBindExpression;
    procedure FormCreate(Sender: TObject);
    procedure btnLoadModelsClick(Sender: TObject);
    procedure ModelsLoaded(Sender: TObject; const AvailableModels: TArray<string>);
    procedure btnRunClick(Sender: TObject);
    procedure GenCompleted(Sender: TObject);
    procedure UpscaleCompleted(Sender: TObject);
  private
    procedure ConfigureDriver;
    procedure Log(const S: string);
  public
  end;

var
  FormSmartFlow: TFormSmartFlow;

implementation

{$R *.fmx}

procedure TFormSmartFlow.FormCreate(Sender: TObject);
begin
  ReplicateDebugHook :=
    procedure(ALine: string)
    begin
      memLogs.Lines.Add(ALine);
    end;

  edtClaudeKey.Text := GetEnvironmentVariable('ANTHROPIC_API_KEY');
  edtReplicateToken.Text := GetEnvironmentVariable('REPLICATE_API_TOKEN');

  // TBindExpression.Active is public (not published): activate at runtime.
  LinkChatOut.Active := True;
  LinkStream.Active := True;
  LinkChatToGen.Active := True;
  LinkGenToUp.Active := True;
end;

procedure TFormSmartFlow.ConfigureDriver;
var
  LParams: TAIClaudeParams;
begin
  // SmartCore driver settings live on the driver's Params object (typed per
  // driver) and are runtime-only (stored False) - configure them here.
  LParams := ClaudeDriver1.Params as TAIClaudeParams;
  LParams.APIKey := edtClaudeKey.Text;
  LParams.Model := Trim(cmbChatModel.Text);
  LParams.MaxToken := 1024;
  // SmartCore's Claude driver sends the anthropic-version header verbatim
  // from this param and defaults it to EMPTY - the API then rejects the
  // request ("anthropic-version: header is required"). Set it explicitly.
  LParams.AnthropicVersion := '2023-06-01';
end;

procedure TFormSmartFlow.btnLoadModelsClick(Sender: TObject);
begin
  // Model ids drift; ask the provider instead of guessing. The driver's
  // models endpoint fires OnLoadModels with the current list.
  ConfigureDriver;
  ClaudeDriver1.OnLoadModels := ModelsLoaded;
  ClaudeDriver1.ListModelsAsync;
  Log('Loading Claude model list...');
end;

procedure TFormSmartFlow.ModelsLoaded(Sender: TObject;
  const AvailableModels: TArray<string>);
var
  LModel: string;
begin
  cmbChatModel.Items.Clear;
  for LModel in AvailableModels do
    cmbChatModel.Items.Add(LModel);
  // Keep the current pick if the provider still offers it; otherwise prefer
  // an Opus model, then fall back to the first entry.
  if cmbChatModel.Items.IndexOf(cmbChatModel.Text) < 0 then
  begin
    cmbChatModel.Text := '';
    for LModel in AvailableModels do
      if LModel.Contains('opus') then
      begin
        cmbChatModel.Text := LModel;
        Break;
      end;
    if (cmbChatModel.Text = '') and (Length(AvailableModels) > 0) then
      cmbChatModel.Text := AvailableModels[0];
  end;
  Log(Format('%d Claude models loaded; using "%s".',
    [Length(AvailableModels), cmbChatModel.Text]));
end;

procedure TFormSmartFlow.btnRunClick(Sender: TObject);
begin
  if Trim(cmbChatModel.Text) = '' then
  begin
    Log('Pick a chat model first (Load Models).');
    Exit;
  end;
  ConfigureDriver;

  NodeGen.ApiToken := edtReplicateToken.Text;
  NodeUpscale.ApiToken := edtReplicateToken.Text;

  memStream.Lines.Clear;
  Log('=== Stage 1 (SmartCore/Claude): writing the image prompt ===');
  NodeChat.SetInputValue('prompt', edtBrief.Text);
  NodeChat.Run;
  // From here the graph runs itself: Claude's OutputText lands in
  // NodeGen.InputPrompt (LinkChatToGen), AutoRun launches flux-schnell, its
  // OutputImage lands in NodeUpscale.InputImage (LinkGenToUp), AutoRun again.
end;

procedure TFormSmartFlow.GenCompleted(Sender: TObject);
begin
  Log('Stage 2 done: ' + NodeGen.OutputImage);
  if NodeGen.OutputImage <> '' then
    LoadUrlOrFileToBitmap(NodeGen.OutputImage, imgGen.Bitmap);
end;

procedure TFormSmartFlow.UpscaleCompleted(Sender: TObject);
begin
  Log('Stage 3 done: ' + NodeUpscale.OutputImage);
  if NodeUpscale.OutputImage <> '' then
    LoadUrlOrFileToBitmap(NodeUpscale.OutputImage, imgFinal.Bitmap);
  Log('=== Workflow complete ===');
end;

procedure TFormSmartFlow.Log(const S: string);
begin
  memLogs.Lines.Add(S);
end;

end.
