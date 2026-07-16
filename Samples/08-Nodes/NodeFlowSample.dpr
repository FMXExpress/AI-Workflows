program NodeFlowSample;

uses
  System.StartUpCopy,
  FMX.Forms,
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas',
  Replicate.Model in '..\..\Source\Replicate.Model.pas',
  Replicate.Node in '..\..\Source\Replicate.Node.pas',
  UnitNodeFlow in 'UnitNodeFlow.pas' {FormNodeFlow};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormNodeFlow, FormNodeFlow);
  Application.Run;
end.
