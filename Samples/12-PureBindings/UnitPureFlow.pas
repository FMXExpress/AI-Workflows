unit UnitPureFlow;

// ZERO-CODE workflow - the whole pipeline is LiveBindings. This unit has NO
// event handlers, NO FormCreate, NO methods at all: every wire below lives in
// the .fmx and the components do the rest.
//
//   [NodeChat: openai/gpt-oss-20b]          writes the image prompt
//        | OutputText -> InputPrompt            (LinkChatToGen)
//   [NodeGen: flux-schnell, AutoRun]        generates the image
//        | OutputImage -> InputImage            (LinkGenToUp)
//   [NodeUpscale: crisp-upscale, AutoRun]   upscales it
//
// How each classic "that needs code" gap is closed without code:
//
//   Launching       swRun.IsChecked -> NodeChat.RunTrigger (quick binding).
//                   RunTrigger is edge-triggered: False->True calls Run.
//                   Flip the switch OFF then ON to run again.
//   Live inputs     TLinkControlToProperty pushes the token and the brief
//                   into the nodes AS YOU TYPE - it observes the control,
//                   unlike a plain TBindExpression which needs a Notify call.
//   Activation      TBindExpression.Active cannot stream from the .fmx, so
//                   TAICustomNode.Loaded activates every expression that
//                   starts or ends at the node. No FormCreate needed.
//   The instruction gpt-oss-20b has no system_prompt input, so the brief's
//                   quick binding carries a CustomFormat expression -
//                   '"instruction... " + Text' - and the instruction rides
//                   inside the prompt itself. Still zero code.
//   Images          NodeGen asks for PNG (output_format=png) and the
//                   registered UrlToFmxBitmap converter loads the output URL
//                   into TImage.Bitmap when the expression assigns it.
//
// REQUIREMENTS: a Replicate API token pasted into the top edit (there is no
// code, so nothing reads REPLICATE_API_TOKEN for you).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  System.Rtti,
  System.Bindings.Outputs,
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.Graphics,
  FMX.Dialogs,
  FMX.StdCtrls,
  FMX.Controls.Presentation,
  FMX.Edit,
  FMX.ScrollBox,
  FMX.Memo,
  FMX.Memo.Types,
  FMX.Objects,
  Data.Bind.Components,
  Data.Bind.EngExt,
  Data.Bind.Controls,
  Fmx.Bind.DBEngExt,
  Fmx.Bind.Editors,
  AI.Engine,
  AI.Node,
  Replicate.Model,
  Replicate.Node,
  Replicate.BindSource;   // registers the UrlToFmxBitmap converter

type
  TFormPureFlow = class(TForm)
    lblToken: TLabel;
    edtToken: TEdit;
    lblBrief: TLabel;
    edtBrief: TEdit;
    lblRun: TLabel;
    swRun: TSwitch;
    lblRunHint: TLabel;
    NodeChat: TReplicateNode;
    NodeGen: TReplicateNode;
    NodeUpscale: TReplicateNode;
    lblPrompt: TLabel;
    memPrompt: TMemo;
    lblErrors: TLabel;
    edtChatErr: TEdit;
    edtGenErr: TEdit;
    edtUpErr: TEdit;
    lblFinalUrl: TLabel;
    edtFinalUrl: TEdit;
    lblGen: TLabel;
    imgGen: TImage;
    lblFinal: TLabel;
    imgFinal: TImage;
    BindingsList1: TBindingsList;
    LinkTokenChat: TLinkControlToProperty;
    LinkTokenGen: TLinkControlToProperty;
    LinkTokenUp: TLinkControlToProperty;
    LinkBrief: TLinkControlToProperty;
    LinkRun: TLinkControlToProperty;
    LinkPromptOut: TBindExpression;
    LinkChatToGen: TBindExpression;
    LinkGenToUp: TBindExpression;
    LinkGenImg: TBindExpression;
    LinkUpImg: TBindExpression;
    LinkFinalUrl: TBindExpression;
    LinkChatErr: TBindExpression;
    LinkGenErr: TBindExpression;
    LinkUpErr: TBindExpression;
  end;

var
  FormPureFlow: TFormPureFlow;

implementation

{$R *.fmx}

end.
