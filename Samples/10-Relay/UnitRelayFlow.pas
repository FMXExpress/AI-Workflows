unit UnitRelayFlow;

// RELAY workflow demo - the nexus done right, with a JSON field picker.
//
// Replicate's output is JSON; the next model's input is a named JSON field.
// The relay couples them with ordinary designer lines (see UnitRelayFlow.fmx):
//
//   LinkJSONToRelay:  NodeGen.OutputJSON  -> Relay1.Input      (whole JSON in)
//   Relay1.InputPath = 'output[0]'                             (pick the field)
//   LinkRelayToInput: Relay1.Output       -> NodeUpscale.InputImage
//   LinkUpOut:        NodeUpscale.OutputImage -> edtUpOut.Text
//
// So the "which field of the output goes where" decision is a PROPERTY on a
// visible component sitting on the wire - change InputPath to 'output.text'
// and the same wiring channels a text output into the next stage instead.
// Draw Relay1.Output into InputPrompt rather than InputImage and you have the
// "output -> prompt" channel. NodeUpscale.AutoRun launches stage 2 when the
// relayed value lands.
//
// The relay also paints its path and current value, so the form shows the
// workflow AND the data moving through it.

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
  Data.Bind.Components,
  Replicate.Model,
  Replicate.Node,
  Replicate.Relay,
  Replicate.BindSource;   // debug hook + LoadUrlOrFileToBitmap

type
  TFormRelayFlow = class(TForm)
    lblToken: TLabel;
    edtToken: TEdit;
    lblPrompt: TLabel;
    edtPrompt: TEdit;
    btnRun: TButton;
    NodeGen: TReplicateNode;
    Relay1: TReplicateRelay;
    NodeUpscale: TReplicateNode;
    lblUpOut: TLabel;
    edtUpOut: TEdit;
    lblLogs: TLabel;
    memLogs: TMemo;
    lblGen: TLabel;
    imgGen: TImage;
    lblFinal: TLabel;
    imgFinal: TImage;
    BindingsList1: TBindingsList;
    LinkJSONToRelay: TBindExpression;
    LinkRelayToInput: TBindExpression;
    LinkUpOut: TBindExpression;
    procedure FormCreate(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure GenCompleted(Sender: TObject);
    procedure UpscaleCompleted(Sender: TObject);
  private
    procedure Log(const S: string);
  public
  end;

var
  FormRelayFlow: TFormRelayFlow;

implementation

{$R *.fmx}

procedure TFormRelayFlow.FormCreate(Sender: TObject);
begin
  ReplicateDebugHook :=
    procedure(ALine: string)
    begin
      memLogs.Lines.Add(ALine);
    end;

  edtToken.Text := GetEnvironmentVariable('REPLICATE_API_TOKEN');

  // TBindExpression.Active is public (not published): activate at runtime.
  LinkJSONToRelay.Active := True;
  LinkRelayToInput.Active := True;
  LinkUpOut.Active := True;
end;

procedure TFormRelayFlow.btnRunClick(Sender: TObject);
begin
  NodeGen.ApiToken := edtToken.Text;
  NodeUpscale.ApiToken := edtToken.Text;
  NodeGen.SetInputValue('prompt', edtPrompt.Text);
  Log('=== Stage 1: ' + NodeGen.Model + ' ===');
  NodeGen.Run;
  // Stage 2 launches by itself: OutputJSON flows into the relay, InputPath
  // picks output[0], the extracted URL lands in NodeUpscale.InputImage, and
  // AutoRun fires.
end;

procedure TFormRelayFlow.GenCompleted(Sender: TObject);
begin
  Log('Stage 1 done: ' + NodeGen.OutputImage);
  Log('Relay passed on: ' + Relay1.Output);
  if NodeGen.OutputImage <> '' then
    LoadUrlOrFileToBitmap(NodeGen.OutputImage, imgGen.Bitmap);
end;

procedure TFormRelayFlow.UpscaleCompleted(Sender: TObject);
begin
  Log('Stage 2 done: ' + NodeUpscale.OutputImage);
  if NodeUpscale.OutputImage <> '' then
    LoadUrlOrFileToBitmap(NodeUpscale.OutputImage, imgFinal.Bitmap);
  Log('=== Workflow complete ===');
end;

procedure TFormRelayFlow.Log(const S: string);
begin
  memLogs.Lines.Add(S);
end;

end.
