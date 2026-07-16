unit UnitSchemaFlow;

// SCHEMA-DRIVEN workflow demo - all three schema stages working together:
//
//  1. TReplicateInputPanel (left):  after Load Schemas, the panel reads
//     NodeGen's input schema and BUILDS THE INPUT FORM - one typed editor per
//     schema input (switches for booleans, clamped number boxes, combos for
//     enums, browse buttons for files). No designer bindings, works for any
//     model.
//
//  2. TReplicateSchemaLink (SchemaLink1): the workflow edge as a SCHEMA
//     MAPPING - 'image=output[0]' walks NodeGen's raw output JSON and writes
//     the value into NodeUpscale's 'image' input, then launches it (AutoRun).
//     Right-click the component -> "Map Schemas..." to edit the mapping
//     visually against both models' schemas.
//
//  3. TReplicateOutputItemsSource (OutputItems1): NodeGen's output array
//     normalized to rows (ItemIndex/Name/Value) and bound to the grid with a
//     designer-native TLinkGridToDataSource - multi-output models fan out to
//     list/grid UI visually.
//
// The images still load through the OnCompleted handlers (URL -> bitmap).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  System.Rtti,
  System.Bindings.Outputs,
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
  FMX.Grid,
  FMX.Grid.Style,
  Fmx.Bind.Editors,
  Fmx.Bind.DBEngExt,
  Fmx.Bind.Grid,
  Data.Bind.EngExt,
  Data.Bind.Components,
  Data.Bind.Grid,
  Data.Bind.DBScope,
  Replicate.Model,
  Replicate.Node,
  Replicate.InputPanel,
  Replicate.OutputItemsSource,
  Replicate.SchemaLink,
  Replicate.BindSource;   // debug hook + LoadUrlOrFileToBitmap

type
  TFormSchemaFlow = class(TForm)
    lblToken: TLabel;
    edtToken: TEdit;
    btnLoad: TButton;
    btnRun: TButton;
    lblInputs: TLabel;
    InputPanel1: TReplicateInputPanel;
    NodeGen: TReplicateNode;
    NodeUpscale: TReplicateNode;
    SchemaLink1: TReplicateSchemaLink;
    OutputItems1: TReplicateOutputItemsSource;
    lblItems: TLabel;
    gridOutputs: TStringGrid;
    lblUpOut: TLabel;
    edtUpOut: TEdit;
    lblLogs: TLabel;
    memLogs: TMemo;
    lblGen: TLabel;
    imgGen: TImage;
    lblFinal: TLabel;
    imgFinal: TImage;
    BindingsList1: TBindingsList;
    LinkUpOut: TBindExpression;
    LinkGridItems: TLinkGridToDataSource;
    procedure FormCreate(Sender: TObject);
    procedure btnLoadClick(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure GenCompleted(Sender: TObject);
    procedure UpscaleCompleted(Sender: TObject);
  private
    procedure Log(const S: string);
    procedure ApplyTokens;
  public
  end;

var
  FormSchemaFlow: TFormSchemaFlow;

implementation

{$R *.fmx}

procedure TFormSchemaFlow.FormCreate(Sender: TObject);
begin
  ReplicateDebugHook :=
    procedure(ALine: string)
    begin
      memLogs.Lines.Add(ALine);
    end;

  edtToken.Text := GetEnvironmentVariable('REPLICATE_API_TOKEN');

  // TBindExpression.Active is public (not published): activate at runtime.
  LinkUpOut.Active := True;
end;

procedure TFormSchemaFlow.ApplyTokens;
begin
  NodeGen.ApiToken := edtToken.Text;
  NodeUpscale.ApiToken := edtToken.Text;
end;

procedure TFormSchemaFlow.btnLoadClick(Sender: TObject);
begin
  ApplyTokens;
  Log('Loading schemas...');
  NodeGen.LoadSchema;
  NodeUpscale.LoadSchema;
  InputPanel1.BuildForm;
  Log(Format('Input form built for %s (%d inputs shown above).',
    [NodeGen.Model, InputPanel1.ComponentCount]));
  Log('Upscale mapping: ' + SchemaLink1.Mappings.Text.Trim);
end;

procedure TFormSchemaFlow.btnRunClick(Sender: TObject);
begin
  ApplyTokens;
  Log('=== Stage 1: ' + NodeGen.Model + ' ===');
  NodeGen.Run;
  // Stage 2 launches by itself: SchemaLink1 walks NodeGen's output JSON with
  // 'image=output[0]', writes NodeUpscale's input, and AutoRun fires.
end;

procedure TFormSchemaFlow.GenCompleted(Sender: TObject);
begin
  Log('Stage 1 done: ' + NodeGen.OutputImage);
  if NodeGen.OutputImage <> '' then
    LoadUrlOrFileToBitmap(NodeGen.OutputImage, imgGen.Bitmap);
end;

procedure TFormSchemaFlow.UpscaleCompleted(Sender: TObject);
begin
  Log('Stage 2 done: ' + NodeUpscale.OutputImage);
  if NodeUpscale.OutputImage <> '' then
    LoadUrlOrFileToBitmap(NodeUpscale.OutputImage, imgFinal.Bitmap);
  Log('=== Workflow complete ===');
end;

procedure TFormSchemaFlow.Log(const S: string);
begin
  memLogs.Lines.Add(S);
end;

end.
