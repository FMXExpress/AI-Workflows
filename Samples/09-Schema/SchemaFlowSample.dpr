program SchemaFlowSample;

uses
  System.StartUpCopy,
  FMX.Forms,
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas',
  Replicate.Model in '..\..\Source\Replicate.Model.pas',
  Replicate.Node in '..\..\Source\Replicate.Node.pas',
  Replicate.InputPanel in '..\..\Source\Replicate.InputPanel.pas',
  Replicate.OutputItemsSource in '..\..\Source\Replicate.OutputItemsSource.pas',
  Replicate.SchemaLink in '..\..\Source\Replicate.SchemaLink.pas',
  UnitSchemaFlow in 'UnitSchemaFlow.pas' {FormSchemaFlow};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormSchemaFlow, FormSchemaFlow);
  Application.Run;
end.
