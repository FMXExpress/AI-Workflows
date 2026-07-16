unit UnitCodeFirst;

// CODE-FIRST workflow - the mirror image of 12-PureBindings. No LiveBindings
// Designer, no TBindingsList, no binding components at all: the same
// three-stage pipeline (gpt-oss-20b writes the prompt -> flux-schnell ->
// crisp-upscale) wired with ONE LINE PER WIRE in FormCreate.
//
//   ModelChat.PipeTextTo(ModelGen).PipeImageTo(ModelUp);
//
// is the entire pipeline: each stage pushes its output into the next and
// runs it on success. OnDone/OnState take closures (fired on the main
// thread), so showing a result is a one-liner too. Ask stores the prompt
// and launches - and the source's ApiToken rides down the pipes, so only
// the first stage needs it.
//
// REQUIREMENTS: REPLICATE_API_TOKEN (or paste a token into the edit).

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
  FMX.ScrollBox,
  FMX.Memo,
  FMX.Memo.Types,
  FMX.Objects,
  AI.Engine,
  Replicate.Model,
  Replicate.BindSource;   // LoadUrlOrFileToBitmap

type
  TFormCodeFirst = class(TForm)
    lblToken: TLabel;
    edtToken: TEdit;
    lblBrief: TLabel;
    edtBrief: TEdit;
    btnRun: TButton;
    lblStatus: TLabel;
    ModelChat: TReplicateModel;
    ModelGen: TReplicateModel;
    ModelUp: TReplicateModel;
    lblPrompt: TLabel;
    memPrompt: TMemo;
    lblGen: TLabel;
    imgGen: TImage;
    lblFinal: TLabel;
    imgFinal: TImage;
    procedure FormCreate(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
  end;

var
  FormCodeFirst: TFormCodeFirst;

implementation

{$R *.fmx}

const
  CInstruction =
    'You are an expert image-prompt engineer. Turn this brief into ONE ' +
    'detailed image generation prompt. Reply with the prompt text only - ' +
    'no preamble, no quotes. Brief: ';

procedure TFormCodeFirst.FormCreate(Sender: TObject);
var
  LEngine: TAICustomEngine;
begin
  edtToken.Text := GetEnvironmentVariable('REPLICATE_API_TOKEN');

  // The whole pipeline, one line.
  ModelChat.PipeTextTo(ModelGen).PipeImageTo(ModelUp);

  // One line per thing you want to see.
  ModelChat.OnDone(procedure(E: TAICustomEngine) begin memPrompt.Text := E.OutputText; end);
  ModelGen.OnDone(procedure(E: TAICustomEngine) begin LoadUrlOrFileToBitmap(E.OutputImage, imgGen.Bitmap); end);
  ModelUp.OnDone(procedure(E: TAICustomEngine) begin LoadUrlOrFileToBitmap(E.OutputImage, imgFinal.Bitmap); end);

  // One shared status line for all three stages.
  for LEngine in TArray<TAICustomEngine>.Create(ModelChat, ModelGen, ModelUp) do
    LEngine.OnState(procedure(E: TAICustomEngine)
      begin lblStatus.Text := Trim(E.Model + ': ' + E.Status + ' ' + E.ErrorMessage); end);
end;

procedure TFormCodeFirst.btnRunClick(Sender: TObject);
begin
  ModelChat.ApiToken := edtToken.Text;   // the pipes hand it down the chain
  ModelChat.Ask(CInstruction + edtBrief.Text);
end;

end.
