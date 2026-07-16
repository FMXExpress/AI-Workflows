unit UnitNodeFlow;

// NODE workflow demo - TReplicateNode is a visual CONTROL, so unlike the
// non-visual TReplicateModel it is a first-class citizen of the LiveBindings
// Designer: both nodes get a designer block, their registered input/output
// members are listed on it, and the chain
//
//   NodeGen.OutputImage -> NodeUpscale.InputImage      (LinkChain)
//
// is a property->property line you can see and redraw in the designer, the
// same way the designer wires NumberBox.Value -> ProgressBar.Progress.
//
// The nodes also paint themselves on the form (model name + live status), so
// the form itself reads as the workflow: [flux-schnell] -> [crisp-upscale].
//
// NodeUpscale.AutoRun = True: when stage 1's output lands in its InputImage
// via LinkChain, stage 2 launches with no code. Only URL -> TImage.Bitmap
// display code lives in the OnCompleted handlers.

interface

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.Graphics,
  FMX.Dialogs,
  FMX.StdCtrls,
  FMX.Controls.Presentation,
  FMX.Edit,
  FMX.ScrollBox,
  FMX.Memo,
  FMX.Memo.Types,
  FMX.Objects,
  Data.Bind.Components,   // TBindingsList, TBindExpression, TExpressionDirection
  Replicate.Node,
  Replicate.Model,
  Replicate.BindSource;   // debug hook + LoadUrlOrFileToBitmap

type
  TFormNodeFlow = class(TForm)
    lblToken: TLabel;
    edtToken: TEdit;
    lblPrompt: TLabel;
    edtPrompt: TEdit;
    btnRun: TButton;
    NodeGen: TReplicateNode;
    NodeUpscale: TReplicateNode;
    lblGenOut: TLabel;
    edtGenOut: TEdit;
    lblUpOut: TLabel;
    edtUpOut: TEdit;
    lblLogs: TLabel;
    memLogs: TMemo;
    lblGen: TLabel;
    imgGen: TImage;
    lblFinal: TLabel;
    imgFinal: TImage;
    BindingsList1: TBindingsList;
    LinkGenOut: TBindExpression;
    LinkUpOut: TBindExpression;
    LinkChain: TBindExpression;
    procedure FormCreate(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure GenCompleted(Sender: TObject);
    procedure UpscaleCompleted(Sender: TObject);
  private
    procedure Log(const S: string);
  public
  end;

var
  FormNodeFlow: TFormNodeFlow;

implementation

{$R *.fmx}

procedure TFormNodeFlow.FormCreate(Sender: TObject);
begin
  ReplicateDebugHook :=
    procedure(ALine: string)
    begin
      memLogs.Lines.Add(ALine);
    end;

  edtToken.Text := GetEnvironmentVariable('REPLICATE_API_TOKEN');

  // TBindExpression.Active is public (not published) so it cannot stream from
  // the .fmx; designer-made bindings are activated at runtime. Do that here.
  LinkGenOut.Active := True;
  LinkUpOut.Active := True;
  LinkChain.Active := True;
end;

procedure TFormNodeFlow.btnRunClick(Sender: TObject);
begin
  NodeGen.ApiToken := edtToken.Text;
  NodeUpscale.ApiToken := edtToken.Text;
  NodeGen.SetInputValue('prompt', edtPrompt.Text);
  Log('=== Stage 1: ' + NodeGen.Model + ' ===');
  NodeGen.Run;
end;

procedure TFormNodeFlow.GenCompleted(Sender: TObject);
begin
  Log('Stage 1 done: ' + NodeGen.OutputImage);
  if NodeGen.OutputImage <> '' then
    LoadUrlOrFileToBitmap(NodeGen.OutputImage, imgGen.Bitmap);
  // LinkChain has already pushed OutputImage into NodeUpscale.InputImage;
  // AutoRun launches stage 2 with no code here.
end;

procedure TFormNodeFlow.UpscaleCompleted(Sender: TObject);
begin
  Log('Stage 2 done: ' + NodeUpscale.OutputImage);
  if NodeUpscale.OutputImage <> '' then
    LoadUrlOrFileToBitmap(NodeUpscale.OutputImage, imgFinal.Bitmap);
  Log('=== Workflow complete ===');
end;

procedure TFormNodeFlow.Log(const S: string);
begin
  memLogs.Lines.Add(S);
end;

end.
