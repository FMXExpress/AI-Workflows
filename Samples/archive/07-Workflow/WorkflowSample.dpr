program WorkflowSample;

uses
  System.StartUpCopy,
  FMX.Forms,
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas',
  Replicate.Model in '..\..\Source\Replicate.Model.pas',
  UnitWorkflow in 'UnitWorkflow.pas' {FormWorkflow};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormWorkflow, FormWorkflow);
  Application.Run;
end.
