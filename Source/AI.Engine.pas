unit AI.Engine;

// TAICustomEngine - the provider-agnostic base of every workflow engine.
//
// Everything the workflow layer (nodes, relays, schema links, items sources)
// consumes lives here as a contract plus the shared plumbing that is the same
// for every provider:
//
//   * canonical input storage (InputPrompt/InputImage + named inputs + the
//     static Inputs list) with the guard battery and change notifications
//   * the observable recipe (CanObserve/ObserverAdded/RegisterObservableMember
//     member names - see the book, ch. 8)
//   * output listeners (items sources, schema links) and the user events
//   * internal face hooks reserved for node controls (single face per engine)
//
// What a provider implements: Run (launch + publish state), the output/state
// getters, and optionally LoadSchema/MapInputName/SchemaChanged. The Replicate
// implementation is TReplicateModel (Replicate.Model.pas); a SmartCore-backed
// chat engine implements the same contract over TAIChatRequest.
//
// Descendants publish NOTHING extra for the shared surface - the published
// properties below are inherited, so form streaming and designer member names
// are identical across engines. Register a concrete engine class's bindable
// members with RegisterAIBindableMembers (per-class registry - ch. 5).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Bindings.Helper,
  Data.Bind.Components,
  Data.DB,
  FireDAC.Comp.Client;

type
  TAICustomEngine = class;

  // A code-first chain edge: on the source's success, push an output into
  // the target's canonical input and run it. See PipeTextTo/PipeImageTo.
  TAIPipeKind = (pkText, pkImage);

  TAIEnginePipe = record
    Kind: TAIPipeKind;
    Target: TAICustomEngine;
  end;

  [ObservableMember('InputImage')]
  TAICustomEngine = class(TComponent)
  private
    FPipes: TList<TAIEnginePipe>;
    FDoneProcs: TList<TProc<TAICustomEngine>>;
    FStateProcs: TList<TProc<TAICustomEngine>>;
    function AddPipe(AKind: TAIPipeKind; ATarget: TAICustomEngine): TAICustomEngine;
    procedure FirePipes;
    procedure ObserverToggle(const AObserver: IObserver; const AValue: Boolean);
  protected
    FModel: string;
    FApiToken: string;
    FCachedSchema: string;
    FAutoRun: Boolean;
    FDebug: Boolean;
    FRunTrigger: Boolean;

    FInputPrompt: string;
    FInputImage: string;
    FInputs: TDictionary<string, string>;    // all inputs by raw/canonical name
    FInputsList: TStringList;                // static name=value inputs

    FOutputListeners: TList<TNotifyEvent>;   // fired on success, before OnCompleted
    FOnCompleted: TNotifyEvent;
    FOnStatusChanged: TNotifyEvent;

    // Reserved for the node face (TAICustomNode) - fired BEFORE the user
    // events so bound state is re-published before user code reads it.
    FOnInternalStateChanged: TNotifyEvent;
    FOnInternalCompleted: TNotifyEvent;

    // ---- provider contract ----
    function GetStatus: string; virtual; abstract;
    function GetErrorMessage: string; virtual; abstract;
    function GetLogs: string; virtual; abstract;
    function GetOutput: string; virtual; abstract;
    function GetOutputImage: string; virtual; abstract;
    function GetOutputText: string; virtual; abstract;
    function GetOutputJSON: string; virtual; abstract;
    function GetIsRunning: Boolean; virtual; abstract;
    // Multi-output rows (ItemIndex/Name/Value); nil when a provider has none.
    function GetOutputItemsTable: TFDMemTable; virtual;
    // Canonical 'prompt'/'image' -> provider's real input name; base: identity.
    function MapInputName(const AName: string): string; virtual;
    // Called whenever CachedSchema changes (assignment or streaming).
    procedure SchemaChanged; virtual;

    // ---- shared plumbing ----
    procedure StoreInput(const AName, AValue: string; AAllowAutoRun: Boolean);
    procedure SetInputPrompt(const AValue: string);
    procedure SetInputImage(const AValue: string);
    function GetInputs: TStrings;
    procedure SetInputs(const AValue: TStrings);
    procedure SetCachedSchema(const AValue: string);
    procedure SetRunTrigger(const AValue: Boolean);
    procedure NotifyOutputs;
    procedure NotifyOutputListeners;
    procedure FireStateChanged;   // internal hook first, then OnStatusChanged
    procedure FireCompleted;      // internal hook first, then OnCompleted

    function CanObserve(const ID: Integer): Boolean; override;
    procedure ObserverAdded(const ID: Integer; const Observer: IObserver); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Launch the provider's work. Must be asynchronous; must publish state on
    // the main thread through NotifyOutputs/FireStateChanged/FireCompleted.
    procedure Run; virtual; abstract;
    // Resolve/caches provider metadata; base is a no-op.
    procedure LoadSchema; virtual;

    // ---- code-first wiring: no bindings, no designer, one line per wire ----
    // Chain stages: on THIS engine's success, its OutputText/OutputImage is
    // pushed into the target's canonical input and the target runs. Returns
    // the TARGET, so a whole pipeline reads left to right:
    //
    //   Chat.PipeTextTo(Gen).PipeImageTo(Up);
    //
    // The source's ApiToken rides down the pipe when the target has none.
    function PipeTextTo(ATarget: TAICustomEngine): TAICustomEngine;
    function PipeImageTo(ATarget: TAICustomEngine): TAICustomEngine;
    // Anonymous-procedure hooks - the closure alternative to the OnCompleted/
    // OnStatusChanged events. Fired on the main thread; return Self so they
    // stack: Engine.OnState(...).OnDone(...)
    function OnDone(AProc: TProc<TAICustomEngine>): TAICustomEngine;
    function OnState(AProc: TProc<TAICustomEngine>): TAICustomEngine;
    // Store the prompt and launch - the one-call entry point of a pipeline.
    procedure Ask(const APrompt: string);

    procedure SetInputValue(const AName, AValue: string);
    // Stores without triggering AutoRun - for bulk application (schema
    // mapping, generated forms) where the caller decides when to launch.
    procedure SetInputValueNoRun(const AName, AValue: string);
    function GetOutputValue(const AName: string): string; virtual;

    // Internal success subscription (after outputs are parsed, before
    // OnCompleted). Used by items sources and schema links.
    procedure AddOutputListener(const AListener: TNotifyEvent);
    procedure RemoveOutputListener(const AListener: TNotifyEvent);

    property IsRunning: Boolean read GetIsRunning;
    property OutputItems: TFDMemTable read GetOutputItemsTable;

    // Node-face hooks: exactly one face per engine.
    property OnInternalStateChanged: TNotifyEvent
      read FOnInternalStateChanged write FOnInternalStateChanged;
    property OnInternalCompleted: TNotifyEvent
      read FOnInternalCompleted write FOnInternalCompleted;
  published
    // Inputs - writable, so they are valid LiveBindings TARGETS. Setting one
    // (with AutoRun) launches this stage. Canonical names: MapInputName
    // translates them to the provider's real input names at serialization.
    property InputPrompt: string read FInputPrompt write SetInputPrompt;
    property InputImage: string read FInputImage write SetInputImage;

    // Static inputs as name=value lines, editable in the Object Inspector.
    // Chained/programmatic values override these on collision.
    property Inputs: TStrings read GetInputs write SetInputs;

    // Outputs - read-only, refreshed via TBindings.Notify.
    property Output: string read GetOutput;
    property OutputImage: string read GetOutputImage;
    property OutputText: string read GetOutputText;
    // The raw output value as JSON - line it into a TReplicateRelay and pick
    // the field with the relay's InputPath.
    property OutputJSON: string read GetOutputJSON;
    property Status: string read GetStatus;
    property ErrorMessage: string read GetErrorMessage;
    property Logs: string read GetLogs;

    // A bindable launch lever: flipping this False->True calls Run. Bind a
    // TSwitch.IsChecked (or any Boolean source) at it and the workflow starts
    // with ZERO event handlers. Flipping back to False just re-arms it.
    property RunTrigger: Boolean read FRunTrigger write SetRunTrigger default False;

    property ApiToken: string read FApiToken write FApiToken;
    property Model: string read FModel write FModel;
    property CachedSchema: string read FCachedSchema write SetCachedSchema;
    property AutoRun: Boolean read FAutoRun write FAutoRun default False;
    property Debug: Boolean read FDebug write FDebug default False;
    property OnCompleted: TNotifyEvent read FOnCompleted write FOnCompleted;
    property OnStatusChanged: TNotifyEvent read FOnStatusChanged write FOnStatusChanged;
  end;

// The LiveBindings Designer draws member rows only for classes registered via
// RegisterObservableMember, per CONCRETE class, under both framework designer
// IDs ('FMX' and 'DFM' - the wrong single one is a silent no-op). Call this
// for every engine/node class you ship.
procedure RegisterAIBindableMembers(const AClass: TClass);
procedure UnregisterAIBindableMembers(const AClass: TClass);

implementation

const
  CBindableMembers: array[0..9] of string = (
    'InputPrompt', 'InputImage', 'RunTrigger',
    'Output', 'OutputImage', 'OutputText', 'OutputJSON',
    'Status', 'ErrorMessage', 'Logs');
  CDesignerIDs: array[0..1] of string = ('FMX', 'DFM');

procedure RegisterAIBindableMembers(const AClass: TClass);
var
  LMember, LDesigner: string;
begin
  for LMember in CBindableMembers do
    for LDesigner in CDesignerIDs do
      Data.Bind.Components.RegisterObservableMember(
        TArray<TClass>.Create(AClass), LMember, LDesigner);
end;

procedure UnregisterAIBindableMembers(const AClass: TClass);
begin
  Data.Bind.Components.UnregisterObservableMember(TArray<TClass>.Create(AClass));
end;

{ TAICustomEngine }

constructor TAICustomEngine.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FInputs := TDictionary<string, string>.Create;
  FInputsList := TStringList.Create;
  FOutputListeners := TList<TNotifyEvent>.Create;
  FPipes := TList<TAIEnginePipe>.Create;
  FDoneProcs := TList<TProc<TAICustomEngine>>.Create;
  FStateProcs := TList<TProc<TAICustomEngine>>.Create;
end;

destructor TAICustomEngine.Destroy;
begin
  FreeAndNil(FStateProcs);
  FreeAndNil(FDoneProcs);
  FreeAndNil(FPipes);
  FOutputListeners.Free;
  FInputsList.Free;
  FInputs.Free;
  inherited;
end;

procedure TAICustomEngine.Notification(AComponent: TComponent; Operation: TOperation);
var
  I: Integer;
begin
  inherited;
  if (Operation = opRemove) and (FPipes <> nil) then
    for I := FPipes.Count - 1 downto 0 do
      if FPipes[I].Target = AComponent then
        FPipes.Delete(I);
end;

function TAICustomEngine.AddPipe(AKind: TAIPipeKind;
  ATarget: TAICustomEngine): TAICustomEngine;
var
  LPipe: TAIEnginePipe;
begin
  Result := ATarget;
  if ATarget = nil then Exit;
  LPipe.Kind := AKind;
  LPipe.Target := ATarget;
  FPipes.Add(LPipe);
  ATarget.FreeNotification(Self);
end;

function TAICustomEngine.PipeTextTo(ATarget: TAICustomEngine): TAICustomEngine;
begin
  Result := AddPipe(pkText, ATarget);
end;

function TAICustomEngine.PipeImageTo(ATarget: TAICustomEngine): TAICustomEngine;
begin
  Result := AddPipe(pkImage, ATarget);
end;

procedure TAICustomEngine.FirePipes;
var
  LPipe: TAIEnginePipe;
begin
  // Runs inside FireCompleted, i.e. on the main thread after a success.
  // Pipes launch their targets directly - the target's AutoRun setting is
  // irrelevant to a code-first chain.
  for LPipe in FPipes do
  begin
    if LPipe.Target.ApiToken = '' then
      LPipe.Target.ApiToken := FApiToken;
    case LPipe.Kind of
      pkText:  LPipe.Target.SetInputValueNoRun('prompt', OutputText);
      pkImage: LPipe.Target.SetInputValueNoRun('image', OutputImage);
    end;
    if not LPipe.Target.IsRunning then
      LPipe.Target.Run;
  end;
end;

function TAICustomEngine.OnDone(AProc: TProc<TAICustomEngine>): TAICustomEngine;
begin
  Result := Self;
  if Assigned(AProc) then FDoneProcs.Add(AProc);
end;

function TAICustomEngine.OnState(AProc: TProc<TAICustomEngine>): TAICustomEngine;
begin
  Result := Self;
  if Assigned(AProc) then FStateProcs.Add(AProc);
end;

procedure TAICustomEngine.Ask(const APrompt: string);
begin
  SetInputValueNoRun('prompt', APrompt);
  if not IsRunning then Run;
end;

function TAICustomEngine.CanObserve(const ID: Integer): Boolean;
begin
  Result := (ID = TObserverMapping.EditLinkID) or
            (ID = TObserverMapping.ControlValueID);
end;

procedure TAICustomEngine.ObserverAdded(const ID: Integer; const Observer: IObserver);
begin
  inherited;
  if ID = TObserverMapping.EditLinkID then
    Observer.OnObserverToggle := ObserverToggle;
end;

procedure TAICustomEngine.ObserverToggle(const AObserver: IObserver; const AValue: Boolean);
begin
  // Non-visual engine: nothing to gray out; the hook must exist for links.
end;

function TAICustomEngine.GetOutputItemsTable: TFDMemTable;
begin
  Result := nil;
end;

function TAICustomEngine.MapInputName(const AName: string): string;
begin
  Result := AName;
end;

procedure TAICustomEngine.SchemaChanged;
begin
  // Providers parse CachedSchema here (input typing, name mapping).
end;

procedure TAICustomEngine.LoadSchema;
begin
  // Providers fetch/refresh metadata here.
end;

procedure TAICustomEngine.SetCachedSchema(const AValue: string);
begin
  FCachedSchema := AValue;
  // A schema streamed in from the .fmx (or assigned in code) carries typing
  // and naming - let the provider parse immediately.
  SchemaChanged;
end;

procedure TAICustomEngine.SetRunTrigger(const AValue: Boolean);
var
  LRising: Boolean;
begin
  // Rising edge only: True while already True is a no-op, and False only
  // re-arms. Guarded like AutoRun - never at design time, never mid-run.
  LRising := AValue and not FRunTrigger;
  FRunTrigger := AValue;
  if LRising and not IsRunning and not (csDesigning in ComponentState) then
    Run;
end;

function TAICustomEngine.GetInputs: TStrings;
begin
  Result := FInputsList;
end;

procedure TAICustomEngine.SetInputs(const AValue: TStrings);
begin
  FInputsList.Assign(AValue);
end;

procedure TAICustomEngine.NotifyOutputs;
begin
  // Refresh every binding that reads an output property - the object-binding
  // equivalent of a dataset Post. Must run on the main thread.
  TBindings.Notify(Self, 'Output');
  TBindings.Notify(Self, 'OutputImage');
  TBindings.Notify(Self, 'OutputText');
  TBindings.Notify(Self, 'OutputJSON');
  TBindings.Notify(Self, 'Status');
  TBindings.Notify(Self, 'ErrorMessage');
  TBindings.Notify(Self, 'Logs');
end;

procedure TAICustomEngine.StoreInput(const AName, AValue: string;
  AAllowAutoRun: Boolean);
var
  LMember: string;
begin
  FInputs.AddOrSetValue(AName, AValue);
  LMember := '';
  if SameText(AName, 'prompt') then begin FInputPrompt := AValue; LMember := 'InputPrompt'; end;
  if SameText(AName, 'image') then begin FInputImage := AValue; LMember := 'InputImage'; end;

  // Changed-value notifications: bindings that READ this input re-evaluate,
  // and any attached edit-link observer is told the "control value" changed.
  if LMember <> '' then
    TBindings.Notify(Self, LMember);
  if Observers.IsObserving(TObserverMapping.EditLinkID) then
    TLinkObservers.ControlChanged(Self);

  // Auto-run only on a non-empty value: a chain binding fires on the
  // upstream's empty starting/processing states too, and we must not launch
  // prematurely. The full guard battery - see the book, ch. 12.
  if AAllowAutoRun and FAutoRun and not IsRunning and (AValue <> '') and
     not (csDesigning in ComponentState) then
    Run;
end;

procedure TAICustomEngine.SetInputPrompt(const AValue: string);
begin
  if FInputPrompt = AValue then Exit;
  StoreInput('prompt', AValue, True);
end;

procedure TAICustomEngine.SetInputImage(const AValue: string);
begin
  if FInputImage = AValue then Exit;
  StoreInput('image', AValue, True);
end;

procedure TAICustomEngine.SetInputValue(const AName, AValue: string);
begin
  StoreInput(AName, AValue, True);
end;

procedure TAICustomEngine.SetInputValueNoRun(const AName, AValue: string);
begin
  StoreInput(AName, AValue, False);
end;

function TAICustomEngine.GetOutputValue(const AName: string): string;
begin
  if SameText(AName, 'image') then Result := OutputImage
  else if SameText(AName, 'text') then Result := OutputText
  else if SameText(AName, 'status') then Result := Status
  else Result := Output;
end;

procedure TAICustomEngine.AddOutputListener(const AListener: TNotifyEvent);
begin
  FOutputListeners.Add(AListener);
end;

procedure TAICustomEngine.RemoveOutputListener(const AListener: TNotifyEvent);
begin
  FOutputListeners.Remove(AListener);
end;

procedure TAICustomEngine.NotifyOutputListeners;
var
  LListener: TNotifyEvent;
begin
  for LListener in FOutputListeners do
    if Assigned(LListener) then
      LListener(Self);
end;

procedure TAICustomEngine.FireStateChanged;
var
  LProc: TProc<TAICustomEngine>;
begin
  // Face first: the node re-publishes bound state (TBindings.Notify on
  // itself) before user handlers read it.
  if Assigned(FOnInternalStateChanged) then FOnInternalStateChanged(Self);
  for LProc in FStateProcs do LProc(Self);
  if Assigned(FOnStatusChanged) then FOnStatusChanged(Self);
end;

procedure TAICustomEngine.FireCompleted;
var
  LProc: TProc<TAICustomEngine>;
begin
  if Assigned(FOnInternalCompleted) then FOnInternalCompleted(Self);
  FirePipes;
  for LProc in FDoneProcs do LProc(Self);
  if Assigned(FOnCompleted) then FOnCompleted(Self);
end;

end.
