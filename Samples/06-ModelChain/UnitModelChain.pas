unit UnitModelChain;

// SPIKE + demo for TReplicateModel (the observable-object component).
//
// Validates the architecture the dataset component can't do: bind one model's
// OUTPUT property straight into another model's INPUT property. Because these
// are ordinary published properties (not read-only virtual bind-source members),
// a property->property binding is writable and legal, and TBindings.Notify makes
// it refresh. If this works, source->source chaining is real - no relay, no
// virtual-member wall.
//
// The three bindings below are created in code via TBindExpression - which is
// exactly what the LiveBindings Designer emits, so once this is confirmed the
// same objects go straight into an .fmx BindingsList as drawn lines:
//
//   ModelGen.OutputImage      -> edtGenOut.Text         (proves Notify refreshes)
//   ModelGen.OutputImage      -> ModelUpscale.InputImage (THE chain, prop->prop)
//   ModelUpscale.OutputImage  -> edtUpOut.Text
//
// ModelUpscale.AutoRun=True, so writing its InputImage launches stage 2.

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
  Data.Bind.Components,   // TBindExpression, TExpressionDirection
  Replicate.Model,
  Replicate.BindSource;   // debug hook + LoadUrlOrFileToBitmap

type
  TFormModelChain = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    edtToken, edtPrompt, edtGenOut, edtUpOut: TEdit;
    btnRun: TButton;
    memLogs: TMemo;
    imgGen, imgFinal: TImage;
    ModelGen, ModelUpscale: TReplicateModel;
    procedure BuildUI;
    procedure WireBindings;
    procedure RunClick(Sender: TObject);
    procedure GenCompleted(Sender: TObject);
    procedure UpscaleCompleted(Sender: TObject);
    procedure Log(const S: string);
  public
  end;

var
  FormModelChain: TFormModelChain;

implementation

{$R *.fmx}

const
  CModelGen = 'black-forest-labs/flux-schnell';
  CModelUpscale = 'recraft-ai/recraft-crisp-upscale';

procedure TFormModelChain.FormCreate(Sender: TObject);
begin
  BuildUI;

  ReplicateDebugHook :=
    procedure(ALine: string)
    begin
      memLogs.Lines.Add(ALine);
    end;

  edtToken.Text := GetEnvironmentVariable('REPLICATE_API_TOKEN');

  ModelGen := TReplicateModel.Create(Self);
  ModelGen.Debug := True;
  ModelGen.Model := CModelGen;
  ModelGen.OnCompleted := GenCompleted;

  ModelUpscale := TReplicateModel.Create(Self);
  ModelUpscale.Debug := True;
  ModelUpscale.Model := CModelUpscale;
  ModelUpscale.AutoRun := True;   // fires when its InputImage is written
  ModelUpscale.OnCompleted := UpscaleCompleted;

  WireBindings;
end;

procedure TFormModelChain.BuildUI;

  function Lbl(const S: string; X, Y: Single): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := Self;
    Result.Position.X := X; Result.Position.Y := Y; Result.Text := S;
  end;

begin
  Caption := 'Replicate Model Chain (observable objects)';
  Width := 1000; Height := 640;

  Lbl('API Token:', 16, 16);
  edtToken := TEdit.Create(Self); edtToken.Parent := Self;
  edtToken.SetBounds(120, 12, 380, 24); edtToken.Password := True;

  Lbl('Prompt:', 16, 48);
  edtPrompt := TEdit.Create(Self); edtPrompt.Parent := Self;
  edtPrompt.SetBounds(120, 44, 380, 24);
  edtPrompt.Text := 'A crisp product photo of a red sports car on a white background';

  btnRun := TButton.Create(Self); btnRun.Parent := Self;
  btnRun.SetBounds(120, 78, 200, 30); btnRun.Text := 'Run Workflow';
  btnRun.OnClick := RunClick;

  Lbl('Gen OutputImage (bound):', 16, 122);
  edtGenOut := TEdit.Create(Self); edtGenOut.Parent := Self;
  edtGenOut.SetBounds(200, 118, 300, 24); edtGenOut.ReadOnly := True;

  Lbl('Upscale OutputImage (bound):', 16, 150);
  edtUpOut := TEdit.Create(Self); edtUpOut.Parent := Self;
  edtUpOut.SetBounds(200, 146, 300, 24); edtUpOut.ReadOnly := True;

  Lbl('Logs:', 16, 180);
  memLogs := TMemo.Create(Self); memLogs.Parent := Self;
  memLogs.SetBounds(16, 204, 484, 416);

  Lbl('Generated:', 516, 12);
  imgGen := TImage.Create(Self); imgGen.Parent := Self;
  imgGen.SetBounds(516, 32, 466, 288);

  Lbl('Upscaled (final):', 516, 328);
  imgFinal := TImage.Create(Self); imgFinal.Parent := Self;
  imgFinal.SetBounds(516, 348, 466, 272);
end;

procedure TFormModelChain.WireBindings;

  function Expr(ASource: TComponent; const ASrcExpr: string;
                AControl: TComponent; const ACtrlExpr: string): TBindExpression;
  begin
    Result := TBindExpression.Create(Self);
    Result.Category := 'Binding Expressions';
    Result.SourceComponent := ASource;
    Result.SourceExpression := ASrcExpr;
    Result.ControlComponent := AControl;
    Result.ControlExpression := ACtrlExpr;
    Result.Direction := TExpressionDirection.dirSourceToControl;
    Result.NotifyOutputs := True;
    Result.Active := True;
  end;

begin
  // Litmus test: does TBindings.Notify refresh an object-property binding?
  Expr(ModelGen, 'OutputImage', edtGenOut, 'Text');
  Expr(ModelUpscale, 'OutputImage', edtUpOut, 'Text');

  // THE CHAIN - one model's output property straight into another's input
  // property. Writable target (a real setter), so no "virtual members are read
  // only". Setting InputImage (with AutoRun) launches stage 2.
  Expr(ModelGen, 'OutputImage', ModelUpscale, 'InputImage');
end;

procedure TFormModelChain.RunClick(Sender: TObject);
begin
  ModelGen.ApiToken := edtToken.Text;
  ModelUpscale.ApiToken := edtToken.Text;
  ModelGen.SetInputValue('prompt', edtPrompt.Text);
  Log('=== Stage 1: ' + CModelGen + ' ===');
  ModelGen.Run;
end;

procedure TFormModelChain.GenCompleted(Sender: TObject);
begin
  Log('Stage 1 done: ' + ModelGen.OutputImage);
  if ModelGen.OutputImage <> '' then
    LoadUrlOrFileToBitmap(ModelGen.OutputImage, imgGen.Bitmap);
end;

procedure TFormModelChain.UpscaleCompleted(Sender: TObject);
begin
  Log('Stage 2 done: ' + ModelUpscale.OutputImage);
  if ModelUpscale.OutputImage <> '' then
    LoadUrlOrFileToBitmap(ModelUpscale.OutputImage, imgFinal.Bitmap);
  Log('=== Workflow complete ===');
end;

procedure TFormModelChain.Log(const S: string);
begin
  memLogs.Lines.Add(S);
end;

end.
