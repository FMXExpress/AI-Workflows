unit UnitChainDemo;

// Fully-wired workflow chain - ALL links are LiveBindings, set up in the .fmx
// (open the LiveBindings Designer to see the drawn lines):
//
//   edtPrompt.Text           -> ReplicateGen.Input_prompt       (LinkPrompt)
//   ReplicateGen.Status      -> edtGenStatus.Text               (LinkGenStatus)
//   ReplicateGen.OutputImage -> imgGen.Bitmap                   (LinkGenImage)
//   ReplicateGen.OutputImage -> edtNexus.Text                   (LinkGenToNexus)   \
//   edtNexus.Text            -> ReplicateUpscale.Input_image    (LinkNexusToUpscale)/ <- the chain
//   ReplicateUpscale.Status  -> edtUpStatus.Text                (LinkUpStatus)
//   ReplicateUpscale.OutputImage -> imgFinal.Bitmap             (LinkFinalImage)
//
// THE CHAIN goes through edtNexus, a read-only TEdit acting as the relay/nexus.
// LiveBindings cannot link two bind sources directly (a bind source field is a
// read-only virtual member as a binding target - "virtual members are read
// only"), but it CAN write into a control and read out of it. So the edge is two
// TLinkControlToField lines through the nexus edit: A's output writes it, and it
// writes B's input. Both are drawn lines in the LiveBindings Designer. Set
// edtNexus.Visible := False to make the nexus non-visual.
//
// ReplicateUpscale.AutoRun = True, so when LinkNexusToUpscale writes Input_image
// the upscale stage runs on its own. Click Run: stage 1 generates, its output
// flows through the nexus into stage 2's input, stage 2 upscales - no chaining
// code. This unit only sets tokens and starts stage 1.

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
  Data.Bind.Components,
  Data.Bind.Controls,
  Fmx.Bind.Editors,
  Data.Bind.DBScope,
  Replicate.DataBindSource,
  Replicate.BindSource;

type
  TFormChainDemo = class(TForm)
    lblToken: TLabel;
    edtToken: TEdit;
    lblPrompt: TLabel;
    edtPrompt: TEdit;
    btnRun: TButton;
    lblGenStatus: TLabel;
    edtGenStatus: TEdit;
    lblUpStatus: TLabel;
    edtUpStatus: TEdit;
    lblLogs: TLabel;
    memLogs: TMemo;
    lblGen: TLabel;
    imgGen: TImage;
    lblFinal: TLabel;
    imgFinal: TImage;
    lblNexus: TLabel;
    edtNexus: TEdit;
    ReplicateGen: TReplicateDataBindSource;
    ReplicateUpscale: TReplicateDataBindSource;
    BindingsList1: TBindingsList;
    LinkPrompt: TLinkControlToField;
    LinkGenStatus: TLinkControlToField;
    LinkGenImage: TLinkControlToField;
    LinkUpStatus: TLinkControlToField;
    LinkFinalImage: TLinkControlToField;
    LinkGenToNexus: TLinkControlToField;
    LinkNexusToUpscale: TLinkControlToField;
    procedure FormCreate(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
  private
    procedure GenCompleted(Sender: TObject);
    procedure UpscaleCompleted(Sender: TObject);
    procedure Log(const S: string);
  public
  end;

var
  FormChainDemo: TFormChainDemo;

implementation

{$R *.fmx}

procedure TFormChainDemo.FormCreate(Sender: TObject);
var
  LToken: string;
begin
  ReplicateDebugHook :=
    procedure(ALine: string)
    begin
      memLogs.Lines.Add(ALine);
    end;

  ReplicateGen.Debug := True;
  ReplicateUpscale.Debug := True;

  LToken := GetEnvironmentVariable('REPLICATE_API_TOKEN');
  edtToken.Text := LToken;
  ReplicateGen.ApiToken := LToken;
  ReplicateUpscale.ApiToken := LToken;

  ReplicateGen.OnCompleted := GenCompleted;
  ReplicateUpscale.OnCompleted := UpscaleCompleted;

  // Seed the prompt through the field so the bound edit shows it (and Run picks
  // it up). The user can edit it; the LinkPrompt binding keeps the field in sync.
  ReplicateGen.SetInputValue('prompt',
    'A crisp product photo of a red sports car on a white background');
end;

procedure TFormChainDemo.btnRunClick(Sender: TObject);
begin
  ReplicateGen.ApiToken := edtToken.Text;
  ReplicateUpscale.ApiToken := edtToken.Text;
  Log('=== Stage 1: generating with ' + ReplicateGen.Model + ' ===');
  // The prompt is already in ReplicateGen.Input_prompt via LinkPrompt.
  ReplicateGen.Run;
end;

procedure TFormChainDemo.GenCompleted(Sender: TObject);
begin
  // Logging only - the chain runs through the nexus relay bindings, no code.
  Log('Stage 1 done: ' + ReplicateGen.GetOutputValue('image'));
  Log('=== Stage 2: upscaling via LiveBindings chain -> ' + ReplicateUpscale.Model + ' ===');
end;

procedure TFormChainDemo.UpscaleCompleted(Sender: TObject);
begin
  Log('Stage 2 done: ' + ReplicateUpscale.GetOutputValue('image'));
  Log('=== Workflow complete ===');
end;

procedure TFormChainDemo.Log(const S: string);
begin
  memLogs.Lines.Add(S);
end;

end.
