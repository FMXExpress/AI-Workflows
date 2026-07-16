program LiveReplicateSample;

uses
  System.StartUpCopy,
  FMX.Forms,
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas',
  UnitMain in 'UnitMain.pas' {FormMain};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
