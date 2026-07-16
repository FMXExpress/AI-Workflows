unit Replicate.InputPanel;

// TReplicateInputPanel - a control that BUILDS AN INPUT FORM FROM THE SCHEMA.
//
// Point it at a TReplicateNode (or TReplicateModel), call BuildForm once the
// schema is available, and it generates one labeled editor per schema input:
//
//   boolean                          -> TSwitch
//   integer/number with min+max      -> TTrackBar + live value label
//   enum (inline or $ref'd)          -> TComboBox
//   string with uri format / image-ish name -> TEdit + browse button
//   anything else                    -> TEdit
//
// Defaults are pre-filled from the schema, descriptions become hints, and
// x-order drives layout order. Every edit writes through SetInputValueNoRun -
// deliberately NOT the auto-running setter, because a half-typed prompt must
// never launch a prediction; Run stays an explicit act (button, chain, code).
//
// This is the runtime answer to "a dialog that looks at the JSON schema and
// automatically builds it as a form": no designer bindings are involved, so
// it works for ANY model with zero configuration. (For designer-native
// per-field lines, see the generated-form verb on TReplicateDataBindSource.)

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  FMX.Types,
  FMX.Controls,
  FMX.Layouts,
  FMX.StdCtrls,
  FMX.Edit,
  FMX.ListBox,
  FMX.Dialogs,
  Replicate.Model,
  Replicate.Node;

type
  TReplicateInputPanel = class(TVertScrollBox)
  private type
    TSchemaInput = record
      Name: string;
      JType: string;        // string / integer / number / boolean
      Title: string;
      Description: string;
      Default: string;
      Format: string;       // e.g. 'uri'
      Enum: TArray<string>;
      Min, Max: Double;
      HasMin, HasMax: Boolean;
      Order: Integer;
    end;
  private
    FNode: TReplicateNode;
    FModel: TReplicateModel;
    FBuilt: TList<TControl>;
    FOpenDialog: TOpenDialog;
    procedure SetNode(const AValue: TReplicateNode);
    procedure SetModel(const AValue: TReplicateModel);
    function ActiveEngine: TReplicateModel;
    function ParseInputs(const ASchema: string): TArray<TSchemaInput>;
    procedure ClearForm;
    procedure WriteInput(const AName, AValue: string);
    procedure EditChanged(Sender: TObject);
    procedure SwitchChanged(Sender: TObject);
    procedure NumberChanged(Sender: TObject);
    procedure ComboChanged(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // (Re)generate the editors from the engine's CachedSchema. Call after the
    // schema is available (LoadSchema, streamed CachedSchema, or a run).
    procedure BuildForm;
  published
    property Node: TReplicateNode read FNode write SetNode;
    property Model: TReplicateModel read FModel write SetModel;
  end;

procedure Register;

implementation

const
  CRowIndent = 12;
  CLabelHeight = 16;
  CEditorHeight = 28;
  CRowGap = 10;

{ TReplicateInputPanel }

constructor TReplicateInputPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBuilt := TList<TControl>.Create;
  Width := 320;
  Height := 400;
  ShowHint := True;
end;

destructor TReplicateInputPanel.Destroy;
begin
  FBuilt.Free;
  inherited;
end;

procedure TReplicateInputPanel.SetNode(const AValue: TReplicateNode);
begin
  if FNode = AValue then Exit;
  if FNode <> nil then FNode.RemoveFreeNotification(Self);
  FNode := AValue;
  if FNode <> nil then FNode.FreeNotification(Self);
end;

procedure TReplicateInputPanel.SetModel(const AValue: TReplicateModel);
begin
  if FModel = AValue then Exit;
  if FModel <> nil then FModel.RemoveFreeNotification(Self);
  FModel := AValue;
  if FModel <> nil then FModel.FreeNotification(Self);
end;

procedure TReplicateInputPanel.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FNode then FNode := nil;
    if AComponent = FModel then FModel := nil;
  end;
end;

function TReplicateInputPanel.ActiveEngine: TReplicateModel;
begin
  if FNode <> nil then
    Result := FNode.Engine
  else
    Result := FModel;
end;

function TReplicateInputPanel.ParseInputs(const ASchema: string): TArray<TSchemaInput>;
var
  LRoot, LComponents, LSchemas, LInput, LProps, LProp, LRefObj: TJSONObject;
  LPair: TJSONPair;
  LVal: TJSONValue;
  LList: TList<TSchemaInput>;
  LItem: TSchemaInput;
  LEnumArr, LAllOf: TJSONArray;
  LRef: string;
  I: Integer;

  function ResolveRef(const ARef: string): TJSONObject;
  var
    LName: string;
  begin
    // '#/components/schemas/Xxx' -> components.schemas.Xxx
    Result := nil;
    LName := ARef.Substring(ARef.LastIndexOf('/') + 1);
    if (LSchemas <> nil) and (LName <> '') then
      Result := LSchemas.GetValue(LName) as TJSONObject;
  end;

  procedure ReadEnum(AObj: TJSONObject);
  var
    J: Integer;
  begin
    if AObj.TryGetValue<TJSONArray>('enum', LEnumArr) then
    begin
      SetLength(LItem.Enum, LEnumArr.Count);
      for J := 0 to LEnumArr.Count - 1 do
        LItem.Enum[J] := LEnumArr.Items[J].Value;
      // enum refs carry the value type on the ref'd object
      LItem.JType := AObj.GetValue<string>('type', LItem.JType);
    end;
  end;

begin
  Result := nil;
  LRoot := TJSONObject.ParseJSONValue(ASchema) as TJSONObject;
  if LRoot = nil then Exit;
  LList := TList<TSchemaInput>.Create;
  try
    LSchemas := nil;
    LComponents := LRoot.GetValue('components') as TJSONObject;
    LInput := nil;
    if LComponents <> nil then
    begin
      LSchemas := LComponents.GetValue('schemas') as TJSONObject;
      if LSchemas <> nil then
        LInput := LSchemas.GetValue('Input') as TJSONObject;
    end
    else
      LInput := LRoot;
    if LInput = nil then Exit;
    LProps := LInput.GetValue('properties') as TJSONObject;
    if LProps = nil then Exit;

    for LPair in LProps do
    begin
      if not (LPair.JsonValue is TJSONObject) then Continue;
      LProp := LPair.JsonValue as TJSONObject;

      LItem := Default(TSchemaInput);
      LItem.Name := LPair.JsonString.Value;
      LItem.JType := LProp.GetValue<string>('type', 'string');
      LItem.Title := LProp.GetValue<string>('title', LItem.Name);
      LItem.Description := LProp.GetValue<string>('description', '');
      LItem.Format := LProp.GetValue<string>('format', '');
      LItem.Order := LProp.GetValue<Integer>('x-order', MaxInt);
      LVal := LProp.GetValue('default');
      if (LVal <> nil) and not (LVal is TJSONNull) then
        LItem.Default := LVal.Value;
      if LProp.TryGetValue<Double>('minimum', LItem.Min) then LItem.HasMin := True;
      if LProp.TryGetValue<Double>('maximum', LItem.Max) then LItem.HasMax := True;

      // enums: inline, or the Replicate-typical allOf -> $ref -> enum shape
      ReadEnum(LProp);
      if (Length(LItem.Enum) = 0) and
         LProp.TryGetValue<TJSONArray>('allOf', LAllOf) and (LAllOf.Count > 0) and
         (LAllOf.Items[0] is TJSONObject) and
         (LAllOf.Items[0] as TJSONObject).TryGetValue<string>('$ref', LRef) then
      begin
        LRefObj := ResolveRef(LRef);
        if LRefObj <> nil then
          ReadEnum(LRefObj);
      end;

      LList.Add(LItem);
    end;

    LList.Sort(TComparer<TSchemaInput>.Construct(
      function(const L, R: TSchemaInput): Integer
      begin
        Result := L.Order - R.Order;
        if Result = 0 then
          Result := CompareText(L.Name, R.Name);
      end));

    SetLength(Result, LList.Count);
    for I := 0 to LList.Count - 1 do
      Result[I] := LList[I];
  finally
    LList.Free;
    LRoot.Free;
  end;
end;

procedure TReplicateInputPanel.ClearForm;
var
  LCtrl: TControl;
begin
  for LCtrl in FBuilt do
    LCtrl.Free;
  FBuilt.Clear;
end;

procedure TReplicateInputPanel.BuildForm;
var
  LEngine: TReplicateModel;
  LInputs: TArray<TSchemaInput>;
  LInput: TSchemaInput;
  Y: Single;
  LLabel: TLabel;
  LEdit: TEdit;
  LSwitch: TSwitch;
  LTrack: TTrackBar;
  LValueLabel: TLabel;
  LCombo: TComboBox;
  LBrowse: TButton;
  LEditorWidth: Single;
  LIsFileish: Boolean;
  LEnumVal: string;

  procedure Place(AControl: TControl; AHeight: Single; AWidth: Single);
  begin
    AControl.Parent := Self;
    AControl.Position.X := CRowIndent;
    AControl.Position.Y := Y;
    AControl.Size.Width := AWidth;
    AControl.Size.Height := AHeight;
    AControl.Anchors := [TAnchorKind.akLeft, TAnchorKind.akTop, TAnchorKind.akRight];
    FBuilt.Add(AControl);
  end;

begin
  ClearForm;
  LEngine := ActiveEngine;
  if LEngine = nil then Exit;
  if LEngine.CachedSchema = '' then Exit;

  LInputs := ParseInputs(LEngine.CachedSchema);
  LEditorWidth := Width - 2 * CRowIndent;
  Y := CRowGap;

  for LInput in LInputs do
  begin
    LLabel := TLabel.Create(Self);
    LLabel.Text := LInput.Title;
    LLabel.Hint := LInput.Description;
    Place(LLabel, CLabelHeight, LEditorWidth);
    LLabel.Anchors := [TAnchorKind.akLeft, TAnchorKind.akTop];
    Y := Y + CLabelHeight + 2;

    if Length(LInput.Enum) > 0 then
    begin
      LCombo := TComboBox.Create(Self);
      for LEnumVal in LInput.Enum do
        LCombo.Items.Add(LEnumVal);
      LCombo.ItemIndex := LCombo.Items.IndexOf(LInput.Default);
      LCombo.TagString := LInput.Name;
      LCombo.Hint := LInput.Description;
      LCombo.OnChange := ComboChanged;
      Place(LCombo, CEditorHeight, LEditorWidth);
    end
    else if LInput.JType = 'boolean' then
    begin
      LSwitch := TSwitch.Create(Self);
      LSwitch.IsChecked := SameText(LInput.Default, 'true');
      LSwitch.TagString := LInput.Name;
      LSwitch.Hint := LInput.Description;
      LSwitch.OnSwitch := SwitchChanged;
      Place(LSwitch, CEditorHeight, 60);
      LSwitch.Anchors := [TAnchorKind.akLeft, TAnchorKind.akTop];
    end
    else if ((LInput.JType = 'integer') or (LInput.JType = 'number')) and
            LInput.HasMin and LInput.HasMax then
    begin
      // value readout sits right-aligned on the title row
      LValueLabel := TLabel.Create(Self);
      LValueLabel.Parent := Self;
      LValueLabel.Position.X := CRowIndent + LEditorWidth - 70;
      LValueLabel.Position.Y := Y - CLabelHeight - 2;
      LValueLabel.Size.Width := 70;
      LValueLabel.Size.Height := CLabelHeight;
      LValueLabel.TextSettings.HorzAlign := TTextAlign.Trailing;
      LValueLabel.Anchors := [TAnchorKind.akTop, TAnchorKind.akRight];
      FBuilt.Add(LValueLabel);

      LTrack := TTrackBar.Create(Self);
      LTrack.Min := LInput.Min;
      LTrack.Max := LInput.Max;
      if LInput.JType = 'integer' then
      begin
        LTrack.Frequency := 1;
        LTrack.Tag := 1;                    // integer marker for the handler
      end;
      LTrack.Value := StrToFloatDef(LInput.Default, LInput.Min);
      LTrack.TagString := LInput.Name;
      LTrack.TagObject := LValueLabel;
      LTrack.Hint := LInput.Description;
      LTrack.OnChange := NumberChanged;
      Place(LTrack, CEditorHeight, LEditorWidth);
      NumberChanged(LTrack);               // seed the readout + store default
    end
    else
    begin
      LIsFileish := SameText(LInput.Format, 'uri') or
        LInput.Name.ToLower.Contains('image') or
        LInput.Name.ToLower.Contains('file') or
        LInput.Name.ToLower.Contains('audio') or
        LInput.Name.ToLower.Contains('video');

      LEdit := TEdit.Create(Self);
      LEdit.Text := LInput.Default;
      LEdit.TagString := LInput.Name;
      LEdit.Hint := LInput.Description;
      LEdit.OnChangeTracking := EditChanged;
      if LIsFileish then
      begin
        Place(LEdit, CEditorHeight, LEditorWidth - 34);
        LBrowse := TButton.Create(Self);
        LBrowse.Text := '...';
        LBrowse.TagObject := LEdit;
        LBrowse.OnClick := BrowseClick;
        LBrowse.Parent := Self;
        LBrowse.Position.X := CRowIndent + LEditorWidth - 30;
        LBrowse.Position.Y := Y;
        LBrowse.Size.Width := 30;
        LBrowse.Size.Height := CEditorHeight;
        LBrowse.Anchors := [TAnchorKind.akTop, TAnchorKind.akRight];
        FBuilt.Add(LBrowse);
      end
      else
        Place(LEdit, CEditorHeight, LEditorWidth);
    end;

    Y := Y + CEditorHeight + CRowGap;
  end;
end;

procedure TReplicateInputPanel.WriteInput(const AName, AValue: string);
var
  LEngine: TReplicateModel;
begin
  // Deliberately no AutoRun: a half-typed prompt must not launch a prediction.
  if FNode <> nil then
    FNode.SetInputValueNoRun(AName, AValue)
  else
  begin
    LEngine := ActiveEngine;
    if LEngine <> nil then
      LEngine.SetInputValueNoRun(AName, AValue);
  end;
end;

procedure TReplicateInputPanel.EditChanged(Sender: TObject);
begin
  WriteInput(TEdit(Sender).TagString, TEdit(Sender).Text);
end;

procedure TReplicateInputPanel.SwitchChanged(Sender: TObject);
const
  CBool: array[Boolean] of string = ('false', 'true');
begin
  WriteInput(TSwitch(Sender).TagString, CBool[TSwitch(Sender).IsChecked]);
end;

procedure TReplicateInputPanel.NumberChanged(Sender: TObject);
var
  LTrack: TTrackBar;
  LText: string;
begin
  LTrack := TTrackBar(Sender);
  if LTrack.Tag = 1 then
    LText := IntToStr(Round(LTrack.Value))
  else
    LText := FormatFloat('0.##', LTrack.Value);
  if LTrack.TagObject is TLabel then
    TLabel(LTrack.TagObject).Text := LText;
  WriteInput(LTrack.TagString, LText);
end;

procedure TReplicateInputPanel.ComboChanged(Sender: TObject);
var
  LCombo: TComboBox;
begin
  LCombo := TComboBox(Sender);
  if LCombo.ItemIndex >= 0 then
    WriteInput(LCombo.TagString, LCombo.Items[LCombo.ItemIndex]);
end;

procedure TReplicateInputPanel.BrowseClick(Sender: TObject);
var
  LEdit: TEdit;
begin
  LEdit := TButton(Sender).TagObject as TEdit;
  if FOpenDialog = nil then
  begin
    FOpenDialog := TOpenDialog.Create(Self);
    FOpenDialog.Filter :=
      'Media files|*.png;*.jpg;*.jpeg;*.webp;*.gif;*.mp3;*.wav;*.mp4|All files|*.*';
  end;
  if FOpenDialog.Execute then
    LEdit.Text := FOpenDialog.FileName;   // OnChangeTracking writes it through
end;

procedure Register;
begin
  RegisterComponents('Replicate', [TReplicateInputPanel]);
end;

initialization
  RegisterClass(TReplicateInputPanel);

finalization
  UnRegisterClass(TReplicateInputPanel);

end.
