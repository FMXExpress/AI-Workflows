unit Replicate.SchemaLink;

// TReplicateSchemaLink - schema-to-schema mapping between two models.
//
// The LiveBindings Designer cannot draw JSON-field -> JSON-field lines
// between two components (per-instance members exist only as bind-source
// fields, and fields are read-only as binding targets). This component is the
// mapping surface the designer can't be: a connector holding
//
//   Mappings: TStrings of   input_name=output_path
//
// e.g.   image=output[0]
//        prompt=output.text
//        mask=output.segments[1].url
//
// On the source's successful completion it walks the source's raw output
// JSON (LastOutputJSON) with each path, writes the extracted values into the
// target's inputs WITHOUT triggering per-value auto-run, and then - once all
// mappings are applied - starts the target if its AutoRun is set. That "apply
// all, then launch once" ordering is the reason this exists as a component
// rather than N property bindings: a chain binding fires per value, and a
// stage must not launch with half its inputs applied.
//
// Source/Target accept any workflow node (TAICustomNode) or engine
// (TAICustomEngine) - Replicate or otherwise (the design-time
// "Map Schemas..." editor builds Mappings from the two cached schemas).
// The canonical single-media chain line (OutputImage -> InputImage) remains
// the right tool for the simple case; this handles the arbitrary long tail.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  AI.Engine,
  AI.Node;

// Resolves the engine behind either component kind (node -> Engine,
// engine -> itself, anything else -> nil). Shared with the design-time editor.
function EngineOf(AComponent: TComponent): TAICustomEngine;

// Walks 'output', 'output[2]', 'output.field', 'output.list[0].url' over raw
// output JSON; a leading 'output' segment means "the value itself". Returns
// '' when the path doesn't resolve. Shared with TReplicateRelay.
function ExtractJSONPath(const AOutputJSON, APath: string): string;

type
  TReplicateSchemaLink = class(TComponent)
  private
    FSource: TComponent;
    FTarget: TComponent;
    FMappings: TStringList;
    FAutoApply: Boolean;
    FSubscribed: TAICustomEngine;
    procedure SetSource(const AValue: TComponent);
    procedure SetTarget(const AValue: TComponent);
    procedure SetMappings(const AValue: TStrings);
    function GetMappings: TStrings;
    procedure Resubscribe;
    procedure SourceOutputReady(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Walk the source's current output and write mapped values into the
    // target now; launches the target afterwards if its AutoRun is set.
    // Returns how many mappings produced a value.
    function Apply: Integer;
  published
    property Source: TComponent read FSource write SetSource;
    property Target: TComponent read FTarget write SetTarget;
    property Mappings: TStrings read GetMappings write SetMappings;
    property AutoApply: Boolean read FAutoApply write FAutoApply default True;
  end;

procedure Register;

implementation

uses
  Replicate.BindSource;   // ReplicateDebugLog

function EngineOf(AComponent: TComponent): TAICustomEngine;
begin
  if AComponent is TAICustomNode then
    Result := TAICustomNode(AComponent).Engine
  else if AComponent is TAICustomEngine then
    Result := TAICustomEngine(AComponent)
  else
    Result := nil;
end;

{ TReplicateSchemaLink }

constructor TReplicateSchemaLink.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMappings := TStringList.Create;
  FAutoApply := True;
end;

destructor TReplicateSchemaLink.Destroy;
begin
  if FSubscribed <> nil then
    FSubscribed.RemoveOutputListener(SourceOutputReady);
  FMappings.Free;
  inherited;
end;

function TReplicateSchemaLink.GetMappings: TStrings;
begin
  Result := FMappings;
end;

procedure TReplicateSchemaLink.SetMappings(const AValue: TStrings);
begin
  FMappings.Assign(AValue);
end;

procedure TReplicateSchemaLink.SetSource(const AValue: TComponent);
begin
  if FSource = AValue then Exit;
  if FSource <> nil then FSource.RemoveFreeNotification(Self);
  FSource := AValue;
  if FSource <> nil then FSource.FreeNotification(Self);
  Resubscribe;
end;

procedure TReplicateSchemaLink.SetTarget(const AValue: TComponent);
begin
  if FTarget = AValue then Exit;
  if FTarget <> nil then FTarget.RemoveFreeNotification(Self);
  FTarget := AValue;
  if FTarget <> nil then FTarget.FreeNotification(Self);
end;

procedure TReplicateSchemaLink.Resubscribe;
var
  LEngine: TAICustomEngine;
begin
  LEngine := EngineOf(FSource);
  if LEngine = FSubscribed then Exit;
  if FSubscribed <> nil then
    FSubscribed.RemoveOutputListener(SourceOutputReady);
  FSubscribed := LEngine;
  if FSubscribed <> nil then
    FSubscribed.AddOutputListener(SourceOutputReady);
end;

procedure TReplicateSchemaLink.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FSource then
    begin
      FSubscribed := nil;   // engine dies with the source component
      FSource := nil;
    end;
    if AComponent = FTarget then FTarget := nil;
  end;
end;

procedure TReplicateSchemaLink.SourceOutputReady(Sender: TObject);
begin
  if FAutoApply and not (csDesigning in ComponentState) then
    Apply;
end;

function ExtractJSONPath(const AOutputJSON, APath: string): string;
var
  LRoot, LCur: TJSONValue;
  LSegments: TArray<string>;
  LSeg, LName: string;
  LIdxStart, LIdxEnd, LIdx: Integer;
begin
  Result := '';
  if (AOutputJSON = '') or (APath = '') then Exit;
  LRoot := TJSONObject.ParseJSONValue(AOutputJSON);
  if LRoot = nil then Exit;
  try
    LCur := LRoot;
    LSegments := APath.Split(['.']);
    for LSeg in LSegments do
    begin
      LName := LSeg;
      // strip and remember [n] indexers (possibly several: a[0][1])
      while True do
      begin
        LIdxStart := LName.IndexOf('[');
        if LIdxStart < 0 then
        begin
          // plain member access; the root segment 'output' means "the value"
          if not SameText(LName, 'output') and (LName <> '') then
          begin
            if LCur is TJSONObject then
              LCur := (LCur as TJSONObject).GetValue(LName)
            else
              Exit;
            if LCur = nil then Exit;
          end;
          Break;
        end;
        // member part before the first '['
        if LIdxStart > 0 then
        begin
          if not SameText(LName.Substring(0, LIdxStart), 'output') then
          begin
            if LCur is TJSONObject then
              LCur := (LCur as TJSONObject).GetValue(LName.Substring(0, LIdxStart))
            else
              Exit;
            if LCur = nil then Exit;
          end;
        end;
        LIdxEnd := LName.IndexOf(']');
        if LIdxEnd < LIdxStart then Exit;
        LIdx := StrToIntDef(LName.Substring(LIdxStart + 1, LIdxEnd - LIdxStart - 1), -1);
        if (LIdx < 0) or not (LCur is TJSONArray) then Exit;
        if LIdx >= (LCur as TJSONArray).Count then Exit;
        LCur := (LCur as TJSONArray).Items[LIdx];
        LName := LName.Substring(LIdxEnd + 1);
        if LName = '' then Break;
      end;
    end;

    if (LCur is TJSONObject) or (LCur is TJSONArray) then
      Result := LCur.ToJSON
    else if not (LCur is TJSONNull) then
      Result := LCur.Value;
  finally
    LRoot.Free;
  end;
end;

function TReplicateSchemaLink.Apply: Integer;
var
  LSrc, LTgt: TAICustomEngine;
  LJSON, LName, LPath, LValue: string;
  I: Integer;
  LTargetAutoRun: Boolean;
begin
  Result := 0;
  LSrc := EngineOf(FSource);
  LTgt := EngineOf(FTarget);
  if (LSrc = nil) or (LTgt = nil) then Exit;
  LJSON := LSrc.OutputJSON;
  if LJSON = '' then Exit;

  // Apply every mapping WITHOUT auto-run: the target must not launch with
  // half its inputs applied.
  for I := 0 to FMappings.Count - 1 do
  begin
    LName := FMappings.Names[I];
    LPath := FMappings.ValueFromIndex[I];
    if (LName = '') or (LPath = '') then Continue;
    LValue := ExtractJSONPath(LJSON, LPath);
    ReplicateDebugLog(Format('[SchemaLink] %s <- %s = "%s"',
      [LName, LPath, LValue]));
    if LValue = '' then Continue;
    if FTarget is TAICustomNode then
      TAICustomNode(FTarget).SetInputValueNoRun(LName, LValue)
    else
      LTgt.SetInputValueNoRun(LName, LValue);
    Inc(Result);
  end;

  // Then launch once, if the target is armed.
  if FTarget is TAICustomNode then
    LTargetAutoRun := TAICustomNode(FTarget).AutoRun
  else
    LTargetAutoRun := LTgt.AutoRun;
  if (Result > 0) and LTargetAutoRun and not LTgt.IsRunning and
     not (csDesigning in ComponentState) then
  begin
    if FTarget is TAICustomNode then
      TAICustomNode(FTarget).Run
    else
      LTgt.Run;
  end;
end;

procedure Register;
begin
  RegisterComponents('Replicate', [TReplicateSchemaLink]);
end;

initialization
  RegisterClass(TReplicateSchemaLink);

finalization
  UnRegisterClass(TReplicateSchemaLink);

end.
