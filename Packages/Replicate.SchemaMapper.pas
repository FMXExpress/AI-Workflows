unit Replicate.SchemaMapper;

// Design-time "Map Schemas..." dialog for TReplicateSchemaLink.
//
// Shows the SOURCE model's output schema as candidate paths (left) and the
// TARGET model's input names (right); picking one of each and clicking Add
// appends 'input=output_path' to the mapping list, which the component editor
// writes back into TReplicateSchemaLink.Mappings (and so into the .fmx).
//
// This dialog is the visual JSON->JSON mapping surface the LiveBindings
// Designer cannot be (field->field lines are impossible; see the book,
// chapters 5 and 7). VCL, built in code - the IDE is a VCL app; no .dfm.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Graphics;

type
  TfrmReplicateSchemaMapper = class(TForm)
  private
    lstOutputs: TListBox;
    lstInputs: TListBox;
    edtPath: TEdit;
    lstMappings: TListBox;
    btnAdd, btnRemove, btnOK, btnCancel: TButton;
    procedure BuildUI;
    procedure PopulateOutputs(const ASourceSchema: string);
    procedure PopulateInputs(const ATargetSchema: string);
    procedure OutputClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
  public
    class function Execute(const ASourceSchema, ATargetSchema: string;
      AMappings: TStrings): Boolean;
  end;

implementation

{ TfrmReplicateSchemaMapper }

class function TfrmReplicateSchemaMapper.Execute(const ASourceSchema,
  ATargetSchema: string; AMappings: TStrings): Boolean;
var
  LForm: TfrmReplicateSchemaMapper;
begin
  LForm := TfrmReplicateSchemaMapper.CreateNew(nil);
  try
    LForm.BuildUI;
    LForm.PopulateOutputs(ASourceSchema);
    LForm.PopulateInputs(ATargetSchema);
    LForm.lstMappings.Items.Assign(AMappings);
    Result := LForm.ShowModal = mrOk;
    if Result then
      AMappings.Assign(LForm.lstMappings.Items);
  finally
    LForm.Free;
  end;
end;

procedure TfrmReplicateSchemaMapper.BuildUI;

  function Lbl(const S: string; X, Y: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := Self;
    Result.Left := X; Result.Top := Y; Result.Caption := S;
  end;

begin
  Caption := 'Map Schemas: source output -> target input';
  Position := poScreenCenter;
  ClientWidth := 640;
  ClientHeight := 460;
  BorderStyle := bsDialog;

  Lbl('Source output paths:', 12, 8);
  lstOutputs := TListBox.Create(Self);
  lstOutputs.Parent := Self;
  lstOutputs.SetBounds(12, 28, 300, 160);
  lstOutputs.OnClick := OutputClick;

  Lbl('Target inputs:', 328, 8);
  lstInputs := TListBox.Create(Self);
  lstInputs.Parent := Self;
  lstInputs.SetBounds(328, 28, 300, 160);

  Lbl('Output path (editable):', 12, 198);
  edtPath := TEdit.Create(Self);
  edtPath.Parent := Self;
  edtPath.SetBounds(12, 218, 300, 24);
  edtPath.Text := 'output';

  btnAdd := TButton.Create(Self);
  btnAdd.Parent := Self;
  btnAdd.Caption := 'Add Mapping';
  btnAdd.SetBounds(328, 216, 140, 28);
  btnAdd.OnClick := AddClick;

  btnRemove := TButton.Create(Self);
  btnRemove.Parent := Self;
  btnRemove.Caption := 'Remove';
  btnRemove.SetBounds(478, 216, 150, 28);
  btnRemove.OnClick := RemoveClick;

  Lbl('Mappings (input=output_path):', 12, 252);
  lstMappings := TListBox.Create(Self);
  lstMappings.Parent := Self;
  lstMappings.SetBounds(12, 272, 616, 140);

  btnOK := TButton.Create(Self);
  btnOK.Parent := Self;
  btnOK.Caption := 'OK';
  btnOK.ModalResult := mrOk;
  btnOK.Default := True;
  btnOK.SetBounds(468, 422, 75, 28);

  btnCancel := TButton.Create(Self);
  btnCancel.Parent := Self;
  btnCancel.Caption := 'Cancel';
  btnCancel.ModalResult := mrCancel;
  btnCancel.Cancel := True;
  btnCancel.SetBounds(553, 422, 75, 28);
end;

procedure TfrmReplicateSchemaMapper.PopulateOutputs(const ASourceSchema: string);
var
  LRoot, LComponents, LSchemas, LOutput, LProps, LItems: TJSONObject;
  LVal: TJSONValue;
  LPair: TJSONPair;
  LType: string;
  I: Integer;
begin
  // Always offer the whole value; everything else is schema-derived sugar.
  lstOutputs.Items.Add('output');

  if ASourceSchema = '' then Exit;
  LRoot := TJSONObject.ParseJSONValue(ASourceSchema) as TJSONObject;
  if LRoot = nil then Exit;
  try
    LOutput := nil;
    LComponents := LRoot.GetValue('components') as TJSONObject;
    if LComponents <> nil then
    begin
      LSchemas := LComponents.GetValue('schemas') as TJSONObject;
      if LSchemas <> nil then
        LOutput := LSchemas.GetValue('Output') as TJSONObject;
    end;
    if LOutput = nil then Exit;

    LType := LOutput.GetValue<string>('type', '');
    if LType = 'array' then
    begin
      for I := 0 to 3 do
        lstOutputs.Items.Add(Format('output[%d]', [I]));
      LVal := LOutput.GetValue('items');
      if LVal is TJSONObject then
      begin
        LItems := LVal as TJSONObject;
        LProps := LItems.GetValue('properties') as TJSONObject;
        if LProps <> nil then
          for LPair in LProps do
            lstOutputs.Items.Add('output[0].' + LPair.JsonString.Value);
      end;
    end
    else if LType = 'object' then
    begin
      LProps := LOutput.GetValue('properties') as TJSONObject;
      if LProps <> nil then
        for LPair in LProps do
          lstOutputs.Items.Add('output.' + LPair.JsonString.Value);
    end;
  finally
    LRoot.Free;
  end;
end;

procedure TfrmReplicateSchemaMapper.PopulateInputs(const ATargetSchema: string);
var
  LRoot, LComponents, LSchemas, LInput, LProps: TJSONObject;
  LPair: TJSONPair;
begin
  if ATargetSchema = '' then Exit;
  LRoot := TJSONObject.ParseJSONValue(ATargetSchema) as TJSONObject;
  if LRoot = nil then Exit;
  try
    LInput := nil;
    LComponents := LRoot.GetValue('components') as TJSONObject;
    if LComponents <> nil then
    begin
      LSchemas := LComponents.GetValue('schemas') as TJSONObject;
      if LSchemas <> nil then
        LInput := LSchemas.GetValue('Input') as TJSONObject;
    end;
    if LInput = nil then Exit;
    LProps := LInput.GetValue('properties') as TJSONObject;
    if LProps <> nil then
      for LPair in LProps do
        lstInputs.Items.Add(LPair.JsonString.Value);
  finally
    LRoot.Free;
  end;
end;

procedure TfrmReplicateSchemaMapper.OutputClick(Sender: TObject);
begin
  if lstOutputs.ItemIndex >= 0 then
    edtPath.Text := lstOutputs.Items[lstOutputs.ItemIndex];
end;

procedure TfrmReplicateSchemaMapper.AddClick(Sender: TObject);
begin
  if (lstInputs.ItemIndex < 0) or (Trim(edtPath.Text) = '') then Exit;
  lstMappings.Items.Add(
    lstInputs.Items[lstInputs.ItemIndex] + '=' + Trim(edtPath.Text));
end;

procedure TfrmReplicateSchemaMapper.RemoveClick(Sender: TObject);
begin
  if lstMappings.ItemIndex >= 0 then
    lstMappings.Items.Delete(lstMappings.ItemIndex);
end;

end.
