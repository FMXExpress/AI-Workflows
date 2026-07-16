program PureFlowSample;

uses
  System.StartUpCopy,
  FMX.Forms,
  AI.Engine in '..\..\Source\AI.Engine.pas',
  AI.Node in '..\..\Source\AI.Node.pas',
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas',
  Replicate.Model in '..\..\Source\Replicate.Model.pas',
  Replicate.Node in '..\..\Source\Replicate.Node.pas',
  UnitPureFlow in 'UnitPureFlow.pas' {FormPureFlow};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormPureFlow, FormPureFlow);
  Application.Run;
end.
