program ChainDesignerSample;

uses
  System.StartUpCopy,
  FMX.Forms,
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas',
  Replicate.DataBindSource in '..\..\Source\Replicate.DataBindSource.pas',
  UnitChainDemo in 'UnitChainDemo.pas' {FormChainDemo};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormChainDemo, FormChainDemo);
  Application.Run;
end.
