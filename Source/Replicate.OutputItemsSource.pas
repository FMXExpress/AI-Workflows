unit Replicate.OutputItemsSource;

// TReplicateOutputItemsSource - a bind source over a model's OUTPUT ITEMS.
//
// Replicate models routinely return arrays (multiple images, token lists).
// The node's OutputImage/OutputText properties flatten that to "first item" /
// "joined text". This component applies the FireDAC normalize-to-dataset
// pattern instead: it is a TBindSourceDB over its own TFDMemTable with a
// FIXED row schema (ItemIndex / Name / Value), so grids, list views and
// list-control links - which only speak bind source - can bind a model's
// full multi-output VISUALLY in the LiveBindings Designer.
//
// The fields exist from construction (the schema is fixed), so the designer
// shows them with no data and no network. At runtime the component subscribes
// to the model/node's output notification and copies the engine's flattened
// OutputItems rows into its table on every successful completion - one Post-
// driven refresh, and every attached link updates.
//
// Set either Node (TReplicateNode) or Model (TReplicateModel); Node wins if
// both are assigned.

interface

uses
  System.SysUtils,
  System.Classes,
  Data.DB,
  Data.Bind.DBScope,
  FireDAC.Comp.Client,
  AI.Engine,
  Replicate.Model,
  Replicate.Node;

type
  TReplicateOutputItemsSource = class(TBindSourceDB)
  private
    FTable: TFDMemTable;
    FModel: TReplicateModel;
    FNode: TReplicateNode;
    FSubscribed: TAICustomEngine;   // engine we are currently listening to
    procedure SetModel(const AValue: TReplicateModel);
    procedure SetNode(const AValue: TReplicateNode);
    function ActiveEngine: TAICustomEngine;
    procedure Resubscribe;
    procedure OutputReady(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Copy the engine's current output rows now (also runs automatically on
    // each successful completion).
    procedure RefreshItems;

    property Table: TFDMemTable read FTable;
  published
    property Node: TReplicateNode read FNode write SetNode;
    property Model: TReplicateModel read FModel write SetModel;
  end;

procedure Register;

implementation

{ TReplicateOutputItemsSource }

constructor TReplicateOutputItemsSource.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Fixed schema, created immediately: the designer needs the fields to exist
  // with no data and no engine attached.
  FTable := TFDMemTable.Create(Self);
  FTable.Name := 'ItemsTable';
  FTable.SetSubComponent(True);
  FTable.FieldDefs.Add('ItemIndex', ftInteger);
  FTable.FieldDefs.Add('Name', ftString, 100);
  FTable.FieldDefs.Add('Value', ftString, 4000);
  FTable.CreateDataSet;
  DataSet := FTable;
end;

destructor TReplicateOutputItemsSource.Destroy;
begin
  if FSubscribed <> nil then
    FSubscribed.RemoveOutputListener(OutputReady);
  inherited;
end;

function TReplicateOutputItemsSource.ActiveEngine: TAICustomEngine;
begin
  if FNode <> nil then
    Result := FNode.Engine
  else
    Result := FModel;
end;

procedure TReplicateOutputItemsSource.Resubscribe;
var
  LEngine: TAICustomEngine;
begin
  LEngine := ActiveEngine;
  if LEngine = FSubscribed then Exit;
  if FSubscribed <> nil then
    FSubscribed.RemoveOutputListener(OutputReady);
  FSubscribed := LEngine;
  if FSubscribed <> nil then
    FSubscribed.AddOutputListener(OutputReady);
end;

procedure TReplicateOutputItemsSource.SetNode(const AValue: TReplicateNode);
begin
  if FNode = AValue then Exit;
  if FNode <> nil then FNode.RemoveFreeNotification(Self);
  FNode := AValue;
  if FNode <> nil then FNode.FreeNotification(Self);
  Resubscribe;
end;

procedure TReplicateOutputItemsSource.SetModel(const AValue: TReplicateModel);
begin
  if FModel = AValue then Exit;
  if FModel <> nil then FModel.RemoveFreeNotification(Self);
  FModel := AValue;
  if FModel <> nil then FModel.FreeNotification(Self);
  Resubscribe;
end;

procedure TReplicateOutputItemsSource.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    // The engine dies with its owner; drop the subscription reference first.
    if (AComponent = FNode) or (AComponent = FModel) then
      FSubscribed := nil;
    if AComponent = FNode then FNode := nil;
    if AComponent = FModel then FModel := nil;
  end;
end;

procedure TReplicateOutputItemsSource.OutputReady(Sender: TObject);
begin
  RefreshItems;
end;

procedure TReplicateOutputItemsSource.RefreshItems;
var
  LEngine: TAICustomEngine;
  LSource: TFDMemTable;
begin
  LEngine := ActiveEngine;
  if (LEngine = nil) or not FTable.Active then Exit;
  LSource := LEngine.OutputItems;
  if (LSource = nil) or not LSource.Active then Exit;

  FTable.DisableControls;
  try
    FTable.EmptyDataSet;
    LSource.First;
    while not LSource.Eof do
    begin
      FTable.Append;
      FTable.FieldByName('ItemIndex').AsInteger :=
        LSource.FieldByName('ItemIndex').AsInteger;
      FTable.FieldByName('Name').AsString :=
        LSource.FieldByName('Name').AsString;
      FTable.FieldByName('Value').AsString :=
        LSource.FieldByName('Value').AsString;
      FTable.Post;
      LSource.Next;
    end;
    FTable.First;
  finally
    FTable.EnableControls;   // one refresh for the whole batch
  end;
end;

procedure Register;
begin
  RegisterComponents('Replicate', [TReplicateOutputItemsSource]);
end;

initialization
  RegisterClass(TReplicateOutputItemsSource);

finalization
  UnRegisterClass(TReplicateOutputItemsSource);

end.
