program SmartFlowSample;

// Requires RAD Studio 13+ with the SmartCore AI Component Pack (GetIt).
// SmartCoreAI.* units resolve from the GetIt install's library path.

uses
  System.StartUpCopy,
  FMX.Forms,
  AI.Engine in '..\..\Source\AI.Engine.pas',
  AI.Node in '..\..\Source\AI.Node.pas',
  AI.SmartCore.Engine in '..\..\Source\AI.SmartCore.Engine.pas',
  AI.SmartCore.ClaudeEx in '..\..\Source\AI.SmartCore.ClaudeEx.pas',
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas',
  Replicate.Model in '..\..\Source\Replicate.Model.pas',
  Replicate.Node in '..\..\Source\Replicate.Node.pas',
  UnitSmartFlow in 'UnitSmartFlow.pas' {FormSmartFlow};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormSmartFlow, FormSmartFlow);
  Application.Run;
end.
