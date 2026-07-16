unit Replicate.Node;

// TReplicateNode - the Replicate workflow node: a TAICustomNode face
// (AI.Node.pas) that owns a TReplicateModel engine.
//
// Why a control? The LiveBindings Designer diagrams CONTROLS and BIND SOURCES
// only - a plain TComponent never gets a block, whatever it registers.
// As a control the node appears with its bindable members
// listed, and the designer supports property->property drags between two
// controls - so
//   NodeGen.OutputImage  ->  NodeUpscale.InputImage
// is a real, visible, designer-drawn line, and AutoRun cascades the stages.
//
// All face behavior (paint, delegation, notification re-issuing, the
// csDesigning AutoRun gate) lives in TAICustomNode; all Replicate behavior
// (REST, polling, schema mapping) lives in TReplicateModel. This class just
// marries them and adds the Replicate-specific Version property. The
// published surface is unchanged from the pre-refactor component - existing
// forms load and behave identically.

interface

uses
  System.SysUtils,
  System.Classes,
  Data.Bind.Components,
  AI.Engine,
  AI.Node,
  Replicate.Model;

type
  [ObservableMember('InputImage')]
  TReplicateNode = class(TAICustomNode)
  private
    function GetReplicateEngine: TReplicateModel;
    function GetVersion: string;
    procedure SetVersion(const AValue: string);
  protected
    function CreateEngine: TAICustomEngine; override;
  public
    // The wrapped engine, typed - everything not surfaced on the node.
    property Engine: TReplicateModel read GetReplicateEngine;
  published
    property Version: string read GetVersion write SetVersion;
  end;

procedure Register;

implementation

{ TReplicateNode }

function TReplicateNode.CreateEngine: TAICustomEngine;
begin
  Result := TReplicateModel.Create(Self);
end;

function TReplicateNode.GetReplicateEngine: TReplicateModel;
begin
  Result := TReplicateModel(GetEngineRef);
end;

function TReplicateNode.GetVersion: string;
begin
  if GetEngineRef <> nil then
    Result := GetReplicateEngine.Version
  else
    Result := '';
end;

procedure TReplicateNode.SetVersion(const AValue: string);
begin
  if GetEngineRef <> nil then
    GetReplicateEngine.Version := AValue;
end;

procedure Register;
begin
  RegisterComponents('Replicate', [TReplicateNode]);
end;

initialization
  RegisterClass(TReplicateNode);
  RegisterAIBindableMembers(TReplicateNode);

finalization
  UnregisterAIBindableMembers(TReplicateNode);
  UnRegisterClass(TReplicateNode);

end.
