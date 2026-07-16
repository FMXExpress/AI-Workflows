program CodeFirstSample;

uses
  System.StartUpCopy,
  FMX.Forms,
  AI.Engine in '..\..\Source\AI.Engine.pas',
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas',
  Replicate.Model in '..\..\Source\Replicate.Model.pas',
  UnitCodeFirst in 'UnitCodeFirst.pas' {FormCodeFirst};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormCodeFirst, FormCodeFirst);
  Application.Run;
end.
