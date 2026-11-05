# OneTake iOS — Project Structure, Working, and Systematic Audit

## 1. Document purpose

This document records the repository structure, application architecture, end-to-end behavior,
storage model, extension integration, validation checks, and known findings reviewed on
2026-11-06.

Repository: `IneshAg/OneTake-iOS`

Current branch checked: `ocr-column-reconstruction`

## 2. Product summary

OneTake is an iOS self-tape audition studio for iOS 18+. It takes an actor from a casting notice
through:

1. Notice import.
2. OCR/PDF/text extraction.
3. Notice and sides parsing.
4. User review and correction.
5. Line preparation and rehearsal.
6. Headshot, slate, full-length, and scene recording.
7. Take selection.
8. Deterministic tape checks.
9. Tape preview and packaging.
10. Local sharing or optional iCloud link delivery.

The normal workflow is local-first. Structured state is stored as JSON, media is stored in the
application container, and authentication is only needed for the iCloud link delivery path.

## 3. Repository layout

```text
OneTake-iOS/
├── OneTake/                 Main SwiftUI application
│   ├── Models/              Domain models, parsing, persistence, ML tokenizer/runner
│   ├── ModelViews/          State store, camera, OCR, analysis, export, accounts, reminders
│   └── Views/               SwiftUI screens, flows, components, theme, assets
├── OneTakeTests/            Unit tests
├── OneTakeShare/            Share extension
├── OneTakeWidgets/          Home/Lock Screen widgets and Live Activity
├── Shared/                  App/extension contracts and App Group storage helpers
├── dataset/                 Local OCR/parser/headshot/sides dataset
├── models/                  Local parser model and training artifacts
├── scripts/                 Dataset, parser, Core ML, and training utilities
├── docs/                    Project documentation and research
├── OneTake.xcodeproj/       Generated Xcode project
├── project.yml              XcodeGen source configuration
├── README.md                Product and setup documentation
└── .gitignore               Generated/data/model exclusions
```

## 4. Xcode targets and configuration

The Xcode project is generated from [project.yml](../project.yml). The configured targets are:

| Target | Type | Bundle identifier |
|---|---|---|
| OneTake | iOS application | `com.srmist.onetake` |
| OneTakeWidgets | Widget extension | `com.srmist.onetake.widgets` |
| OneTakeShare | Share extension | `com.srmist.onetake.share` |
| OneTakeTests | Unit-test bundle | `com.srmist.onetake.tests` |

Important project settings:

- Deployment target: iOS 18.0.
- Swift version: 5.10.
- XcodeGen is the project source of truth; do not hand-edit the generated project.
- GoogleSignIn-iOS is the only declared Swift package dependency.
- App Group: `group.com.srmist.onetake`.
- Apple Sign In is disabled in the open configuration.
- Google client identifiers are placeholders until configured.
- Camera, microphone, speech-recognition, Photos, and Live Activity usage settings are configured.

## 5. Application startup and navigation

The entry point is [OneTakeApp.swift](../OneTake/Views/OneTakeApp.swift).

At launch the app:

1. Creates the shared `AppStore`.
2. Loads persisted state.
3. Shows onboarding until `isOnboarded` is true.
4. Shows the root tab interface afterward.
5. Applies the selected appearance.
6. Validates any stored Apple account.
7. Handles `onetake://` deep links.
8. Flushes state when entering the background.
9. Refreshes widgets and Live Activities.
10. Checks the Share Inbox when returning to the foreground.

`AppStore` in [AppStore.swift](../OneTake/ModelViews/AppStore.swift) owns:

- Auditions.
- Takes.
- Practice pieces.
- Slate/profile data.
- Account state.
- Navigation paths.
- Camera flows.
- Add-audition drafts.
- Incoming Share extension data.
- Export/upload progress.

Navigation uses the `Route` enum for pushed screens. Camera work uses the separate `CameraFlow`
enum and is presented full-screen.

## 6. Core data model

The primary models are in [Models.swift](../OneTake/Models/Models.swift).

### Audition

Stores project, role, due date, requirements, scenes, submission destination, package choice,
recorded media URLs, export URLs, link state, callback information, and notes.

The normal status lifecycle is:

```text
due → ready → sent
```

An audition is ready when all required checklist pieces are complete. Optional pieces do not block
packaging.

### Piece

Checklist entries represent:

- Headshot.
- Slate.
- Full-length video.
- Scene recording.

Each piece has completion and optional/required state.

### ScriptScene and ScriptLine

Scenes contain a heading, title, estimated duration, and dialogue lines. Each line records its
character, text, and whether it belongs to the actor.

### Take

A take stores its number, duration, recording time, circled state, private notes, media URL,
audition ID, and scene index.

Only the circled take for each audition/scene is eligible for final delivery.

### PracticePiece

Standalone or audition-linked rehearsal data stores the scene, character, total actor lines,
learned-line count, and practice take count.

## 7. Persistence and media storage

[Persistence.swift](../OneTake/Models/Persistence.swift) separates structured state from media.

Structured data is saved as:

```text
Application Support/OneTake/state.json
```

Media is stored under the application Documents directory in folders such as:

```text
Documents/
├── takes/
├── headshots/
├── Exports/
├── reader-tracks/
├── audition-<uuid>/
└── practice-<uuid>/
```

The persistence layer:

- Uses Codable JSON.
- Supports older date formats.
- Decodes records lossily so one damaged record does not destroy all state.
- Preserves unreadable source state before replacement.
- Debounces normal writes.
- Flushes immediately when the app backgrounds.
- Rebases old Documents URLs after app-container relocation.

## 8. Add-audition and notice ingestion

The main import flow is in [AddAuditionFlow.swift](../OneTake/Views/AddAuditionFlow.swift).

Supported inputs:

- Clipboard text.
- Photos.
- VisionKit document scans.
- PDF files.
- Plain text.
- RTF.
- Share extension content.
- Manual entry.

### OCR and document extraction

[NoticeOCR.swift](../OneTake/ModelViews/NoticeOCR.swift) provides:

- Vision OCR.
- PDFKit text extraction.
- Scanned-PDF rasterization and OCR fallback.
- RTF extraction.
- Security-scoped file handling.
- Image normalization.
- Grayscale, contrast, and sharpening preprocessing.
- English and Hindi recognition.
- Readability checks.

[OCRLayoutReconstructor.swift](../OneTake/ModelViews/OCRLayoutReconstructor.swift) restores visual
reading order and pairs two-column key/value rows such as:

```text
Role       Lead
Deadline   25 Nov
```

into:

```text
Role: Lead
Deadline: 25 Nov
```

### Draft and review

The parser creates a `NoticeParser.Draft` before creating an `Audition`. The user can review and
correct project, role, due date, requirements, destination, and sides before committing.

The parser can identify:

- Project and project type.
- Role and candidate roles.
- Role size.
- Casting office.
- Deadline.
- Submission requirements.
- Destination and email.
- Scene count.
- Script/sides text.
- Casting notes.

## 9. Script parsing and line learning

[ScriptParser.swift](../OneTake/Models/ScriptParser.swift) supports:

- Screenplay dialogue cues.
- `CHARACTER: dialogue` format.
- `INT.`, `EXT.`, and `INT/EXT` headings.
- Scene headers.
- Multi-role casting packets.
- Commercial scripts.
- Stage-play structures.
- OCR punctuation repair.
- Parenthetical removal.
- Watermark/header filtering.
- Split contractions and hyphenated word repair.

The actor can practice using:

- Full text.
- First-letter prompts.
- Hidden lines.
- Mask and reveal.
- Audio gap.
- Audio walk.
- Reader playback.
- Speech recognition.

`SpokenLineMatcher` performs tolerant forward-only transcript matching with contraction,
number-word, filler-word, and repeated-word handling.

## 10. Camera, headshots, and recording

[CameraController.swift](../OneTake/ModelViews/CameraController.swift) manages AVFoundation:

- Camera and microphone permissions.
- Front/back camera selection.
- 1080p capture.
- Movie and photo outputs.
- Zoom.
- Orientation.
- Focus, exposure, and white balance.
- Audio level.
- Face guidance.
- Body-pose guidance.
- Hand gesture detection.
- Recording lifecycle.

The shooting flow is implemented in [ShootViews.swift](../OneTake/Views/ShootViews.swift).

The typical sequence is:

```text
Camera setup → Slate → Optional full length → Scene 1 → Scene 2 → ...
```

Supported controls include:

- Countdown.
- Pinch zoom and zoom presets.
- Hold-to-stop recording.
- Volume buttons.
- Camera Control.
- AirPods stem.
- “Action” and “Cut” voice commands.
- Voice-following prompter.
- Reader audio playback.

Headshots are stored independently through `HeadshotStore`, with front, left-profile, and
right-profile variants. Headshot images are cached to avoid repeated disk decoding during list
rendering.

## 11. Takes, tape check, preview, and export

### Takes

`AppStore` ensures:

- Take numbers are not reused.
- The first take is automatically circled.
- Only one take per audition/scene is circled.
- Foreign-audition takes are excluded.
- Replacing a take invalidates exports.
- Private notes remain private.

### Tape Check

[TapeAnalyzer.swift](../OneTake/ModelViews/TapeAnalyzer.swift) analyzes the exact clips selected by
`MediaExporter.clips`.

Video checks include:

- Face presence.
- Framing.
- Headroom.
- Centering.
- Face size/distance.
- Head turn.
- Brightness.
- Orientation.
- HD dimensions.

Audio checks include:

- Missing audio.
- Quiet audio.
- Clipping.
- Long pauses.
- Possible clipped opening.

Package checks include:

- Slate presence.
- Full-length requirements.
- Scene coverage.
- Total duration.
- Orientation.
- Resolution.
- Filename.

The analyzer caches results by file path, modification date, file size, and clip label. Optional
timing prompts are kept separate from technical findings and do not reduce the readiness score.

### Preview and MP4 export

[MediaExporter.swift](../OneTake/ModelViews/MediaExporter.swift) creates the final composition from:

1. Slate.
2. Full-length clip, if present.
3. Circled take for each scene.

It preserves clip transforms, handles mixed orientations, generates chapter metadata, and exports
an MP4.

The filename format is:

```text
LAST_FIRST_ROLE_PROJECT.mp4
```

### ZIP export

[ZipArchive.swift](../OneTake/ModelViews/ZipArchive.swift) writes a streaming, store-only ZIP
containing finalized videos and headshots. Extraction validates paths to prevent archive traversal.

## 12. Delivery and authentication

[PackageViews.swift](../OneTake/Views/PackageViews.swift) supports:

- Combined MP4.
- Separate clips ZIP.
- Headshots only.
- Complete package.

Local delivery uses the system Share Sheet for Mail, AirDrop, Files, or casting-site applications.
The app marks an audition sent only after the share action reports completion.

[CloudLink.swift](../OneTake/ModelViews/CloudLink.swift) handles optional iCloud link delivery:

```text
Sign in → Copy to iCloud → Wait for upload → Publish link → Save expiration
```

The local export remains available because iCloud receives a copy.

[AccountAuth.swift](../OneTake/ModelViews/AccountAuth.swift) supports Apple and Google providers,
but the open configuration intentionally disables Apple Sign In and uses placeholder Google
credentials.

## 13. Share extension, widgets, reminders, and Live Activity

### Share extension

[ShareViewController.swift](../OneTakeShare/ShareViewController.swift) saves shared text, URLs,
images, and PDFs into [ShareInbox.swift](../Shared/ShareInbox.swift). The main app reads the oldest
pending share when returning to the foreground.

### Widgets

[WidgetSnapshot.swift](../Shared/WidgetSnapshot.swift) stores a small App Group snapshot containing:

- Audition ID.
- Project.
- Role.
- Due date.
- Checklist status.

[NextAuditionWidget.swift](../OneTakeWidgets/NextAuditionWidget.swift) displays the nearest
upcoming audition, countdown, progress, and next piece.

### Reminders

[Reminders.swift](../OneTake/ModelViews/Reminders.swift) schedules local notifications for:

- Morning of the deadline.
- Two hours before the deadline.
- Optional daily practice.

Reminders are rebuilt when audition state changes.

### Live Activity

[AuditionActivity.swift](../Shared/AuditionActivity.swift) and
[AuditionLiveActivity.swift](../OneTakeWidgets/AuditionLiveActivity.swift) provide countdown and
upload-progress displays on the Lock Screen and Dynamic Island.

## 14. Systematic inventory performed

The repository was checked recursively, excluding `.git` internals.

### Counts

- Working files scanned: 216.
- Git-tracked files: 117.
- Top-level folders with application/source content: `.vscode`, `dataset`, `docs`, `models`,
  `OneTake`, `OneTake.xcodeproj`, `OneTakeShare`, `OneTakeTests`, `OneTakeWidgets`, `scripts`,
  and `Shared`.
- Swift files: 53.
- Python files: 16.
- Test files: 10.
- JSON files: 42.
- JSONL files: 4.
- PDFs: 3.
- JPG files: 55.
- SVG files: 5.

### Per-area file counts

| Area | Files |
|---|---:|
| OneTake | 48 |
| OneTakeTests | 10 |
| OneTakeShare | 3 |
| OneTakeWidgets | 5 |
| Shared | 6 |
| scripts | 36 |
| dataset | 71 |
| models | 27 |
| docs | 17 |

### Git and ignore state

The worktree was clean at the time of inspection. Dataset and model files are ignored through
[.gitignore](../.gitignore), including:

- `dataset/`
- `models/`
- Python caches.
- Build and Xcode-generated output.
- Core ML compiled models.

## 15. Validation results

### Passed

- No zero-byte files found.
- Raster image validation: 58 images checked, 0 failures.
- PDF/SVG/ZIP signature check: 0 failures.
- All 16 Python scripts compiled successfully with `py_compile`.
- All plist files parsed successfully.
- All entitlement files parsed successfully.
- Privacy manifest parsed successfully.
- Dataset JSON and JSONL files parsed successfully, excluding the commented example manifest.
- App Group identifiers are consistent across project configuration, entitlements, and shared code.

### Not runnable in the current Windows environment

- Swift compilation.
- Xcode build.
- iOS Simulator tests.
- Bash syntax validation.
- Full PDF page extraction using the unavailable Python `pypdf` module.

The repository documentation notes that build/test validation should be performed on macOS with
Xcode and the iOS Simulator.

## 16. Findings and known issues

### 16.1 Dataset manifests contain machine-specific absolute paths

These manifests contain paths rooted at a different local workspace:

- `dataset/notices/instagram/24x7auditionupdates/manifest.json`
- `dataset/notices/instagram/casting_updates/manifest.json`

The files exist locally by filename, but the `file` fields are not portable. Relative paths should
be preferred if these manifests will be used by another machine or CI.

### 16.2 README App Group text is outdated

[README.md](../README.md) mentions `group.com.onetake.app`, while the actual project uses
`group.com.srmist.onetake`. [CODEBASE_OVERVIEW.md](CODEBASE_OVERVIEW.md) already documents this
discrepancy.

### 16.3 iCloud capability is not provisioned

The iCloud link code exists, but the iCloud entitlement is not declared in the current open
configuration. This is documented as a paid Apple Developer provisioning requirement.

### 16.4 ML artifacts are very large

The local model directory is approximately 3.3 GB. It is ignored by Git and should remain outside
normal source distribution unless a separate model distribution strategy is introduced.

### 16.5 Generated Python cache exists

`scripts/__pycache__/` exists and is correctly ignored. It is generated output, not source.

### 16.6 Intentional duplicate files

Byte-identical duplicates were found for:

- Root/shared illustration SVGs.
- Common tokenizer files in the LoRA and merged model directories.
- Entitlement files used by multiple targets.

These appear to be intentional target/data duplication rather than corruption.

## 17. Recommended follow-up

1. Replace dataset manifest absolute paths with repository-relative paths.
2. Update the README App Group value to `group.com.srmist.onetake`.
3. Run `xcodegen generate` on macOS after any project configuration change.
4. Run the full iOS build and test workflow on macOS/Xcode.
5. Test camera, VisionKit, mixed-orientation export, iCloud provisioning, widgets, and Live Activity
   on real supported devices.
6. Keep large model artifacts out of normal Git distribution.

## 18. Parser model audit

The local parser model consists of:

- Base model: `Qwen/Qwen2.5-1.5B-Instruct`.
- LoRA adapter: `models/onetake-parser-lora/`.
- Merged model: `models/onetake-parser-merged/`.
- Training script: `scripts/train_script_parser_lora.py`.
- Merge script: `scripts/merge_lora_weights.py`.
- Local backend: `scripts/backend_parser_service.py`.
- Core ML exporter: `scripts/export_coreml_ane.py`.
- iOS runner: `OneTake/Models/CoreMLParserRunner.swift`.

The merged model contains 338 tensors and has the expected Qwen2 configuration:

- Vocabulary size: 151,936.
- Hidden size: 1,536.
- 28 transformer layers.
- 12 attention heads.
- Maximum context: 32,768 positions.
- Merged weight file size: approximately 3.09 GB.

The LoRA configuration is internally consistent with the training script:

- Rank: 16.
- Alpha: 32.
- Dropout: 0.05.
- Target modules: attention and MLP projection modules.
- Quantized training configuration: 4-bit NF4 with double quantization.

### Current dataset evidence

The parser dataset was inspected directly:

| Dataset | Rows | Notices | Sides | Prompt overlap |
|---|---:|---:|---:|---:|
| `parsing_dataset_train.jsonl` | 192 | 106 | 86 | N/A |
| `parsing_dataset_eval.jsonl` | 24 | 12 | 12 | 0 with train |

Additional observations:

- Training prompts have an average length of approximately 703 characters.
- Evaluation prompts have an average length of approximately 738 characters.
- Training sides contain 88 scenes and 382 dialogue lines.
- Evaluation sides contain 12 scenes and 58 dialogue lines.
- No duplicate prompt hashes were found within either split.
- No prompt overlap was found between the training and evaluation splits.
- All inspected rows contain valid three-message chat records.
- All assistant targets are valid JSON.

This is a useful smoke-test dataset, but it is too small to establish production reliability for
arbitrary OCR, screenplay formats, languages, casting notices, or multi-page documents.

The sides evaluation set is especially narrow: every evaluation sides sample has one scene, while
the application is intended to process multi-scene sides packets. It therefore does not measure
scene-boundary recall on realistic long packets.

### Current training limitations

The training script has several limitations:

1. It defaults to one epoch.
2. It has no validation loss or early stopping.
3. It truncates examples at 1,024 tokens even though the base model supports 32,768 positions.
4. It does not report field-level parsing metrics after training.
5. It does not compare the fine-tuned model against the base model.
6. It does not preserve a versioned training manifest containing the exact dataset hash,
   tokenizer version, base-model revision, and run configuration.
7. Its comments still describe 156 samples, while the current training file contains 192 rows.

The prompt loss masking is directionally correct because it attempts to compute loss only on the
assistant response. However, examples whose prompt consumes the full maximum length can leave little
or no supervised target after truncation. This should be measured and rejected explicitly.

### Current evaluation limitations

The existing parser benchmark in `scripts/benchmark_local_parser.py` primarily measures:

- Whether the backend responds.
- Whether its output can be decoded as JSON.
- Request latency.

It does not calculate:

- Exact-match accuracy.
- Per-field precision, recall, or F1.
- Scene-boundary precision/recall.
- Character-cue accuracy.
- Dialogue text preservation.
- Parenthetical extraction accuracy.
- Date, email, URL, destination, or requirement extraction accuracy.
- Hallucination rate.
- Performance by OCR corruption level.

Therefore, no defensible parser accuracy percentage can currently be reported. The appropriate
current conclusion is:

> The model pipeline is operationally assembled and produces a valid training/evaluation format,
> but model effectiveness is not yet demonstrated by a statistically meaningful field-level
> benchmark.

### iOS deployment finding

The iOS Core ML path is not currently connected end-to-end:

1. `CoreMLParserRunner` looks for `OneTakeParser.mlmodelc` or `OneTakeParserANE.mlmodelc/.mlpackage`.
2. The repository contains `HeadshotPoseClassifier.mlmodel`, but no parser `.mlpackage` or compiled
   parser `.mlmodelc`.
3. `project.yml` does not add a parser Core ML package to the application target.
4. The large merged PyTorch model is not directly usable by iOS.

As a result, `CoreMLParserRunner.shared.isAvailable` will normally be false in the current app
bundle and the parser will fall back to the deterministic Swift parser. The model is therefore not
currently improving notice parsing in the shipped iOS application.

### Tokenizer parity status

The repository now includes
[scripts/test_tokenizer_parity.py](../scripts/test_tokenizer_parity.py), which loads the merged
model's `vocab.json` and `merges.txt` and compares the custom byte-level BPE implementation with
the Hugging Face tokenizer. All nine representative samples passed exact token-ID comparison,
including Unicode text, JSON punctuation, screenplay formatting, parentheticals, and table-like
text.

This materially reduces the tokenizer risk, but it is not a complete deployment proof. The parity
test still needs to run against the exact tokenizer resources bundled into the iOS app, and the
test corpus should be expanded with all supported languages and long OCR prompts.

### Core ML inference efficiency risks

The current Core ML path also has performance risks:

- It recomputes the full sequence for every generated token.
- It does not use a KV cache.
- It exposes logits for the full vocabulary at every step.
- Its bracket counter is not a full JSON grammar constraint.
- Braces inside JSON string values can be counted as structural braces.
- Hard-coded token IDs for `{` are not a substitute for tokenizer-derived IDs.
- Dynamic sequence shapes may reduce ANE optimization compared with fixed supported lengths.

The exporter should be validated on macOS with `coremltools`, then compared against Python output
using identical token IDs and prompts before any performance claim is made.

## 19. Model effectiveness assessment

### What is already good

- The selected 1.5B instruct model is small enough to be practical for experimentation.
- LoRA keeps adaptation weights much smaller than the base model.
- The training/evaluation prompt split has no detected leakage.
- The data covers both casting notices and screenplay sides.
- The output schema is explicit and machine-readable.
- Deterministic parsing remains available as a fallback.
- The backend attempts local inference before external inference and deterministic fallback.
- JSON-only output and early stopping reduce common conversational output failures.

### What is not yet proven

- Correctness on unseen real casting notices.
- Correctness on multi-page and multi-scene sides.
- Robustness to OCR column ordering and character-name splits.
- Preservation of dialogue text.
- Correct date and deadline normalization.
- Correct handling of missing fields without hallucination.
- Accuracy relative to the existing deterministic Swift parser.
- On-device latency, memory usage, or battery impact.
- Actual ANE execution.

### Recommended improvement plan

#### Priority 1 — Make the deployed path correct

1. Implement a real Qwen tokenizer loader in Swift using the bundled vocabulary and merge rules, or
   use a verified tokenizer runtime that produces byte-for-byte identical token IDs.
2. Add the generated parser Core ML package to `project.yml` and the application bundle.
3. Add a Python-vs-Swift tokenizer parity test covering ASCII, Unicode, Hindi, punctuation, OCR
   artifacts, ChatML control tokens, and long prompts.
4. Add a Python-vs-Core-ML greedy decoding parity test.
5. Treat parser Core ML availability as a tested build artifact rather than an optional assumption.

#### Priority 2 — Build a real evaluation harness

Add a script that compares predictions with gold JSON and reports:

- JSON validity rate.
- Schema validity rate.
- Exact-match rate.
- Normalized string exact match.
- Per-field precision/recall/F1 for notice fields.
- Date/email/URL exact match.
- Scene count accuracy.
- Scene-boundary precision/recall.
- Character cue precision/recall.
- Dialogue text word error rate or normalized edit distance.
- Parenthetical accuracy.
- Missing-field hallucination rate.
- Latency and peak memory.

Report results separately for:

- Clean digital text.
- OCR text.
- Column-reconstructed OCR.
- Single-scene sides.
- Multi-scene sides.
- Multi-role packets.
- Notices with missing fields.
- Notices with conflicting fields.

#### Priority 3 — Improve and enlarge the dataset

Target a permission-cleared, stratified evaluation set rather than relying mainly on synthetic
examples. Include:

- At least hundreds of evaluation documents.
- Multiple independent source domains.
- Real multi-page packets.
- Multiple scenes per sides document.
- Commercial, theater, film, television, and multilingual examples.
- Different OCR noise levels.
- Rotated, low-contrast, and two-column scans.
- Ambiguous and missing metadata.
- Adversarial watermarks, page numbers, and repeated headers.

Keep evaluation data isolated from training data by source document, not only by prompt hash.

#### Priority 4 — Improve training methodology

- Add a validation split and evaluate every checkpoint.
- Compare zero-shot base, LoRA adapter, merged model, deterministic parser, and hybrid parser.
- Increase context length only after measuring memory and target-token coverage.
- Reject or separately bucket examples truncated before the assistant target.
- Use multiple seeds and report variance.
- Save dataset/model/configuration hashes with every run.
- Add schema-constrained supervised targets with consistent null/empty conventions.
- Consider separate models or adapters for notice extraction and sides extraction if task
  interference appears.

#### Priority 5 — Prefer a hybrid production architecture

The strongest likely production design is not “LLM only”:

```text
OCR/layout reconstruction
        ↓
Deterministic high-confidence extraction
        ↓
Small model fills ambiguous fields and classifies structure
        ↓
Schema validation and confidence checks
        ↓
User review for uncertain fields
```

The model should not overwrite high-confidence dates, emails, URLs, scene headings, or dialogue
text without evidence. It should return field-level confidence and provenance where possible.

## 20. Final model verdict

The model is a promising experimental parser pipeline, not yet a measured production-grade parser.

Current confidence:

- Training artifact consistency: **Good**.
- Dataset formatting and split hygiene: **Good for a smoke-test corpus**.
- Dataset scale and diversity: **Insufficient**.
- Evaluation methodology: **Insufficient for accuracy claims**.
- Backend fallback architecture: **Useful but requires stronger schema validation**.
- iOS Core ML deployment: **Not complete**.
- Swift tokenizer parity: **Promising for the tested corpus; complete app-bundle parity remains unverified**.
- Production effectiveness: **Not established**.

The highest-value next step is to fix tokenizer/model deployment parity and implement field-level
evaluation before changing model size, training duration, or quantization.

## 21. External model and runtime research

Research was performed against current Hugging Face Hub and GitHub listings on 2026-11-06.
The candidates below are alternatives or complements to the current Qwen2.5-1.5B parser. They
should be benchmarked on the OneTake evaluation corpus before adoption; download counts and
repository popularity are not evidence of extraction accuracy.

### Candidate language models

| Candidate | Source | Approx. size | License/status | OneTake fit | Recommendation |
|---|---|---:|---|---|---|
| Qwen2.5-1.5B-Instruct | [Hugging Face](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct) | 1.54B | Apache-2.0 | Current baseline; strong ecosystem and the existing fine-tuning work can be reused | Keep as baseline |
| SmolLM2-1.7B-Instruct | [Hugging Face](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct) | 1.71B | Apache-2.0 | Small, open, and has Transformers, ONNX, GGUF, and MLX ecosystem options | Highest-priority text-model comparison |
| Gemma 3 1B IT | [Hugging Face](https://huggingface.co/google/gemma-3-1b-it) | 1.0B | Gemma license; gated | Small and capable, with LiteRT and MLX conversions, but licensing and access add friction | Good technical candidate; verify legal/deployment fit |
| Llama 3.2 1B Instruct | [Hugging Face](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct) | 1.24B | Llama 3.2 license; gated | Mature tooling, multilingual coverage, GGUF and MLX conversions | Strong comparison; license review required |
| Granite 3.3 2B Instruct | [Hugging Face](https://huggingface.co/ibm-granite/granite-3.3-2b-instruct) | 2B | Apache-2.0 | More capacity and permissive licensing; available in GGUF and MLX formats | Best larger permissive text candidate |
| Phi-4-mini-instruct | [Hugging Face](https://huggingface.co/microsoft/Phi-4-mini-instruct) | 3.84B | MIT | Stronger reasoning and multilingual support, but substantially heavier for iPhone | Server/local-GPU candidate, not first on-device choice |

Notes:

- The Hugging Face listings identify SmolLM2, Qwen2.5, Granite, and Phi-4 as
  Transformers-compatible; several also have GGUF or MLX variants.
- `google/gemma-3-1b-it` and `meta-llama/Llama-3.2-1B-Instruct` are gated in the current Hub
  metadata. Access approval, redistribution terms, and App Store distribution implications must
  be checked before training or bundling.
- Models with Apache-2.0 or MIT licenses are operationally simpler, but every model card and
  dependent tokenizer must still be reviewed before commercial distribution.

### Vision and document-parsing candidates

These are not direct replacements for the current text-only parser. They are relevant when OCR
layout reconstruction is the failure point.

| Candidate | Source | Strength | Limitation for OneTake |
|---|---|---|---|
| Qwen2.5-VL-3B-Instruct | [Hugging Face](https://huggingface.co/Qwen/Qwen2.5-VL-3B-Instruct) | Image/PDF-like visual understanding and structured extraction from page images | Around 3B parameters; iOS/Core ML conversion is materially harder than text-only inference |
| olmOCR-2 7B | [Hugging Face](https://huggingface.co/allenai/olmOCR-2-7B-1025) | Specialized document OCR and layout-to-text output; Apache-2.0 metadata | Server-class size; best as an offline preprocessing service, not an iPhone bundle |
| PaddleOCR-VL 1.6 | [Hugging Face](https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.6) | OCR, layout, tables, formulas, charts, seals, and multilingual documents | Custom runtime and larger multimodal stack; requires a separate integration and license review |
| LayoutLMv3 | [Hugging Face](https://huggingface.co/microsoft/layoutlmv3-base) | Layout-aware token classification and document QA after OCR | CC-BY-NC-SA-4.0 is non-commercial; not a generative JSON parser by itself |

Recommended use of these models:

1. Keep Apple Vision/PDFKit and the deterministic layout reconstructor as the first stage.
2. Use a layout/OCR model only when the page is scanned, multi-column, rotated, or has poor OCR.
3. Pass the reconstructed text and layout metadata to a small text model for schema extraction.
4. Do not send confidential audition material to a cloud API by default.

### GitHub runtimes and implementation references

| Repository | Use in OneTake | Assessment |
|---|---|---|
| [john-rocky/CoreML-Models](https://github.com/john-rocky/CoreML-Models) | Core ML conversion patterns and ready-to-use `.mlpackage` examples | Useful reference for exporter and Swift integration; it is not itself a parser model |
| [tattn/LocalLLMClient](https://github.com/tattn/LocalLLMClient) | Swift package patterns for local LLMs across iOS/macOS/Linux, including GGUF/MLX-oriented workflows | Most directly relevant Swift integration reference; verify maintenance and iOS support at adoption time |
| [preternatural-explore/mlx-swift-chat](https://github.com/preternatural-explore/mlx-swift-chat) | MLX Swift app architecture and local model UX | Useful if the app targets Apple Silicon devices and accepts an MLX runtime |
| [SharpAI/SwiftLM](https://github.com/SharpAI/SwiftLM) | Swift/MLX local inference and OpenAI-compatible interfaces | Interesting newer option, but requires careful maturity, licensing, and device testing |
| [ibrahimcetin/MLXSampleApp](https://github.com/ibrahimcetin/MLXSampleApp) | Minimal iOS/macOS MLX Swift examples | Good prototype reference, not a production dependency without review |

These GitHub repositories are runtime or integration references, not proof that a model will run
efficiently on an iPhone. The current project should not adopt a repository solely because its
search ranking or star count is high.

### Practical ranking for OneTake

#### Tier 1: benchmark immediately

1. Current fine-tuned Qwen2.5-1.5B model.
2. SmolLM2-1.7B-Instruct with the same OneTake dataset and prompt format.
3. Granite 3.3 2B Instruct if memory and latency permit.
4. Deterministic Swift parser as the non-LLM baseline.

These can be compared using the same text input and JSON schema. The experiment should use the
same train/evaluation split, seed policy, maximum output length, temperature, and decoding method.

#### Tier 2: benchmark for device/runtime feasibility

1. Gemma 3 1B IT through a verified LiteRT/Core ML route.
2. Llama 3.2 1B through GGUF/MLX/Core ML-compatible tooling.
3. SmolLM2 1.7B through ONNX or MLX.

These are attractive only if tokenizer parity, structured output, memory, and App Store licensing
are all demonstrated.

#### Tier 3: use as preprocessing services

1. Qwen2.5-VL-3B-Instruct for page-image extraction.
2. PaddleOCR-VL for difficult multilingual/layout-heavy pages.
3. olmOCR-2 7B for server-side PDF/OCR normalization.

They are likely too large and complex for the current iOS bundle, but could improve the dataset
pipeline or a privacy-preserving Mac/local backend.

### Proposed bake-off

Create a model comparison table with one row per model and one column per metric:

- Valid JSON rate.
- Schema-valid JSON rate.
- Exact-match rate.
- Normalized field F1.
- Scene count accuracy.
- Scene-heading F1.
- Character-cue F1.
- Dialogue normalized edit distance.
- Missing-field hallucination rate.
- Median and p95 latency.
- Peak RAM/VRAM.
- Model download size and quantized bundle size.
- Tokenizer parity result.
- License and redistribution status.

The bake-off should include the current 24 examples only as a smoke test, then a new isolated test
set of at least several hundred documents. Results should be reported separately for notices,
single-scene sides, multi-scene sides, clean digital text, and OCR-corrupted text.

The first reusable evaluation harness is now available at
[scripts/evaluate_parser_models.py](../scripts/evaluate_parser_models.py). It does not load a
specific model; it evaluates any compatible endpoint:

```text
python scripts/evaluate_parser_models.py \
  --base-url http://localhost:8080 \
  --output parser-evaluation.json
```

The endpoint must expose `/api/v1/parse/notice` and `/api/v1/parse/sides`, accepting
`{"text": "..."}`. The report includes valid JSON rate, schema validity, notice field exact-match
rate, missing-field hallucinations, scene-count accuracy, heading similarity, character similarity,
dialogue similarity, and mean/median/p95 latency. The evaluation corpus is still too small for a
statistically sufficient production benchmark.

### Executed local results

The current ignored evaluation file was re-counted before the final run and contains 100 rows:
66 notices and 34 sides. The deterministic fallback endpoint was run against all 100 rows on
Windows (2026-11-06). The external proxy was intentionally unavailable, so these results measure
the fallback parser, not a neural model:

| Metric | Result |
|---|---:|
| Samples | 100 |
| Valid JSON rate | 100% |
| Schema-valid rate | 100% |
| Notice field exact-match rate | 19.1% |
| Sides scene-count accuracy | 100% |
| Sides heading similarity | 0% |
| Sides character similarity | 23.2% |
| Sides dialogue similarity | 11.8% |
| Mean latency | 2.06 s |
| Median latency | 2.06 s |
| p95 latency | 2.08 s |

The low content scores confirm that valid JSON alone is not a useful proxy for parser quality.
The approximately two-second fallback latency is also inflated by the backend attempting an
unavailable external endpoint before using its deterministic fallback. Production fallback mode
should bypass unavailable providers quickly or use a short circuit breaker.

An earlier neural smoke evaluation ran against a previous 24-row snapshot before the corpus was
expanded: it achieved 100% JSON/schema validity, 2.1% notice field exact match, 100% scene-count
accuracy, 0% heading similarity, 2.8% character similarity, 2.8% dialogue similarity, and
19.13 seconds mean latency (37.35 seconds for the first request). Those results must not be
compared numerically with the current 100-row deterministic run until the neural model is rerun
against the same current corpus.

The current merged neural model was then run against the same 100-row corpus with CUDA enabled on
an NVIDIA GeForce RTX 4050 Laptop GPU. The model loaded in 4-bit mode and reported approximately
1.2 GB allocated VRAM:

| Metric | Deterministic fallback | Qwen merged model, CUDA |
|---|---:|---:|
| Samples | 100 | 100 |
| Valid JSON rate | 100% | 100% |
| Schema-valid rate | 100% | 100% |
| Notice field exact-match rate | 19.1% | 9.3% |
| Sides scene-count accuracy | 100% | 100% |
| Sides heading similarity | 0% | 0% |
| Sides character similarity | 23.2% | 16.3% |
| Sides dialogue similarity | 11.8% | 21.0% |
| Mean latency | 2.06 s | 6.59 s |
| Median latency | 2.06 s | 6.76 s |
| p95 latency | 2.08 s | 8.15 s |

The neural model did not outperform the deterministic fallback on this corpus. It improved
dialogue similarity but reduced notice and character accuracy, while remaining slower. This
supports retaining the deterministic parser as the production baseline and using the model only
behind confidence checks until training data, prompts, and decoding are improved.

GPU acceleration clearly improved the earlier CPU experiment, but the current generation loop
still recomputes the full sequence for each token and lacks a KV cache. The measured latency is
therefore not representative of an optimized inference engine.

The original `scripts/evaluate_field_accuracy.py` was found to substitute the gold target when
the server was offline, which produced misleading perfect scores. It now delegates to the
endpoint evaluator and never fabricates predictions.

### Research conclusion

The most practical near-term choice is **not to replace Qwen immediately**. Instead:

- Keep the current Qwen model as the baseline.
- Benchmark SmolLM2-1.7B and Granite-3.3-2B as permissively licensed text alternatives.
- Test Gemma 3 1B and Llama 3.2 1B only after their license/gating constraints are accepted.
- Use Qwen2.5-VL, PaddleOCR-VL, or olmOCR as preprocessing candidates for difficult documents,
  not as direct iOS parser replacements.
- Use a verified runtime such as a reviewed Core ML, MLX Swift, LiteRT, or GGUF path rather than
  writing a custom autoregressive Core ML loop without tokenizer and generation parity.

No external model should be selected until it beats the deterministic parser and current Qwen
baseline on the same held-out OneTake test set while meeting the iOS memory, latency, privacy, and
licensing requirements.
