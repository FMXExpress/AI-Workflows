unit UnitMainData;

// Stage 1 sample for the dataset-backed TReplicateDataBindSource.
//
// The whole point: bind Status and OutputImage to controls with
// TLinkControlToField and watch them update ON THEIR OWN when a prediction
// completes - no event/fallback code driving the controls. That works because
// the component is a TBindSourceDB over a TFDMemTable and Post fires the
// LiveBindings refresh (the pattern from FMXExpress/Cross-Platform-Samples).
//
// UI is built in code so there is no designer .fmx to fiddle with; the .fmx is
// an empty form shell.

interface

uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Classes,
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
  Data.DB,
  Data.Bind.Components,
  Data.Bind.Controls,
  Fmx.Bind.Editors,
  Data.Bind.DBScope,
  Replicate.DataBindSource,
  Replicate.BindSource;

type
  TFormMainData = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    edtToken, edtModel, edtStatus: TEdit;
    memPrompt, memLogs: TMemo;
    btnLoad, btnRun: TButton;
    imgOutput: TImage;
    Rep: TReplicateDataBindSource;
    procedure BuildUI;
    procedure WireBindings;
    procedure LoadClick(Sender: TObject);
    procedure RunClick(Sender: TObject);
    procedure StatusChanged(Sender: TObject);
    procedure Completed(Sender: TObject);
  public
  end;

var
  FormMainData: TFormMainData;

implementation

{$R *.fmx}

procedure TFormMainData.FormCreate(Sender: TObject);
begin
  BuildUI;

  Rep := TReplicateDataBindSource.Create(Self);
  Rep.Debug := True;
  Rep.OnStatusChanged := StatusChanged;
  Rep.OnCompleted := Completed;

  // Stream every diagnostic line into the logs memo.
  ReplicateDebugHook :=
    procedure(ALine: string)
    begin
      memLogs.Lines.Add(ALine);
    end;

  edtToken.Text := GetEnvironmentVariable('REPLICATE_API_TOKEN');
  edtModel.Text := 'black-forest-labs/flux-schnell';
  memPrompt.Text := 'A vibrant digital painting of a futuristic neon city, cyberpunk, high detail';

  // Load the schema up front (if a token is present) so the input/output fields
  // exist before we wire the links, then bind. If there is no token yet, the
  // stable fields (Status, OutputImage) already exist, so binding still works;
  // click "Load Schema" after pasting a token.
  Rep.ApiToken := edtToken.Text;
  Rep.Model := edtModel.Text;
  if edtToken.Text <> '' then
  try
    Rep.LoadSchema;
  except
    on E: Exception do
      memLogs.Lines.Add('Schema preload failed: ' + E.Message);
  end;

  WireBindings;
end;

procedure TFormMainData.BuildUI;

  function Lbl(const S: string; X, Y: Single): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := Self;
    Result.Position.X := X; Result.Position.Y := Y;
    Result.Text := S;
  end;

begin
  Caption := 'LiveReplicate Data (dataset-backed) Demo';
  Width := 900; Height := 620;

  Lbl('API Token:', 16, 16);
  edtToken := TEdit.Create(Self); edtToken.Parent := Self;
  edtToken.SetBounds(120, 12, 360, 24); edtToken.Password := True;

  Lbl('Model:', 16, 48);
  edtModel := TEdit.Create(Self); edtModel.Parent := Self;
  edtModel.SetBounds(120, 44, 360, 24);

  btnLoad := TButton.Create(Self); btnLoad.Parent := Self;
  btnLoad.SetBounds(496, 12, 150, 26); btnLoad.Text := 'Load Schema';
  btnLoad.OnClick := LoadClick;

  btnRun := TButton.Create(Self); btnRun.Parent := Self;
  btnRun.SetBounds(496, 44, 150, 26); btnRun.Text := 'Generate / Run';
  btnRun.OnClick := RunClick;

  Lbl('Prompt:', 16, 84);
  memPrompt := TMemo.Create(Self); memPrompt.Parent := Self;
  memPrompt.SetBounds(16, 108, 330, 90);

  Lbl('Status (bound):', 16, 206);
  edtStatus := TEdit.Create(Self); edtStatus.Parent := Self;
  edtStatus.SetBounds(120, 202, 226, 24); edtStatus.ReadOnly := True;

  Lbl('Logs:', 16, 236);
  memLogs := TMemo.Create(Self); memLogs.Parent := Self;
  memLogs.SetBounds(16, 260, 330, 330);

  imgOutput := TImage.Create(Self); imgOutput.Parent := Self;
  imgOutput.SetBounds(360, 108, 520, 482);
end;

procedure TFormMainData.WireBindings;
begin
  // Status -> edit. Use a TEdit (not a TLabel): TLabel has no control observer.
  var L1 := TLinkControlToField.Create(Self);
  L1.DataSource := Rep;
  L1.FieldName := 'Status';
  L1.Control := edtStatus;
  L1.Active := True;

  // OutputImage (URL string) -> image. The registered UrlToFmxBitmap converter
  // downloads and decodes it. No code sets the bitmap - the binding does.
  var L2 := TLinkControlToField.Create(Self);
  L2.DataSource := Rep;
  L2.FieldName := 'OutputImage';
  L2.Control := imgOutput;
  L2.Active := True;
end;

procedure TFormMainData.LoadClick(Sender: TObject);
begin
  Rep.ApiToken := edtToken.Text;
  Rep.Model := edtModel.Text;
  try
    Rep.LoadSchema;
    memLogs.Lines.Add('Schema loaded. Version: ' + Rep.ActualVersion);
  except
    on E: Exception do
      ShowMessage('Failed to load schema: ' + E.Message);
  end;
end;

procedure TFormMainData.RunClick(Sender: TObject);
begin
  Rep.ApiToken := edtToken.Text;
  Rep.Model := edtModel.Text;
  if Rep.CachedSchema = '' then
    Rep.LoadSchema;

  try
    Rep.SetInputValue('prompt', memPrompt.Text);
  except
    on E: Exception do
      memLogs.Lines.Add('Could not set prompt: ' + E.Message);
  end;

  memLogs.Lines.Add('Starting prediction...');
  Rep.Run;
end;

procedure TFormMainData.StatusChanged(Sender: TObject);
begin
  // Optional: proves the event fires too. The bound edtStatus updates via the
  // LiveBindings link independently of this.
  if Rep.Table.Active and (Rep.Table.FindField('Status') <> nil) then
    Caption := 'Status: ' + Rep.Table.FieldByName('Status').AsString;
end;

procedure TFormMainData.Completed(Sender: TObject);
begin
  memLogs.Lines.Add('Completed. OutputImage = ' + Rep.GetOutputValue('image'));
  if imgOutput.Bitmap.Width > 0 then
    memLogs.Lines.Add('Image set by the LiveBindings TLinkControlToField binding.')
  else
    memLogs.Lines.Add('NOTE: image not set by the binding (Bitmap.Width = 0).');
end;

end.
