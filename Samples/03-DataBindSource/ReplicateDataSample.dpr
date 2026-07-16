program ReplicateDataSample;

uses
  System.StartUpCopy,
  FMX.Forms,
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas',
  Replicate.DataBindSource in '..\..\Source\Replicate.DataBindSource.pas',
  UnitMainData in 'UnitMainData.pas' {FormMainData};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormMainData, FormMainData);
  Application.Run;
end.
