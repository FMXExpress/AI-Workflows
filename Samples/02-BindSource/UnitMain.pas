unit UnitMain;

interface

uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Classes,
  System.Variants,
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
  FMX.Objects,
  FMX.Layouts,
  Replicate.BindSource,
  Data.Bind.Components,
  Data.Bind.ObjectScope, FMX.Memo.Types, Data.Bind.EngExt, Fmx.Bind.DBEngExt,
  Data.Bind.Controls, Fmx.Bind.Editors, System.Rtti, System.Bindings.Outputs;

type
  TFormMain = class(TForm)
    pnlTop: TPanel;
    lblApiToken: TLabel;
    edtApiToken: TEdit;
    lblModel: TLabel;
    edtModel: TEdit;
    btnLoadSchema: TButton;
    btnRun: TButton;
    lytMain: TLayout;
    pnlLeft: TPanel;
    lblPrompt: TLabel;
    memPrompt: TMemo;
    pnlRight: TPanel;
    imgOutput: TImage;
    lblStatus: TLabel;
    memLogs: TMemo;
    lblLogs: TLabel;
    ReplicateSource: TReplicateBindSource;
    BindingsList1: TBindingsList;
    LinkControlToField1: TLinkControlToField;
    procedure btnLoadSchemaClick(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    procedure ReplicateStatusChanged(Sender: TObject);
    procedure ReplicateCompleted(Sender: TObject);
  public
    { Public declarations }
  end;

var
  FormMain: TFormMain;

implementation

{$R *.fmx}

procedure TFormMain.FormCreate(Sender: TObject);
begin
  // Set default model
  edtModel.Text := 'black-forest-labs/flux-schnell';
  
  // Look for API token in environment if not set
 // edtApiToken.Text := GetEnvironmentVariable('REPLICATE_API_TOKEN');
 // if edtApiToken.Text = '' then
 //   edtApiToken.Text := 'PASTE_YOUR_REPLICATE_API_TOKEN_HERE';
    
  memPrompt.Text := 'A vibrant digital painting of a futuristic neon city under a starry sky, cyberpunk aesthetic, high detail';

  // DEBUG: stream every diagnostic line from the component (schema fetch,
  // HTTP status codes, request bodies, polling, binding field creation,
  // converter activity, errors) straight into the logs memo. This makes any
  // failure visible instead of silent. Debug := True also mirrors the lines
  // to OutputDebugString, so they appear in the IDE Event Log while debugging.
  ReplicateDebugHook :=
    procedure(ALine: string)
    begin
      memLogs.Lines.Add(ALine);
    end;
  ReplicateSource.Debug := True;

  // DRAG-AND-DROP LIVEBINDINGS (the goal).
  // The image binding is wired visually in the LiveBindings Designer and lives
  // in the form: BindingsList1 -> LinkControlToField1, binding
  // ReplicateSource 'Output.image' -> imgOutput. TLinkControlToField (the link
  // the designer creates when you drop a field on a control) subscribes to the
  // bind source's refresh cycle, so it re-reads on DataSetChanged and runs the
  // UrlToFmxBitmap converter. No code is needed for it - that is the point.
  //
  // Do NOT create a TLinkControlToField for the Status TLabel: TLabel has no
  // LiveBindings control observer, so activating one raises "TLabel does not
  // have an observer". A label is display-only, so it is updated from an event
  // instead (simplest correct choice for a control with no observer).
  ReplicateSource.OnStatusChanged := ReplicateStatusChanged;
  ReplicateSource.OnCompleted := ReplicateCompleted;
end;

procedure TFormMain.ReplicateStatusChanged(Sender: TObject);
begin
  // Fires on the main thread for the initial state and every poll tick.
  lblStatus.Text := 'Status: ' + ReplicateSource.Status;
end;

procedure TFormMain.ReplicateCompleted(Sender: TObject);
var
  LUrl: string;
begin
  LUrl := ReplicateSource.GetOutputValue('image').ToString;
  memLogs.Lines.Add('Completed. Output.image = ' + LUrl);

  // Diagnostic: did the designer's TLinkControlToField set the image on its
  // own? If so the pure LiveBindings path works and the fallback is not used.
  if imgOutput.Bitmap.Width > 0 then
    memLogs.Lines.Add('Image set by the LiveBindings TLinkControlToField binding.')
  else if LUrl <> '' then
  begin
    memLogs.Lines.Add('LiveBindings did not set the image - loading directly as a fallback.');
    LoadUrlOrFileToBitmap(LUrl, imgOutput.Bitmap);
  end;
end;

procedure TFormMain.FormShow(Sender: TObject);
begin
  ReplicateSource.ApiToken := edtApiToken.Text;
  ReplicateSource.Model := edtModel.Text;

  try
    ReplicateSource.LoadSchema;
  except
    on E: Exception do
    begin
      memLogs.Lines.Add('Failed to pre-load schema: ' + E.Message);
    end;
  end;
end;

procedure TFormMain.btnLoadSchemaClick(Sender: TObject);
begin
  if (edtApiToken.Text = '') or (edtApiToken.Text.StartsWith('PASTE_')) then
  begin
    ShowMessage('Please enter a valid Replicate API Token.');
    Exit;
  end;

  ReplicateSource.ApiToken := edtApiToken.Text;
  ReplicateSource.Model := edtModel.Text;

  try
    ReplicateSource.LoadSchema;
    ShowMessage('Successfully loaded schema for ' + edtModel.Text + '!' + #13#10 + 
                'The input and output fields have been dynamically built.');
  except
    on E: Exception do
      ShowMessage('Failed to load model schema: ' + E.Message);
  end;
end;

procedure TFormMain.btnRunClick(Sender: TObject);
begin
  if (edtApiToken.Text = '') or (edtApiToken.Text.StartsWith('PASTE_')) then
  begin
    ShowMessage('Please enter a valid Replicate API Token.');
    Exit;
  end;

  ReplicateSource.ApiToken := edtApiToken.Text;
  ReplicateSource.Model := edtModel.Text;
  
  // Foolproof schema loading: if we have never loaded the schema, load it now!
  if ReplicateSource.CachedSchema = '' then
  begin
    try
      ReplicateSource.LoadSchema;
    except
      on E: Exception do
      begin
        ShowMessage('Failed to fetch model schema: ' + E.Message);
        Exit;
      end;
    end;
  end;

  // Set the prompt dynamically
  try
    ReplicateSource.SetInputValue('prompt', memPrompt.Text);
  except
    on E: Exception do
    begin
      ShowMessage('Error setting prompt input: ' + E.Message + #13#10 + 
                  'We will try running with default inputs.');
    end;
  end;

  // Ask for PNG output: FMX's TBitmap decodes PNG on every platform, whereas
  // the model's default WebP needs a Windows WebP codec that is not always
  // installed. Ignored if the model has no output_format input.
  try
    ReplicateSource.SetInputValue('output_format', 'png');
  except
    // model does not expose output_format - keep its default
  end;

  // Run the prediction!
  memLogs.Lines.Add('Starting prediction...');
  ReplicateSource.Run;
end;

end.
