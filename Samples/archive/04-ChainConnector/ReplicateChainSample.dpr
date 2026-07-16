program ReplicateChainSample;

uses
  System.StartUpCopy,
  FMX.Forms,
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas',
  Replicate.DataBindSource in '..\..\Source\Replicate.DataBindSource.pas',
  UnitMainChain in 'UnitMainChain.pas' {FormMainChain};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormMainChain, FormMainChain);
  Application.Run;
end.
