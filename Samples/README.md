# Samples

Each sample is self-contained: open the `.dproj`, set `REPLICATE_API_TOKEN`
(or paste a token into the form), run.

## The learning path

| # | Sample | Component(s) | Demonstrates |
|---|---|---|---|
| 01 | [Console](01-Console) | `TReplicateBindSource` | The service layer with no UI and no bindings — the diagnostic harness |
| 02 | [BindSource](02-BindSource) | `TReplicateBindSource` | The original single-model FMX demo (legacy component, kept for compatibility) |
| 03 | [DataBindSource](03-DataBindSource) | `TReplicateDataBindSource` | Dataset-backed bind source: per-instance schema fields, designer field links, grids |
| 06 | [ModelChain](06-ModelChain) | `TReplicateModel` | Code-wired chaining — no `.fmx` bindings, no designer; the pattern for code-first pipelines |
| 08 | [Nodes](08-Nodes) | `TReplicateNode` | **The visual node workflow** — designer-drawn model→model lines with `AutoRun` cascade |
| 09 | [Schema](09-Schema) | `TReplicateInputPanel`, `TReplicateSchemaLink`, `TReplicateOutputItemsSource` | Schema-built input form, schema mapping edge, output items grid |
| 10 | [Relay](10-Relay) | `TReplicateRelay` | The JSON-field-picking valve: `OutputJSON → relay(output[0]) → InputImage` |
| 11 | [SmartFlow](11-SmartFlow) | `TSmartCoreChatEngine`, `TAIEngineNode` | **Mixed providers:** Claude (SmartCore) writes the prompt → flux-schnell → upscaler, one designer-drawn cascade. *Requires RAD Studio 13+ + SmartCore from GetIt.* |
| 12 | [PureBindings](12-PureBindings) | `TReplicateNode` | **Zero code.** gpt-oss-20b writes the prompt → flux-schnell → upscaler with an empty form unit: quick bindings push the token/brief live (instruction via `CustomFormat`), a `TSwitch` bound to `RunTrigger` launches, nodes self-activate their expressions |
| 13 | [CodeFirst](13-CodeFirst) | `TReplicateModel` | **Zero bindings.** The same pipeline as 12 wired in code, one line per wire: `Chat.PipeTextTo(Gen).PipeImageTo(Up)`, `OnDone`/`OnState` closures for display, `Ask` to launch |

Start with **08-Nodes**, then **09-Schema** and **10-Relay** — those three are
the current architecture. **12-PureBindings** is the payoff: the same
three-stage pipeline with not a single event handler in the unit. The numbering gaps are deliberate: they belong to
superseded approaches, preserved below.

## Archive

Working demos of approaches the project outgrew — kept runnable to show
*why* each one lost, not as patterns to copy:

| # | Sample | Superseded by | The lesson |
|---|---|---|---|
| 04 | [ChainConnector](archive/04-ChainConnector) | `TReplicateSchemaLink` | Event-connector chaining works but draws no designer lines — invisible topology |
| 05 | [ChainNexus](archive/05-ChainNexus) | `TReplicateRelay` | Chaining through a relay `TEdit`: visible lines, but a UI control as a data bus |
| 07 | [Workflow](archive/07-Workflow) | `TReplicateNode` (08-Nodes) | `.fmx`-wired chains between non-visual models run fine but are invisible in the LiveBindings Designer |
