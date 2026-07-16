unit AI.SmartCore.Reg;

// Design-time registration for the optional SmartCore engine package.

interface

procedure Register;

implementation

uses
  System.Classes,
  AI.SmartCore.Engine,
  AI.SmartCore.ClaudeEx;

procedure Register;
begin
  RegisterComponents('Replicate', [TSmartCoreChatEngine, TAIClaudeDriverEx]);
end;

end.
