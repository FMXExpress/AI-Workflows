program RelayFlowSample;

uses
  System.StartUpCopy,
  FMX.Forms,
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas',
  Replicate.Model in '..\..\Source\Replicate.Model.pas',
  Replicate.Node in '..\..\Source\Replicate.Node.pas',
  Replicate.SchemaLink in '..\..\Source\Replicate.SchemaLink.pas',
  Replicate.Relay in '..\..\Source\Replicate.Relay.pas',
  UnitRelayFlow in 'UnitRelayFlow.pas' {FormRelayFlow};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormRelayFlow, FormRelayFlow);
  Application.Run;
end.
