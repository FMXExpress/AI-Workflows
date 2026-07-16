unit Replicate.BindSource.Reg;

interface

uses
  System.Classes,
  DesignIntf,
  DesignEditors;

type
  // Adds "Pick Replicate Model..." / "Load Model Schema" verbs (right-click
  // and double-click) to the Replicate components. Works for any component
  // exposing string Model and ApiToken properties, via RTTI, so one editor
  // serves them all. For TReplicateDataBindSource it additionally offers
  // "Generate Input Form" - design-time creation of one labeled edit +
  // TLinkControlToField per Input_* field, so the whole schema appears as
  // native LiveBindings Designer lines.
  TReplicateModelEditor = class(TComponentEditor)
  private
    procedure LoadSchemaVerb;
    procedure GenerateInputForm;
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
    procedure Edit; override;
  end;

  // "Map Schemas..." on TReplicateSchemaLink: source output paths vs target
  // input names, persisted into Mappings.
  TReplicateSchemaLinkEditor = class(TComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
    procedure Edit; override;
  end;

procedure Register;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  System.Rtti,
  Data.DB,
  Data.Bind.Components,
  Vcl.Dialogs,
  FMX.StdCtrls,
  FMX.Edit,
  AI.Engine,
  AI.Node,
  Replicate.BindSource,
  Replicate.DataBindSource,
  Replicate.Model,
  Replicate.Node,
  Replicate.InputPanel,
  Replicate.OutputItemsSource,
  Replicate.SchemaLink,
  Replicate.Relay,
  Replicate.ModelPicker,
  Replicate.SchemaMapper;

{ TReplicateModelEditor }

function TReplicateModelEditor.GetVerbCount: Integer;
begin
  Result := 2;
  if Component is TReplicateDataBindSource then
    Inc(Result);
end;

function TReplicateModelEditor.GetVerb(Index: Integer): string;
begin
  case Index of
    0: Result := 'Pick Replicate Model...';
    1: Result := 'Load Model Schema';
  else
    Result := 'Generate Input Form (experimental)';
  end;
end;

procedure TReplicateModelEditor.LoadSchemaVerb;
var
  LCtx: TRttiContext;
  LMethod: TRttiMethod;
begin
  // Fetch the model's schema now, at design time: input typing and the
  // canonical prompt/image name mapping get resolved, and CachedSchema
  // streams into the form so the built app needs no pre-run fetch.
  LMethod := LCtx.GetType(Component.ClassType).GetMethod('LoadSchema');
  if LMethod = nil then Exit;
  try
    LMethod.Invoke(Component, []);
    if Designer <> nil then
      Designer.Modified;
    ShowMessage('Schema loaded for ' + GetStrProp(Component, 'Model'));
  except
    on E: Exception do
      ShowMessage('Schema load failed: ' + E.Message);
  end;
end;

procedure TReplicateModelEditor.GenerateInputForm;
var
  LSource: TReplicateDataBindSource;
  LRoot: TComponent;
  LList: TBindingsList;
  LLink: TLinkControlToField;
  LField: TField;
  LLabel, LEdit: TComponent;
  I, Y, LCount: Integer;
begin
  // EXPERIMENTAL: drives the form designer from code - creates persistent
  // FMX controls plus TLinkControlToField links, exactly as if drawn by hand.
  LSource := Component as TReplicateDataBindSource;
  if (LSource.DataSet = nil) or (LSource.DataSet.FieldCount = 0) then
  begin
    ShowMessage('No fields. Set Model (or run Load Model Schema) first.');
    Exit;
  end;
  LRoot := Designer.Root;

  LList := nil;
  for I := 0 to LRoot.ComponentCount - 1 do
    if LRoot.Components[I] is TBindingsList then
    begin
      LList := TBindingsList(LRoot.Components[I]);
      Break;
    end;
  if LList = nil then
    LList := Designer.CreateComponent(TBindingsList, LRoot, 40, 40, 24, 24)
      as TBindingsList;

  Y := 24;
  LCount := 0;
  for I := 0 to LSource.DataSet.FieldCount - 1 do
  begin
    LField := LSource.DataSet.Fields[I];
    if not LField.FieldName.StartsWith('Input_') then Continue;

    LLabel := Designer.CreateComponent(FMX.StdCtrls.TLabel, LRoot, 24, Y, 140, 18);
    (LLabel as FMX.StdCtrls.TLabel).Text := LField.FieldName.Substring(6);

    LEdit := Designer.CreateComponent(FMX.Edit.TEdit, LRoot, 170, Y, 260, 24);

    LLink := Designer.CreateComponent(TLinkControlToField, LRoot, 0, 0, 0, 0)
      as TLinkControlToField;
    // Parent the link into the bindings list so it streams as the designer
    // would write it. Property set via RTTI so a rename in some RTL version
    // degrades gracefully instead of breaking the whole design package.
    if GetPropInfo(LLink, 'BindingsList') <> nil then
      SetObjectProp(LLink, 'BindingsList', LList);
    LLink.DataSource := LSource;
    LLink.FieldName := LField.FieldName;
    LLink.Control := LEdit;
    LLink.Track := True;

    Inc(LCount);
    Inc(Y, 34);
  end;

  Designer.Modified;
  ShowMessage(Format('Generated %d input controls with field links.', [LCount]));
end;

procedure TReplicateModelEditor.ExecuteVerb(Index: Integer);
var
  LModel, LToken: string;
begin
  if GetPropInfo(Component, 'Model') = nil then Exit;

  case Index of
    1: LoadSchemaVerb;
    2: begin
         try
           GenerateInputForm;
         except
           on E: Exception do
             ShowMessage('Generate Input Form failed: ' + E.Message);
         end;
       end;
  else
    LModel := GetStrProp(Component, 'Model');
    if GetPropInfo(Component, 'ApiToken') <> nil then
      LToken := GetStrProp(Component, 'ApiToken');
    if LToken = '' then
      LToken := GetEnvironmentVariable('REPLICATE_API_TOKEN');

    if TfrmReplicateModelPicker.Execute(LModel, LToken) then
    begin
      if (LToken <> '') and (GetPropInfo(Component, 'ApiToken') <> nil) then
        SetStrProp(Component, 'ApiToken', LToken);
      SetStrProp(Component, 'Model', LModel);
      if Designer <> nil then
        Designer.Modified;
    end;
  end;
end;

procedure TReplicateModelEditor.Edit;
begin
  // Double-clicking the component opens the picker.
  ExecuteVerb(0);
end;

{ TReplicateSchemaLinkEditor }

function TReplicateSchemaLinkEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

function TReplicateSchemaLinkEditor.GetVerb(Index: Integer): string;
begin
  Result := 'Map Schemas...';
end;

procedure TReplicateSchemaLinkEditor.ExecuteVerb(Index: Integer);
var
  LLink: TReplicateSchemaLink;
  LSrc, LTgt: TAICustomEngine;
  LMappings: TStringList;

  function SchemaOf(AEngine: TAICustomEngine): string;
  begin
    Result := '';
    if AEngine = nil then Exit;
    if AEngine.CachedSchema = '' then
      try
        AEngine.LoadSchema;
      except
        on E: Exception do
          ShowMessage('Schema load failed: ' + E.Message);
      end;
    Result := AEngine.CachedSchema;
  end;

begin
  LLink := Component as TReplicateSchemaLink;
  LSrc := EngineOf(LLink.Source);
  LTgt := EngineOf(LLink.Target);
  if (LSrc = nil) or (LTgt = nil) then
  begin
    ShowMessage('Set Source and Target (a workflow node or engine) first.');
    Exit;
  end;

  LMappings := TStringList.Create;
  try
    LMappings.Assign(LLink.Mappings);
    if TfrmReplicateSchemaMapper.Execute(SchemaOf(LSrc), SchemaOf(LTgt),
      LMappings) then
    begin
      LLink.Mappings := LMappings;
      if Designer <> nil then
        Designer.Modified;
    end;
  finally
    LMappings.Free;
  end;
end;

procedure TReplicateSchemaLinkEditor.Edit;
begin
  ExecuteVerb(0);
end;

procedure Register;
begin
  RegisterComponents('Replicate',
    [TReplicateBindSource, TReplicateDataBindSource, TReplicateWorkflowLink,
     TReplicateModel, TReplicateNode,
     TReplicateInputPanel, TReplicateOutputItemsSource, TReplicateSchemaLink,
     TReplicateRelay, TAIEngineNode]);
  RegisterComponentEditor(TReplicateBindSource, TReplicateModelEditor);
  RegisterComponentEditor(TReplicateDataBindSource, TReplicateModelEditor);
  RegisterComponentEditor(TReplicateModel, TReplicateModelEditor);
  RegisterComponentEditor(TReplicateNode, TReplicateModelEditor);
  RegisterComponentEditor(TReplicateSchemaLink, TReplicateSchemaLinkEditor);
end;

end.
