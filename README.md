# LiveBindings-Replicate

**A Delphi FMX component suite for building visual AI workflows on
[Replicate.com](https://replicate.com) — wire models together in the
LiveBindings Designer, press Run, watch the chain execute.**

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

Design-time extras: a **model picker** (searches Replicate's catalog),
**Load Model Schema** (caches the schema into the form file), **Map
Schemas...**, and an experimental **Generate Input Form** verb that emits
controls + field links onto the form.

## Quick start

**Requirements:** Delphi 12.x (Athens), FireMonkey, FireDAC (in-memory tables
only — no database), a [Replicate API token](https://replicate.com/account/api-tokens),
and internet access at runtime.

1. **Build & install the packages** (order matters):
   - Open `Packages/LiveReplicate.dproj` → *Build* (runtime).
   - Open `Packages/dclLiveReplicate.dproj` → *Build*, then *Install* (design).
   - Restart the IDE. A **Replicate** palette page appears.
2. **Set your token.** Preferred: the `REPLICATE_API_TOKEN` environment
   variable (the components and all samples fall back to it). Never commit a
   token — form files are code.
3. **Run a sample.** Start with
   [`Samples/08-Nodes`](Samples/08-Nodes) for the node workflow, or see the
   [samples index](Samples/README.md) for the full learning path.

### Your first workflow, from scratch

1. Drop two `TReplicateNode`s on an FMX form. Right-click each → **Pick
   Replicate Model...** (e.g. `black-forest-labs/flux-schnell` and an
   upscaler), then **Load Model Schema**.
2. Open the LiveBindings Designer and drag
   `NodeGen.OutputImage → NodeUpscale.InputImage`.
3. Set `NodeUpscale.AutoRun := True`.
4. In a button click: `NodeGen.SetInputValue('prompt', Edit1.Text); NodeGen.Run;`

Stage 2 launches itself when stage 1 completes. Bind `Status`, `Logs`, and
`OutputImage` to controls for live progress; use a `TReplicateRelay` between
nodes when you need to pick a specific field out of the output JSON.

## Repository layout

```
Source/     Runtime components (one unit per component)
Packages/   LiveReplicate (runtime) + dclLiveReplicate (design-time)
Samples/    Numbered learning path (superseded approaches under Samples/archive)
```

## Notes & caveats

- Written and tested against Delphi 12.x. Designer-integration behaviors are
  version-sensitive; the book marks every behavior-derived claim with the
  experiment to re-verify it.
- Predictions run on Replicate's infrastructure and **cost money** — the
  components guard against accidental design-time launches, and `AutoRun`
  only fires on non-empty inputs, but review chains before running them.
- Win32/Win64 project targets are configured; other FMX platforms should
  work but are untested.

## License

[MIT](LICENSE)