unit UnitWorkflow;

// DESIGNER-WIRED workflow demo for TReplicateModel.
//
// This is the payoff of the observable-object architecture: the model->model
// chain is a real LiveBindings line drawn in the LiveBindings Designer, living
// in the form's BindingsList (see UnitWorkflow.fmx), NOT created in code.
//
// The three bindings in BindingsList1 are:
//
//   LinkGenOut:  ModelGen.OutputImage     -> edtGenOut.Text        (show stage 1 URL)
//   LinkUpOut:   ModelUpscale.OutputImage -> edtUpOut.Text         (show stage 2 URL)
//   LinkChain:   ModelGen.OutputImage     -> ModelUpscale.InputImage  <-- THE edge
//
// LinkChain is the workflow edge: because a TReplicateModel's InputImage is an
// ordinary writable property (not a read-only virtual bind-source field), the
// designer can draw a property->property line straight from one model's output
// into the next model's input. ModelUpscale.AutoRun=True, so when stage 1's
// OutputImage lands in ModelUpscale.InputImage the upscale launches on its own.
//
// TBindings.Notify (inside TReplicateModel) fires each binding when an output
// changes, so no polling and no relay control. To edit the graph, open this
// form in the IDE and use the LiveBindings Designer - the lines are all there.
//
// Only the image display (URL string -> TImage.Bitmap) stays in code, in the
// OnCompleted handlers, via LoadUrlOrFileToBitmap.

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
  Replicate.Model,
  Replicate.BindSource;   // debug hook + LoadUrlOrFileToBitmap

type
  TFormWorkflow = class(TForm)
    lblToken: TLabel;
    edtToken: TEdit;
    lblPrompt: TLabel;
    edtPrompt: TEdit;
    btnRun: TButton;
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
    ModelGen: TReplicateModel;
    ModelUpscale: TReplicateModel;
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
  FormWorkflow: TFormWorkflow;

implementation

{$R *.fmx}

procedure TFormWorkflow.FormCreate(Sender: TObject);
begin
  ReplicateDebugHook :=
    procedure(ALine: string)
    begin
      memLogs.Lines.Add(ALine);
    end;

  edtToken.Text := GetEnvironmentVariable('REPLICATE_API_TOKEN');

  // TBindExpression.Active is PUBLIC, not published: you can set it in code but
  // it cannot live in the .fmx - the form loader errors on an 'Active =' line
  // because the streamer only sees published properties. So the bindings are
  // drawn in the designer without an Active line and must be turned on at
  // runtime; we do that here.
  LinkGenOut.Active := True;
  LinkUpOut.Active := True;
  LinkChain.Active := True;
end;

procedure TFormWorkflow.btnRunClick(Sender: TObject);
begin
  ModelGen.ApiToken := edtToken.Text;
  ModelUpscale.ApiToken := edtToken.Text;
  ModelGen.SetInputValue('prompt', edtPrompt.Text);
  Log('=== Stage 1: ' + ModelGen.Model + ' ===');
  ModelGen.Run;
end;

procedure TFormWorkflow.GenCompleted(Sender: TObject);
begin
  Log('Stage 1 done: ' + ModelGen.OutputImage);
  if ModelGen.OutputImage <> '' then
    LoadUrlOrFileToBitmap(ModelGen.OutputImage, imgGen.Bitmap);
  // The LinkChain binding has already pushed OutputImage into
  // ModelUpscale.InputImage; AutoRun launches stage 2 with no code here.
end;

procedure TFormWorkflow.UpscaleCompleted(Sender: TObject);
begin
  Log('Stage 2 done: ' + ModelUpscale.OutputImage);
  if ModelUpscale.OutputImage <> '' then
    LoadUrlOrFileToBitmap(ModelUpscale.OutputImage, imgFinal.Bitmap);
  Log('=== Workflow complete ===');
end;

procedure TFormWorkflow.Log(const S: string);
begin
  memLogs.Lines.Add(S);
end;

end.
