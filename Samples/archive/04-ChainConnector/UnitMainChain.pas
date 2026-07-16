unit UnitMainChain;

// Stage 2 sample: chain two Replicate models into a workflow.
//
//   prompt -> [flux-schnell] -> image URL -> [recraft-crisp-upscale] -> upscaled image
//
// input -> output -> input -> output. Each stage is a dataset-backed
// TReplicateDataBindSource. The OUTPUT images are shown purely through
// LiveBindings TLinkControlToField bindings (no code sets the bitmaps). The
// hop that feeds stage 1's output into stage 2's input is one line in the
// OnCompleted handler - the seam a designer field-to-field wire will replace.
//
// UI built in code; the .fmx is an empty shell.

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
  TFormMainChain = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    edtToken: TEdit;
    memPrompt, memLogs: TMemo;
    btnRun: TButton;
    edtGenStatus, edtUpStatus: TEdit;
    imgGen, imgFinal: TImage;
    RepGen, RepUpscale: TReplicateDataBindSource;
    procedure BuildUI;
    procedure WireBindings;
    procedure RunClick(Sender: TObject);
    procedure GenCompleted(Sender: TObject);
    procedure UpscaleCompleted(Sender: TObject);
    procedure LogLine(const S: string);
  public
  end;

var
  FormMainChain: TFormMainChain;

implementation

{$R *.fmx}

const
  CModelGen = 'black-forest-labs/flux-schnell';
  CModelUpscale = 'recraft-ai/recraft-crisp-upscale';

procedure TFormMainChain.FormCreate(Sender: TObject);
begin
  BuildUI;

  ReplicateDebugHook :=
    procedure(ALine: string)
    begin
      memLogs.Lines.Add(ALine);
    end;

  edtToken.Text := GetEnvironmentVariable('REPLICATE_API_TOKEN');

  RepGen := TReplicateDataBindSource.Create(Self);
  RepGen.Debug := True;
  RepGen.ApiToken := edtToken.Text;
  RepGen.Model := CModelGen;
  RepGen.OnCompleted := GenCompleted;

  RepUpscale := TReplicateDataBindSource.Create(Self);
  RepUpscale.Debug := True;
  RepUpscale.ApiToken := edtToken.Text;
  RepUpscale.Model := CModelUpscale;
  RepUpscale.OnCompleted := UpscaleCompleted;

  if edtToken.Text <> '' then
  begin
    try RepGen.LoadSchema; except on E: Exception do LogLine('Gen schema: ' + E.Message); end;
    try RepUpscale.LoadSchema; except on E: Exception do LogLine('Upscale schema: ' + E.Message); end;
  end;

  WireBindings;
end;

procedure TFormMainChain.BuildUI;

  function Lbl(const S: string; X, Y: Single): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := Self;
    Result.Position.X := X; Result.Position.Y := Y; Result.Text := S;
  end;

begin
  Caption := 'Replicate Workflow: Generate -> Upscale';
  Width := 1000; Height := 660;

  Lbl('API Token:', 16, 16);
  edtToken := TEdit.Create(Self); edtToken.Parent := Self;
  edtToken.SetBounds(120, 12, 380, 24); edtToken.Password := True;

  Lbl('Prompt:', 16, 48);
  memPrompt := TMemo.Create(Self); memPrompt.Parent := Self;
  memPrompt.SetBounds(120, 46, 380, 70);
  memPrompt.Text := 'A crisp product photo of a red sports car on a white background';

  btnRun := TButton.Create(Self); btnRun.Parent := Self;
  btnRun.SetBounds(120, 124, 200, 30); btnRun.Text := 'Run Workflow';
  btnRun.OnClick := RunClick;

  Lbl('1) Generate status:', 16, 168);
  edtGenStatus := TEdit.Create(Self); edtGenStatus.Parent := Self;
  edtGenStatus.SetBounds(150, 164, 350, 24); edtGenStatus.ReadOnly := True;

  Lbl('2) Upscale status:', 16, 196);
  edtUpStatus := TEdit.Create(Self); edtUpStatus.Parent := Self;
  edtUpStatus.SetBounds(150, 192, 350, 24); edtUpStatus.ReadOnly := True;

  Lbl('Logs:', 16, 226);
  memLogs := TMemo.Create(Self); memLogs.Parent := Self;
  memLogs.SetBounds(16, 250, 484, 390);

  Lbl('Generated:', 516, 12);
  imgGen := TImage.Create(Self); imgGen.Parent := Self;
  imgGen.SetBounds(516, 32, 466, 290);

  Lbl('Upscaled (final):', 516, 328);
  imgFinal := TImage.Create(Self); imgFinal.Parent := Self;
  imgFinal.SetBounds(516, 348, 466, 292);
end;

procedure TFormMainChain.WireBindings;

  procedure BindField(ASource: TReplicateDataBindSource; const AField: string; AControl: TFmxObject);
  begin
    var L := TLinkControlToField.Create(Self);
    L.DataSource := ASource;
    L.FieldName := AField;
    L.Control := AControl as TComponent;
    L.Active := True;
  end;

begin
  // Outputs and statuses shown purely via LiveBindings - no code sets them.
  BindField(RepGen, 'Status', edtGenStatus);
  BindField(RepGen, 'OutputImage', imgGen);
  BindField(RepUpscale, 'Status', edtUpStatus);
  BindField(RepUpscale, 'OutputImage', imgFinal);

  // THE CHAIN.
  // A TLinkPropertyToField to RepUpscale.InputImage does NOT work: when the
  // Component is a bind source, LiveBindings resolves ComponentProperty against
  // the bind source's FIELD scope (its dataset fields), so the object property
  // 'InputImage' is not found. Stock LiveBindings has no field->field link
  // between two bind sources, so the output->input hop is done here in the
  // upstream OnCompleted (see GenCompleted). AutoRun launches stage 2 as soon
  // as its input is set.
  RepUpscale.AutoRun := True;
end;

procedure TFormMainChain.RunClick(Sender: TObject);
begin
  RepGen.ApiToken := edtToken.Text;
  RepUpscale.ApiToken := edtToken.Text;
  if RepGen.CachedSchema = '' then RepGen.LoadSchema;
  if RepUpscale.CachedSchema = '' then RepUpscale.LoadSchema;

  try
    RepGen.SetInputValue('prompt', memPrompt.Text);
  except
    on E: Exception do LogLine('Set prompt: ' + E.Message);
  end;

  LogLine('=== Stage 1: generating with ' + CModelGen + ' ===');
  RepGen.Run;
end;

procedure TFormMainChain.GenCompleted(Sender: TObject);
var
  LUrl: string;
begin
  LUrl := RepGen.GetOutputValue('image');
  LogLine('Stage 1 done. Image: ' + LUrl);
  if LUrl = '' then Exit;

  // The output->input hop. RepUpscale.AutoRun is True, so setting the input
  // launches stage 2 on its own - no explicit Run here.
  LogLine('=== Stage 2: upscaling -> ' + CModelUpscale + ' ===');
  try
    RepUpscale.SetInputValue('image', LUrl);
  except
    on E: Exception do
      LogLine('Could not set upscale input "image": ' + E.Message +
              ' (check the model''s input field name in the schema log).');
  end;
end;

procedure TFormMainChain.UpscaleCompleted(Sender: TObject);
begin
  LogLine('Stage 2 done. Final image: ' + RepUpscale.GetOutputValue('image'));
  LogLine('=== Workflow complete ===');
end;

procedure TFormMainChain.LogLine(const S: string);
begin
  memLogs.Lines.Add(S);
end;

end.
