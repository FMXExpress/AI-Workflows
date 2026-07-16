unit AI.Node;

// TAICustomNode - the visual workflow-node FACE over any TAICustomEngine.
//
// The engine/face split: everything that WORKS lives
// in the engine; everything that SHOWS lives here. The node is a control, so
// it gets a LiveBindings Designer block with draggable members - the engine
// alone, being a TComponent, never would. The node:
//
//   * delegates the full bindable surface to the engine
//   * re-issues every output notification against ITSELF (bindings attach to
//     the node, not the inner engine - the delegation rule)
//   * paints a node box (model name + live status)
//   * gates the engine's AutoRun through the NODE's csDesigning (an owned
//     engine never gets the flag itself)
//
// Two wirings:
//   TReplicateNode (Replicate.Node.pas) - owns its engine via CreateEngine.
//   TAIEngineNode (below) - fronts an engine REFERENCE dropped on the form
//     (the TDataSource.DataSet idiom): point Engine at any TAICustomEngine -
//     a TReplicateModel today, a SmartCore-backed engine tomorrow - and the
//     node gives it designer presence and chaining.
//
// One face per engine: the face claims the engine's internal hooks; the
// engine's public OnStatusChanged/OnCompleted stay free for user code.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  FMX.Types,
  FMX.Controls,
  FMX.Graphics,
  System.Bindings.Helper,
  Data.Bind.Components,
  FireDAC.Comp.Client,
  AI.Engine;

type
  [ObservableMember('InputImage')]
  TAICustomNode = class(TControl)
  private
    FEngine: TAICustomEngine;
    FOwnsEngine: Boolean;
    FAutoRun: Boolean;
    FOnCompleted: TNotifyEvent;
    FOnStatusChanged: TNotifyEvent;

    procedure EngineStateChanged(Sender: TObject);
    procedure EngineCompleted(Sender: TObject);
    procedure NotifyOutputs;
    procedure ObserverToggle(const AObserver: IObserver; const AValue: Boolean);
    procedure InputChanged(const AMember: string);

    function GetModel: string;
    procedure SetModel(const AValue: string);
    function GetApiToken: string;
    procedure SetApiToken(const AValue: string);
    function GetCachedSchema: string;
    procedure SetCachedSchema(const AValue: string);
    function GetDebug: Boolean;
    procedure SetDebug(const AValue: Boolean);
    procedure SetAutoRun(const AValue: Boolean);

    function GetInputPrompt: string;
    procedure SetInputPrompt(const AValue: string);
    function GetInputImage: string;
    procedure SetInputImage(const AValue: string);
    function GetInputs: TStrings;
    procedure SetInputs(const AValue: TStrings);

    function GetOutput: string;
    function GetOutputImage: string;
    function GetOutputText: string;
    function GetOutputJSON: string;
    function GetStatus: string;
    function GetErrorMessage: string;
    function GetLogs: string;
    function GetIsRunning: Boolean;
    function GetOutputItems: TFDMemTable;
    function GetRunTrigger: Boolean;
    procedure SetRunTrigger(const AValue: Boolean);
    procedure ActivateOwnExpressions;
  protected
    // Descendants that OWN their engine return it here; return nil for the
    // reference wiring (TAIEngineNode).
    function CreateEngine: TAICustomEngine; virtual;
    procedure AttachEngine(AEngine: TAICustomEngine; AOwned: Boolean);
    procedure DetachEngine;
    procedure SyncAutoRun;

    function CanObserve(const ID: Integer): Boolean; override;
    procedure ObserverAdded(const ID: Integer; const Observer: IObserver); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Paint; override;
    procedure Loaded; override;

    function GetEngineRef: TAICustomEngine;
  public
    constructor Create(AOwner: TComponent); override;

    procedure Run;
    procedure LoadSchema;
    procedure SetInputValue(const AName, AValue: string);
    procedure SetInputValueNoRun(const AName, AValue: string);
    function GetOutputValue(const AName: string): string;

    property Engine: TAICustomEngine read FEngine;
    property IsRunning: Boolean read GetIsRunning;
    property OutputItems: TFDMemTable read GetOutputItems;
  published
    // Inputs - writable, so a chain line drawn INTO this node has a real
    // setter to land on.
    property InputPrompt: string read GetInputPrompt write SetInputPrompt;
    property InputImage: string read GetInputImage write SetInputImage;
    property Inputs: TStrings read GetInputs write SetInputs;

    // Bindable launch lever (delegated): a False->True transition calls Run.
    // Bind a TSwitch.IsChecked at it for a zero-code start button.
    property RunTrigger: Boolean read GetRunTrigger write SetRunTrigger default False;

    // Outputs - read-only; re-notified on this node when the engine reports.
    property Output: string read GetOutput;
    property OutputImage: string read GetOutputImage;
    property OutputText: string read GetOutputText;
    property OutputJSON: string read GetOutputJSON;
    property Status: string read GetStatus;
    property ErrorMessage: string read GetErrorMessage;
    property Logs: string read GetLogs;

    property ApiToken: string read GetApiToken write SetApiToken;
    property Model: string read GetModel write SetModel;
    property CachedSchema: string read GetCachedSchema write SetCachedSchema;
    property AutoRun: Boolean read FAutoRun write SetAutoRun default False;
    property Debug: Boolean read GetDebug write SetDebug default False;
    property OnCompleted: TNotifyEvent read FOnCompleted write FOnCompleted;
    property OnStatusChanged: TNotifyEvent read FOnStatusChanged write FOnStatusChanged;

    // Standard control surface so the node can be placed and sized on a form.
    property Align;
    property Anchors;
    property Enabled;
    property Height;
    property HitTest;
    property Margins;
    property Opacity;
    property Padding;
    property Position;
    property Size;
    property Visible;
    property Width;
  end;

  // A node face for an engine dropped on the form as its own component -
  // point Engine at any TAICustomEngine and wire the node in the designer.
  [ObservableMember('InputImage')]
  TAIEngineNode = class(TAICustomNode)
  private
    procedure SetEngineRef(const AValue: TAICustomEngine);
  published
    property Engine: TAICustomEngine read GetEngineRef write SetEngineRef;
  end;

procedure Register;

implementation

const
  CNodeFill: TAlphaColor = $FF2B3A55;
  CNodeBorder: TAlphaColor = $FF7FB2FF;
  CNodeText: TAlphaColor = TAlphaColorRec.White;
  CNodeStatusText: TAlphaColor = $FFB9C7E0;

{ TAICustomNode }

constructor TAICustomNode.Create(AOwner: TComponent);
var
  LEngine: TAICustomEngine;
begin
  inherited Create(AOwner);
  Width := 180;
  Height := 64;
  LEngine := CreateEngine;
  if LEngine <> nil then
    AttachEngine(LEngine, True);
end;

function TAICustomNode.CreateEngine: TAICustomEngine;
begin
  Result := nil;
end;

procedure TAICustomNode.AttachEngine(AEngine: TAICustomEngine; AOwned: Boolean);
begin
  if FEngine = AEngine then Exit;
  DetachEngine;
  FEngine := AEngine;
  FOwnsEngine := AOwned;
  if FEngine <> nil then
  begin
    if AOwned then
      FEngine.SetSubComponent(True)
    else
      FEngine.FreeNotification(Self);
    // Claim the face hooks; the engine's public events stay free for users.
    FEngine.OnInternalStateChanged := EngineStateChanged;
    FEngine.OnInternalCompleted := EngineCompleted;
    SyncAutoRun;
  end;
  Repaint;
end;

procedure TAICustomNode.DetachEngine;
begin
  if FEngine = nil then Exit;
  FEngine.OnInternalStateChanged := nil;
  FEngine.OnInternalCompleted := nil;
  if not FOwnsEngine then
    FEngine.RemoveFreeNotification(Self);
  FEngine := nil;   // owned engines are freed by component ownership
  FOwnsEngine := False;
end;

procedure TAICustomNode.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FEngine) then
  begin
    // The engine is going away - do not touch it, just forget it.
    FEngine := nil;
    FOwnsEngine := False;
  end;
end;

function TAICustomNode.CanObserve(const ID: Integer): Boolean;
begin
  Result := (ID = TObserverMapping.EditLinkID) or
            (ID = TObserverMapping.ControlValueID);
end;

procedure TAICustomNode.ObserverAdded(const ID: Integer; const Observer: IObserver);
begin
  inherited;
  if ID = TObserverMapping.EditLinkID then
    Observer.OnObserverToggle := ObserverToggle;
end;

procedure TAICustomNode.ObserverToggle(const AObserver: IObserver; const AValue: Boolean);
begin
  // Nothing to gray out: the node is an engine face, not an editor.
end;

procedure TAICustomNode.Loaded;
begin
  inherited;
  // Engine AutoRun stays off at design time - an owned engine never gets
  // csDesigning itself and would otherwise fire real predictions from
  // Object Inspector edits.
  SyncAutoRun;
  // TBindExpression.Active is public-not-published, so it cannot stream from
  // the .fmx and every hand-authored expression normally needs a FormCreate
  // activation line. The node removes that last bit of code: after loading,
  // it activates every expression that starts or ends at itself.
  if not (csDesigning in ComponentState) then
    ActivateOwnExpressions;
end;

procedure TAICustomNode.ActivateOwnExpressions;
var
  I: Integer;
  LExpr: TBindExpression;
begin
  if Owner = nil then Exit;
  for I := 0 to Owner.ComponentCount - 1 do
    if Owner.Components[I] is TBindExpression then
    begin
      LExpr := TBindExpression(Owner.Components[I]);
      if ((LExpr.SourceComponent = Self) or (LExpr.ControlComponent = Self)) and
         not LExpr.Active then
        LExpr.Active := True;
    end;
end;

procedure TAICustomNode.SyncAutoRun;
begin
  if FEngine <> nil then
    FEngine.AutoRun := FAutoRun and not (csDesigning in ComponentState);
end;

procedure TAICustomNode.SetAutoRun(const AValue: Boolean);
begin
  FAutoRun := AValue;
  SyncAutoRun;
end;

procedure TAICustomNode.EngineStateChanged(Sender: TObject);
begin
  NotifyOutputs;
  Repaint;
  if Assigned(FOnStatusChanged) then FOnStatusChanged(Self);
end;

procedure TAICustomNode.EngineCompleted(Sender: TObject);
begin
  NotifyOutputs;
  Repaint;
  if Assigned(FOnCompleted) then FOnCompleted(Self);
end;

procedure TAICustomNode.NotifyOutputs;
begin
  // Bindings attach to the NODE, so notifications must name the node - the
  // engine's own notifications go to an object nothing binds to.
  TBindings.Notify(Self, 'Output');
  TBindings.Notify(Self, 'OutputImage');
  TBindings.Notify(Self, 'OutputText');
  TBindings.Notify(Self, 'OutputJSON');
  TBindings.Notify(Self, 'Status');
  TBindings.Notify(Self, 'ErrorMessage');
  TBindings.Notify(Self, 'Logs');
end;

procedure TAICustomNode.InputChanged(const AMember: string);
begin
  TBindings.Notify(Self, AMember);
  if Observers.IsObserving(TObserverMapping.EditLinkID) then
    TLinkObservers.ControlChanged(Self);
end;

procedure TAICustomNode.Run;
begin
  if FEngine <> nil then FEngine.Run;
end;

procedure TAICustomNode.LoadSchema;
begin
  if FEngine <> nil then FEngine.LoadSchema;
end;

procedure TAICustomNode.SetInputValue(const AName, AValue: string);
begin
  if FEngine = nil then Exit;
  FEngine.SetInputValue(AName, AValue);
  if SameText(AName, 'prompt') then InputChanged('InputPrompt');
  if SameText(AName, 'image') then InputChanged('InputImage');
end;

procedure TAICustomNode.SetInputValueNoRun(const AName, AValue: string);
begin
  if FEngine = nil then Exit;
  FEngine.SetInputValueNoRun(AName, AValue);
  if SameText(AName, 'prompt') then InputChanged('InputPrompt');
  if SameText(AName, 'image') then InputChanged('InputImage');
end;

function TAICustomNode.GetOutputValue(const AName: string): string;
begin
  if FEngine <> nil then
    Result := FEngine.GetOutputValue(AName)
  else
    Result := '';
end;

{ delegation - every getter/setter guards a nil engine (reference wiring) }

function TAICustomNode.GetModel: string;
begin
  if FEngine <> nil then Result := FEngine.Model else Result := '';
end;

procedure TAICustomNode.SetModel(const AValue: string);
begin
  if FEngine = nil then Exit;
  if FEngine.Model = AValue then Exit;
  FEngine.Model := AValue;
  Repaint;
end;

function TAICustomNode.GetApiToken: string;
begin
  if FEngine <> nil then Result := FEngine.ApiToken else Result := '';
end;

procedure TAICustomNode.SetApiToken(const AValue: string);
begin
  if FEngine <> nil then FEngine.ApiToken := AValue;
end;

function TAICustomNode.GetCachedSchema: string;
begin
  if FEngine <> nil then Result := FEngine.CachedSchema else Result := '';
end;

procedure TAICustomNode.SetCachedSchema(const AValue: string);
begin
  if FEngine <> nil then FEngine.CachedSchema := AValue;
end;

function TAICustomNode.GetDebug: Boolean;
begin
  Result := (FEngine <> nil) and FEngine.Debug;
end;

procedure TAICustomNode.SetDebug(const AValue: Boolean);
begin
  if FEngine <> nil then FEngine.Debug := AValue;
end;

function TAICustomNode.GetInputPrompt: string;
begin
  if FEngine <> nil then Result := FEngine.InputPrompt else Result := '';
end;

procedure TAICustomNode.SetInputPrompt(const AValue: string);
begin
  if FEngine = nil then Exit;
  if FEngine.InputPrompt = AValue then Exit;
  FEngine.InputPrompt := AValue;
  InputChanged('InputPrompt');
end;

function TAICustomNode.GetInputImage: string;
begin
  if FEngine <> nil then Result := FEngine.InputImage else Result := '';
end;

procedure TAICustomNode.SetInputImage(const AValue: string);
begin
  if FEngine = nil then Exit;
  if FEngine.InputImage = AValue then Exit;
  FEngine.InputImage := AValue;
  InputChanged('InputImage');
end;

function TAICustomNode.GetInputs: TStrings;
begin
  if FEngine <> nil then Result := FEngine.Inputs else Result := nil;
end;

procedure TAICustomNode.SetInputs(const AValue: TStrings);
begin
  if FEngine <> nil then FEngine.Inputs := AValue;
end;

function TAICustomNode.GetOutput: string;
begin
  if FEngine <> nil then Result := FEngine.Output else Result := '';
end;

function TAICustomNode.GetOutputImage: string;
begin
  if FEngine <> nil then Result := FEngine.OutputImage else Result := '';
end;

function TAICustomNode.GetOutputText: string;
begin
  if FEngine <> nil then Result := FEngine.OutputText else Result := '';
end;

function TAICustomNode.GetOutputJSON: string;
begin
  if FEngine <> nil then Result := FEngine.OutputJSON else Result := '';
end;

function TAICustomNode.GetStatus: string;
begin
  if FEngine <> nil then Result := FEngine.Status else Result := '';
end;

function TAICustomNode.GetErrorMessage: string;
begin
  if FEngine <> nil then Result := FEngine.ErrorMessage else Result := '';
end;

function TAICustomNode.GetLogs: string;
begin
  if FEngine <> nil then Result := FEngine.Logs else Result := '';
end;

function TAICustomNode.GetIsRunning: Boolean;
begin
  Result := (FEngine <> nil) and FEngine.IsRunning;
end;

function TAICustomNode.GetOutputItems: TFDMemTable;
begin
  if FEngine <> nil then Result := FEngine.OutputItems else Result := nil;
end;

function TAICustomNode.GetRunTrigger: Boolean;
begin
  Result := (FEngine <> nil) and FEngine.RunTrigger;
end;

procedure TAICustomNode.SetRunTrigger(const AValue: Boolean);
begin
  if FEngine <> nil then FEngine.RunTrigger := AValue;
end;

procedure TAICustomNode.Paint;
var
  LRect, LTop, LBottom: TRectF;
  LTitle, LStatus: string;
begin
  LRect := LocalRect;

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := CNodeFill;
  Canvas.FillRect(LRect, 6, 6, AllCorners, AbsoluteOpacity);

  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Thickness := 1;
  Canvas.Stroke.Color := CNodeBorder;
  Canvas.DrawRect(LRect, 6, 6, AllCorners, AbsoluteOpacity);

  LTitle := Model;
  if LTitle = '' then LTitle := Name;
  if FEngine = nil then
    LStatus := 'no engine'
  else
  begin
    LStatus := Status;
    if LStatus = '' then LStatus := 'idle';
  end;

  LTop := RectF(6, 4, LRect.Width - 6, LRect.Height * 0.55);
  LBottom := RectF(6, LRect.Height * 0.55, LRect.Width - 6, LRect.Height - 4);

  Canvas.Font.Size := 12;
  Canvas.Fill.Color := CNodeText;
  Canvas.FillText(LTop, LTitle, False, AbsoluteOpacity, [],
    TTextAlign.Center, TTextAlign.Center);

  Canvas.Font.Size := 11;
  Canvas.Fill.Color := CNodeStatusText;
  Canvas.FillText(LBottom, LStatus, False, AbsoluteOpacity, [],
    TTextAlign.Center, TTextAlign.Center);
end;

function TAICustomNode.GetEngineRef: TAICustomEngine;
begin
  Result := FEngine;
end;

{ TAIEngineNode }

procedure TAIEngineNode.SetEngineRef(const AValue: TAICustomEngine);
begin
  AttachEngine(AValue, False);
end;

procedure Register;
begin
  RegisterComponents('Replicate', [TAIEngineNode]);
end;

initialization
  RegisterClass(TAIEngineNode);
  RegisterAIBindableMembers(TAIEngineNode);

finalization
  UnregisterAIBindableMembers(TAIEngineNode);
  UnRegisterClass(TAIEngineNode);

end.
