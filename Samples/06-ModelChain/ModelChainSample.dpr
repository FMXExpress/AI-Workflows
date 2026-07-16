program ModelChainSample;

uses
  System.StartUpCopy,
  FMX.Forms,
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas',
  Replicate.Model in '..\..\Source\Replicate.Model.pas',
  UnitModelChain in 'UnitModelChain.pas' {FormModelChain};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormModelChain, FormModelChain);
  Application.Run;
end.
