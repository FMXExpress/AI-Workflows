<div align="center">

# LiveBindings-Replicate

### Build visual AI workflows in Delphi FMX — wire [Replicate.com](https://replicate.com) models together in the LiveBindings Designer, press **Run**, and watch the chain execute.

[![Language: Delphi](https://img.shields.io/badge/language-Delphi%2013-E62431?logo=delphi&logoColor=white)](https://www.embarcadero.com/products/delphi)
[![Framework: FireMonkey](https://img.shields.io/badge/framework-FireMonkey%20(FMX)-6E4C9E)](https://www.embarcadero.com/products/rad-studio)
[![Platform: Windows](https://img.shields.io/badge/platform-Win32%20%7C%20Win64-0078D6?logo=windows&logoColor=white)](#quick-start)
[![Powered by Replicate](https://img.shields.io/badge/powered%20by-Replicate-000000)](https://replicate.com)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

</div>

---

Drop model nodes on a form, drag a line from one model's output to the next
model's input, and the workflow runs itself: generate an image with
`flux-schnell`, and the upscaler downstream launches automatically the moment
the URL lands in its input. Inputs are typed from each model's JSON schema,
outputs fan out to grids and images, and a JSON-aware relay picks which field
of an output travels on down the chain.

```
┌─────────────────┐      ┌──────────────────┐      ┌─────────────────────┐
│  flux-schnell   │─────▶│  > output[0] >   │─────▶│ recraft-crisp-      │
│  "a red car..." │      │  (TReplicateRelay)│      │ upscale   AutoRun   │
└─────────────────┘      └──────────────────┘      └─────────────────────┘
   TReplicateNode          JSON field picker           TReplicateNode
        └──────────── all three are LiveBindings Designer lines ───────────┘
```

## Contents

- [Why this project](#why-this-project)
- [Components](#components)
- [Quick start](#quick-start)
- [Your first workflow](#your-first-workflow-from-scratch)
- [Samples](#samples)
- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Notes & caveats](#notes--caveats)
- [License](#license)

## Why this project

- **Visual, not glue code.** Model→model chains are *drawn* in the LiveBindings
  Designer, so the topology of a workflow is visible on the form — no hidden
  event wiring.
- **Schema-driven.** Inputs are typed straight from each model's JSON schema;
  `TReplicateInputPanel` builds a full input form (switches, sliders,
  enum-aware combos, file pickers) at runtime with zero configuration.
- **Cascading execution.** Set `AutoRun` and a downstream stage launches itself
  the instant its input arrives — one node fanning into the next into the next.
- **Code-first when you want it.** Every visual capability has a plain-code
  path (`Chat.PipeTextTo(Gen).PipeImageTo(Up)`) for pipelines without bindings.
- **Mixed providers.** An optional SmartCore chat engine (OpenAI / Claude /
  Gemini / Ollama) plugs into the same nodes and chains as the Replicate models.

## Components

| Component | Kind | Purpose |
|---|---|---|
| `TReplicateNode` | control | **The workflow node.** Visual box (model name + live status) with bindable `InputPrompt`/`InputImage`/`Output*`/`OutputJSON` members. Designer-drawable node→node chains; `AutoRun` cascades stages. |
| `TReplicateRelay` | control | **The valve.** JSON in, `InputPath` (`output[0]`, `output.text`, …) picks the field, extracted value out. Couples anything to anything, including REST-component bind sources. |
| `TReplicateSchemaLink` | component | Schema→schema workflow edge: `Mappings` of `input_name=output_path`, applied atomically on completion, then launches the target. Design-time **Map Schemas...** dialog. |
| `TReplicateInputPanel` | control | Builds an input **form from the model's JSON schema** at runtime: switches, sliders, combos (enum-aware), file-browse edits — zero configuration. |
| `TReplicateOutputItemsSource` | bind source | Multi-output models normalized to rows (`ItemIndex`/`Name`/`Value`) — bind grids and list controls to a model's full output array. |
| `TReplicateDataBindSource` | bind source | Dataset-backed single-model component: per-instance schema fields, designer field links, grid-friendly. |
| `TReplicateModel` | component | The Replicate engine (REST, polling, schema mapping, notifications). Powers the node; usable standalone for code-wired pipelines. |
| `TAIEngineNode` | control | A node face for any engine dropped on the form (`Engine` reference, the `TDataSource.DataSet` idiom) — the extension point for non-Replicate providers. |
| `TSmartCoreChatEngine` | component | *Optional (RAD Studio 13+):* chat engine over Embarcadero's SmartCore AI pack (OpenAI/Claude/Gemini/Ollama drivers) — mixed-provider workflows via the same nodes and chains. Ships in the separate `LiveAISmartCore` package. |
| `TReplicateBindSource` | bind source | The original single-model bind source (kept for compatibility). |

**Design-time extras:** a **model picker** (searches Replicate's catalog),
**Load Model Schema** (caches the schema into the form file), **Map
Schemas...**, and an experimental **Generate Input Form** verb that emits
controls + field links onto the form.

## Quick start

### 1. Build & install the packages (order matters)

- Open `Packages/LiveReplicate.dproj` → **Build** (runtime).
- Open `Packages/dclLiveReplicate.dproj` → **Build**, then **Install** (design-time).
- Restart the IDE. A **Replicate** palette page appears.

### 2. Set your token

Preferred: the `REPLICATE_API_TOKEN` environment variable — the components and
all samples fall back to it.

> [!WARNING]
> Never commit a token. Form files are code, and a pasted token is saved with them.
> Get a token at [replicate.com/account/api-tokens](https://replicate.com/account/api-tokens).

### 3. Run a sample

Start with [`Samples/08-Nodes`](Samples/08-Nodes) for the node workflow, or see
the [samples index](Samples/README.md) for the full learning path.

## Your first workflow, from scratch

1. Drop two `TReplicateNode`s on an FMX form. Right-click each → **Pick
   Replicate Model...** (e.g. `black-forest-labs/flux-schnell` and an
   upscaler), then **Load Model Schema**.
2. Open the LiveBindings Designer and drag
   `NodeGen.OutputImage → NodeUpscale.InputImage`.
3. Set `NodeUpscale.AutoRun := True`.
4. In a button click:
   ```pascal
   NodeGen.SetInputValue('prompt', Edit1.Text);
   NodeGen.Run;
   ```

Stage 2 launches itself when stage 1 completes. Bind `Status`, `Logs`, and
`OutputImage` to controls for live progress; use a `TReplicateRelay` between
nodes when you need to pick a specific field out of the output JSON.

## Samples

The [`Samples/`](Samples) folder is a numbered learning path — each sample is
self-contained: open the `.dproj`, set `REPLICATE_API_TOKEN`, run.

| # | Sample | Component(s) | Demonstrates |
|---|---|---|---|
| 01 | [Console](Samples/01-Console) | `TReplicateBindSource` | The service layer with no UI and no bindings — the diagnostic harness |
| 02 | [BindSource](Samples/02-BindSource) | `TReplicateBindSource` | The original single-model FMX demo (legacy, kept for compatibility) |
| 03 | [DataBindSource](Samples/03-DataBindSource) | `TReplicateDataBindSource` | Dataset-backed bind source: per-instance schema fields, designer field links, grids |
| 06 | [ModelChain](Samples/06-ModelChain) | `TReplicateModel` | Code-wired chaining — no `.fmx` bindings, no designer; the code-first pipeline pattern |
| 08 | [Nodes](Samples/08-Nodes) | `TReplicateNode` | **The visual node workflow** — designer-drawn model→model lines with `AutoRun` cascade |
| 09 | [Schema](Samples/09-Schema) | `TReplicateInputPanel`, `TReplicateSchemaLink`, `TReplicateOutputItemsSource` | Schema-built input form, schema mapping edge, output items grid |
| 10 | [Relay](Samples/10-Relay) | `TReplicateRelay` | The JSON-field-picking valve: `OutputJSON → relay(output[0]) → InputImage` |
| 11 | [SmartFlow](Samples/11-SmartFlow) | `TSmartCoreChatEngine`, `TAIEngineNode` | **Mixed providers:** Claude writes the prompt → flux-schnell → upscaler in one cascade. *Requires RAD Studio 13+ + SmartCore.* |
| 12 | [PureBindings](Samples/12-PureBindings) | `TReplicateNode` | **Zero code.** gpt-oss-20b → flux-schnell → upscaler with an empty form unit — the whole pipeline in bindings |
| 13 | [CodeFirst](Samples/13-CodeFirst) | `TReplicateModel` | **Zero bindings.** The same pipeline wired in code: `Chat.PipeTextTo(Gen).PipeImageTo(Up)` |

Start with **08-Nodes**, then **09-Schema** and **10-Relay** — those three are
the current architecture. **12-PureBindings** is the payoff: a three-stage
pipeline with not a single event handler in the unit. Numbering gaps are
deliberate — they belong to superseded approaches, preserved under
[`Samples/archive`](Samples/archive) with notes on *why* each was outgrown.

## Repository layout

```
Source/     Runtime components (one unit per component)
Packages/   LiveReplicate (runtime) + dclLiveReplicate (design-time)
Samples/    Numbered learning path (superseded approaches under Samples/archive)
```

## Requirements

- **Delphi 13** with **FireMonkey** (also builds on Delphi 12.x Athens)
- **FireDAC** — in-memory tables only, no database
- A [Replicate API token](https://replicate.com/account/api-tokens)
- Internet access at runtime
- *For mixed-provider workflows:* the SmartCore AI pack (from GetIt) for the
  `TSmartCoreChatEngine` and the SmartFlow sample

## Notes & caveats

- Developed against **Delphi 13** and **Delphi 12.x**. Designer-integration
  behaviors are version-sensitive.
- Predictions run on Replicate's infrastructure and **cost money** — the
  components guard against accidental design-time launches, and `AutoRun` only
  fires on non-empty inputs, but review chains before running them.
- **Win32/Win64** project targets are configured; other FMX platforms should
  work but are untested.

## License

Released under the [MIT License](LICENSE) — © 2026 FMXExpress.
