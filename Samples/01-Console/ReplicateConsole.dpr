program ReplicateConsole;

{$APPTYPE CONSOLE}

// Command-line harness for TReplicateBindSource. Runs a model with a prompt
// and streams the component's full debug output to the console, so the whole
// pipeline (schema fetch, request, polling, output parsing) can be verified
// without FMX or LiveBindings in the picture.
//
// Usage:
//   ReplicateConsole <owner/model[:version]> "<prompt>"
// The API token is read from the REPLICATE_API_TOKEN environment variable.

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  Replicate.BindSource in '..\..\Source\Replicate.BindSource.pas';

var
  GSource: TReplicateBindSource;
  GModel: string;
  GPrompt: string;
  GToken: string;

begin
  try
    if ParamCount < 2 then
    begin
      Writeln('Usage: ReplicateConsole <owner/model[:version]> "<prompt>"');
      Writeln('Set the REPLICATE_API_TOKEN environment variable first.');
      Writeln('Example: ReplicateConsole black-forest-labs/flux-schnell "a red bicycle"');
      ExitCode := 1;
      Exit;
    end;

    GModel := ParamStr(1);
    GPrompt := ParamStr(2);
    GToken := GetEnvironmentVariable('REPLICATE_API_TOKEN');
    if GToken = '' then
    begin
      Writeln('ERROR: REPLICATE_API_TOKEN environment variable is not set.');
      ExitCode := 1;
      Exit;
    end;

    // Stream every diagnostic line from the component to stdout.
    ReplicateDebugHook :=
      procedure(ALine: string)
      begin
        Writeln(ALine);
      end;

    GSource := TReplicateBindSource.Create(nil);
    try
      GSource.Debug := True;
      GSource.ApiToken := GToken;
      GSource.Model := GModel;

      Writeln('Loading schema for ' + GModel + ' ...');
      try
        GSource.LoadSchema;
        Writeln('Schema loaded. Version: ' + GSource.ActualVersion);
      except
        on E: Exception do
          Writeln('WARNING: schema load failed (' + E.Message + ') - ' +
                  'continuing; Run will use the model-scoped endpoint.');
      end;

      try
        GSource.SetInputValue('prompt', GPrompt);
      except
        on E: Exception do
          Writeln('WARNING: ' + E.Message + ' - running with default inputs.');
      end;

      Writeln('Starting prediction ...');
      GSource.Run;

      // The component reports progress through TThread.Queue. A console app
      // has no message loop, so those queued callbacks only execute when
      // CheckSynchronize pumps them - without this loop IsRunning would stay
      // True forever and no status/output would ever arrive.
      while GSource.IsRunning do
        CheckSynchronize(100);
      CheckSynchronize(100); // flush any final queued updates

      Writeln('');
      Writeln('Status : ' + GSource.Status);
      if GSource.ErrorMessage <> '' then
        Writeln('Error  : ' + GSource.ErrorMessage);
      Writeln('Output : ' + GSource.GetOutputValue('Output').ToString);
      Writeln('Text   : ' + GSource.GetOutputValue('text').ToString);

      if GSource.Status <> 'succeeded' then
        ExitCode := 2;
    finally
      GSource.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('FATAL: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
