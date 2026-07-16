unit Replicate.Relay;

// TReplicateRelay - a visible, bindable VALVE with a JSON field picker.
//
// Replicate speaks JSON on both ends: a prediction's output is a JSON value,
// and the next model's input is a named JSON field. The relay is the coupling
// piece between them:
//
//     [anything] --> Input --(InputPath picks the JSON field)--> Output --> [anything]
//
//   * Input is a writable published property: feed it from any LiveBindings
//     line - a node's OutputJSON, a memo's Text, a REST response - via an
//     ordinary TBindExpression.
//   * InputPath chooses WHICH field of the incoming JSON travels on:
//     'output' (the whole value), 'output[0]', 'output.text',
//     'output.segments[1].url'. Empty = pass through unchanged. Non-JSON
//     input with a path simply yields '' (fail-quiet).
//   * Output is the extracted value, a read-only property refreshed via
//     TBindings.Notify - draw a line from it into the next node's InputPrompt
//     or InputImage, and that is the "channel output -> prompt" gesture.
//   * OnPass lets code transform the value in transit.
//
// Because the relay is a control, it gets a LiveBindings Designer block with
// draggable members (unlike a plain TComponent). And
// because it carries the full observer recipe, it can also sit on the CONTROL
// side of a TLinkControlToField - which is the only writable path into
// bind-source fields like TRESTRequest.Resource or a TReplicateDataBindSource
// Input_* field. Two mirrored members, one link type per leg: bind one way in,
// bind the other way out, the relay passes it on in code.

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
  Replicate.SchemaLink;   // ExtractJSONPath

type
  TReplicateRelayPassEvent = procedure(Sender: TObject; var AValue: string) of object;

  [ObservableMember('Input')]
  TReplicateRelay = class(TControl)
  private
    FInput: string;
    FOutput: string;
    FInputPath: string;
    FOnPass: TReplicateRelayPassEvent;
    procedure SetInput(const AValue: string);
    procedure SetInputPath(const AValue: string);
    procedure Pass;
    procedure ObserverToggle(const AObserver: IObserver; const AValue: Boolean);
  protected
    function CanObserve(const ID: Integer): Boolean; override;
    procedure ObserverAdded(const ID: Integer; const Observer: IObserver); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    // Inbound: any binding can write here (real setter).
    property Input: string read FInput write SetInput;

    // The JSON field picker: which part of Input travels on.
    property InputPath: string read FInputPath write SetInputPath;

    // Outbound: the extracted/mirrored value (read-only, Notify-refreshed).
    property Output: string read FOutput;

    // Transform hook, applied after extraction, before publication.
    property OnPass: TReplicateRelayPassEvent read FOnPass write FOnPass;

    // Standard control surface.
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

procedure Register;

implementation

const
  CRelayFill: TAlphaColor = $FF2E4636;
  CRelayBorder: TAlphaColor = $FF7FD79A;
  CRelayText: TAlphaColor = TAlphaColorRec.White;
  CRelayValueText: TAlphaColor = $FFBFE3C9;

{ TReplicateRelay }

constructor TReplicateRelay.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 150;
  Height := 48;
end;

function TReplicateRelay.CanObserve(const ID: Integer): Boolean;
begin
  Result := (ID = TObserverMapping.EditLinkID) or
            (ID = TObserverMapping.ControlValueID);
end;

procedure TReplicateRelay.ObserverAdded(const ID: Integer; const Observer: IObserver);
begin
  inherited;
  if ID = TObserverMapping.EditLinkID then
    Observer.OnObserverToggle := ObserverToggle;
end;

procedure TReplicateRelay.ObserverToggle(const AObserver: IObserver; const AValue: Boolean);
begin
  // Nothing to gray out.
end;

procedure TReplicateRelay.SetInput(const AValue: string);
begin
  if FInput = AValue then Exit;   // storm guard: repeated identical writes are free
  FInput := AValue;
  Pass;
end;

procedure TReplicateRelay.SetInputPath(const AValue: string);
begin
  if FInputPath = AValue then Exit;
  FInputPath := AValue;
  // Re-extract from the current input so a path edit takes effect immediately.
  if not (csLoading in ComponentState) then
    Pass;
  Repaint;
end;

procedure TReplicateRelay.Pass;
var
  LValue: string;
begin
  LValue := FInput;
  if (FInputPath <> '') and (LValue <> '') then
    LValue := ExtractJSONPath(FInput, FInputPath);   // '' when it doesn't resolve
  if Assigned(FOnPass) then
    FOnPass(Self, LValue);
  FOutput := LValue;

  // Publish to every listener kind: expressions reading Input/Output, and an
  // attached edit-link observer (field-link leg into a bind-source field).
  TBindings.Notify(Self, 'Input');
  TBindings.Notify(Self, 'Output');
  if Observers.IsObserving(TObserverMapping.EditLinkID) then
    TLinkObservers.ControlChanged(Self);
  Repaint;
end;

procedure TReplicateRelay.Paint;
var
  LRect, LTop, LBottom: TRectF;
  LTitle, LValue: string;
begin
  LRect := LocalRect;

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := CRelayFill;
  Canvas.FillRect(LRect, 6, 6, AllCorners, AbsoluteOpacity);

  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Thickness := 1;
  Canvas.Stroke.Color := CRelayBorder;
  Canvas.DrawRect(LRect, 6, 6, AllCorners, AbsoluteOpacity);

  if FInputPath <> '' then
    LTitle := '> ' + FInputPath + ' >'
  else
    LTitle := '> ' + Name + ' >';
  LValue := FOutput;
  if LValue = '' then LValue := '(empty)';
  if Length(LValue) > 40 then LValue := LValue.Substring(0, 40) + '...';

  LTop := RectF(6, 3, LRect.Width - 6, LRect.Height * 0.55);
  LBottom := RectF(6, LRect.Height * 0.55, LRect.Width - 6, LRect.Height - 3);

  Canvas.Font.Size := 12;
  Canvas.Fill.Color := CRelayText;
  Canvas.FillText(LTop, LTitle, False, AbsoluteOpacity, [],
    TTextAlign.Center, TTextAlign.Center);

  Canvas.Font.Size := 10;
  Canvas.Fill.Color := CRelayValueText;
  Canvas.FillText(LBottom, LValue, False, AbsoluteOpacity, [],
    TTextAlign.Center, TTextAlign.Center);
end;

procedure Register;
begin
  RegisterComponents('Replicate', [TReplicateRelay]);
end;

procedure RegisterBindableMembers;
const
  CMembers: array[0..2] of string = ('Input', 'InputPath', 'Output');
  CDesigners: array[0..1] of string = ('FMX', 'DFM');
var
  LMember, LDesigner: string;
begin
  for LMember in CMembers do
    for LDesigner in CDesigners do
      Data.Bind.Components.RegisterObservableMember(
        TArray<TClass>.Create(TReplicateRelay), LMember, LDesigner);
end;

initialization
  RegisterClass(TReplicateRelay);
  RegisterBindableMembers;

finalization
  Data.Bind.Components.UnregisterObservableMember(
    TArray<TClass>.Create(TReplicateRelay));
  UnRegisterClass(TReplicateRelay);

end.
