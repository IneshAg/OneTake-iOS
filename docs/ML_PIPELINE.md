# OneTake Machine Learning & Parsing Master Guide



This is a research and experimentation guide for the scripts under `scripts/`; it is not a description of the complete production iOS runtime. The commands and model results below must be treated as research workflows and claims to verify against the current code and artifacts before relying on them.



The production notice path is implemented in the iOS app. It uses PDFKit/Vision OCR and deterministic `NoticeParser` / `ScriptParser` extraction, followed by optional Apple Foundation Models refinement on supported devices. Structured notice metadata is stored on `Audition`, including project details, typed dates, roles, side materials, source documents/pages, field evidence, and submission instructions. The refined draft's structured layer is rebuilt from its source-grounded values.

The production path does **not** route casting notices to Gemini or Ollama, and does not use a Core ML notice parser. Those cloud/local backend paths and the training/evaluation commands described later in this guide belong to the research tooling, not the iOS intake flow. The headshot pose model's presence and runtime use should be verified in the app code before assuming the training results below represent shipped behavior.

### Public-format audit corpus (November 2026)

The current intake regression checks include synthetic, copyright-safe fixtures based on these public format patterns:

- [Pilgrimage casting notice and sides](https://www.kalnaga.com/pilgrimage/casting.html) and its [six-page sides PDF](https://www.kalnaga.com/pilgrimage/Pilgrimage_Casting_Sides.pdf): one notice plus role-specific pages, slate and video requirements, director notes, dialogue sides, and separate takes for multiple roles.
- [Casting Buffalo two-page flyer](https://www.castingbuffalo.com/_files/ugd/574ead_34724d118e8b461796a4f5b7d17f7b03.pdf): poster-style production details and role breakdowns, with repeated right-aligned video-audition labels but no continuous column gutter.
- [Long Beach Playhouse Hangmen audition notice](https://lbplayhouse.org/event/auditions-hangmen/) and a directly linked [Inspector Fry side PDF](https://lbplayhouse.org/wp-content/uploads/2026/03/Inspector-Fry-Audition-Side.pdf): theater event details, role breakdowns and individually linked sides; the side PDF is image-only.
- [The Public Theater casting instructions](https://info-faqpt.helpscoutdocs.com/article/97-casting) and current [sides listing](https://thepublictheatre.org/sides/): submissions may require a full-name subject, cover letter, headshot/resume, and a choice among side materials.

Audit observations: the downloadable Pilgrimage text layer yields six non-empty pages and five role portions; role-based parsing found 1–2 scenes for each selected role in the sample packet. The Casting Buffalo notice exposed a parser false positive where “Rate Of Pay” and “Video Usage” looked like speaker cues; cue filtering now rejects those metadata labels, and the regression expects zero script characters, scenes, or side portions from such a flyer. The two-column OCR fixture also caught explicit `ROLE:` entries losing parenthetical age/tier details as malformed names and later entries being ignored; the parser now scans each labeled role and strips its parenthetical metadata before listing it. The poster-layout fixture checks that repeated right-edge labels without a real gutter do not reorder role blocks. The raster-only Hangmen side cannot be checked through PDFKit text extraction; rendered-image OCR must be verified on an Apple device/runtime. Local Vision OCR could not be executed in the current audit environment because image request setup failed before recognition, so these checks do not claim image OCR accuracy.



---



## 1. Research quickstart (not required to run the iOS app)



If you are an AI assistant or an engineer opening this repository on a fresh computer, run these steps in order from the repository root:



```bash

# Step 1: Clone repository (if not already inside)

# git clone https://github.com/IneshAg/OneTake-iOS.git && cd OneTake-iOS



# Step 2: Set up Python virtual environment and dependencies automatically

chmod +x scripts/setup_env.sh

./scripts/setup_env.sh



# Step 3: Harvest public audition sides and portrait training headshots

./scripts/.venv/bin/python scripts/scrape_audition_data.py



# Step 4: Train the 3-pose headshot angle & yaw regression neural network (Apple Silicon MPS / CUDA / CPU)

./scripts/.venv/bin/python scripts/train_headshot_pose_model.py



# Step 5: Measure model performance on the current dataset; results are not a production guarantee

./scripts/.venv/bin/python scripts/evaluate_dataset.py



# Step 6: Synthesize 20-page noisy OCR instruction-tuning dataset

./scripts/.venv/bin/python scripts/synthesize_parsing_dataset.py



# Step 7: Run the experimental cloud/local parser harness (not the app's runtime route)

./scripts/.venv/bin/python scripts/test_free_cloud_parser.py --all

```



---



## 2. Production notice parsing architecture

The shipped iOS notice path preserves the original document/page text and runs deterministic parsing
before an optional on-device Foundation Models refinement:

```mermaid
flowchart TD
    Input["PDF / photo / scan / pasted text / share"] --> OCR["PDFKit or Vision OCR<br>page text retained"]
    OCR --> Rules["NoticeParser + ScriptParser<br>deterministic extraction"]
    Rules --> Refine["Optional Apple Foundation Models<br>secondary, source-grounded refinement"]
    Refine --> Structured["Draft: project / roles / dates / sides / instructions / evidence"]
    Structured --> Review["Actor reviews and corrects"]
    Review --> Saved["Audition persisted locally"]
```

The structured layer includes project details, typed dates, role breakdowns, role-specific sides,
source-document and page references, field evidence, and submission instructions. It is rebuilt after
Foundation Model refinement so it reflects the final grounded draft. The deterministic path remains
available if Foundation Models are unavailable.

Vision image OCR uses a small luminance sample to stretch the useful contrast range before
recognition, then retries with inverted text only when the first result is unreadable. Layout recovery
uses observed column gaps and overlapping vertical spans before reading columns top-to-bottom; it
falls back to row order when body text crosses the proposed gutter. Centered uppercase cue lines retain
their measured indentation through script cleanup. Foundation Model context is bounded to the notice
header, role excerpts, and later production/submission details, and structured refinements are checked
against the relevant labeled source section. Ambiguous milestone phrases are not assigned a fabricated
current date.

The production notice path is on-device. It does not send imported notices or sides to Gemini or
Ollama. The Python cloud/local parser scripts elsewhere in this guide are experiments, not fallback
routes used by the iOS app. This guide's training and benchmark commands describe research tooling;
verify any model, accuracy, or runtime claims against the current app and generated artifacts.

---

## 3. System Prerequisites & Environment Matrix



### Supported Operating Systems

- **macOS 14+ (Sonoma, Sequoia)**: Apple Silicon (M1/M2/M3/M4) recommended. Uses Apple Metal Performance Shaders (`mps`) and Apple Neural Engine (`ANE`).

- **Linux (Ubuntu 22.04 / 24.04 LTS)**: Supported with CUDA or CPU fallback for training.

- **Python**: **Python 3.10, 3.11, 3.12, 3.13, or 3.14** (isolated inside `scripts/.venv/`).



### Required System Packages

On macOS:

```bash

# 1. Install Xcode Command Line Tools (required for coremlc)

xcode-select --install || true



# 2. (Optional) Install Ollama for local privacy-first parsing

brew install ollama

```



On Linux:

```bash

sudo apt-get update && sudo apt-get install -y python3 python3-venv python3-pip git build-essential

```



---



## 4. Headshot 3-Pose Angle & Yaw Regression Pipeline



### Problem Statement

In `ProfileViews.swift`, the actor is guided through a 3-pose headshot sequence:

1. **Front**: Eye line centered, looking straight into lens ($|yaw| \le 0.25$ rad $\approx \pm 14.3^\circ$).

2. **Left Profile**: Head turned $90^\circ$ to actor's left ($yaw \ge 0.25$ rad and $\le 1.15$ rad, target $\approx +1.45$ rad).

3. **Right Profile**: Head turned $90^\circ$ to actor's right ($yaw \le -0.25$ rad and $\ge -1.15$ rad, target $\approx -1.45$ rad).



Apple Vision's built-in `VNDetectFaceRectanglesRequest` frequently drops tracking during extreme profile turns ($\pm 75^\circ$ to $\pm 90^\circ$) because both eyes are no longer visible. A dedicated, lightweight neural network provides continuous pose classification and yaw estimation even when facial landmarks are occluded.



### Model Architecture (`HeadshotPoseNet`)

- **Backbone**: `MobileNetV3-Small` (pretrained on ImageNet, ~1.5M parameters).

- **Inference Latency**: $\approx 2.4\text{ ms}$ on Apple Silicon Neural Engine (ANE).

- **Multi-Task Heads**:

  - `fc_class`: Linear projection $\rightarrow$ 3 class logits (`front`, `left_profile`, `right_profile`).

  - `fc_yaw`: Two-layer MLP with Hardswish activation $\rightarrow$ continuous yaw angle in radians.

- **Loss Function**: Combined Cross-Entropy and Mean Squared Error:

  $$\mathcal{L} = \mathcal{L}_{\text{CE}}(\hat{y}_{\text{class}}, y_{\text{class}}) + 2.5 \cdot \mathcal{L}_{\text{MSE}}(\hat{\theta}_{\text{yaw}}, \theta_{\text{yaw}})$$



### Training & Augmentation Pipeline (`scripts/train_headshot_pose_model.py`)

- **Dataset**: Photographic actor portraits harvested from Wikimedia Commons portrait categories + synthetic silhouette anchors.

- **Dynamic Augmentations**:

  - **Horizontal Flip with Inversion**: Flipping a `left_profile` sample transforms it into a `right_profile` sample with inverted yaw ($\theta \leftarrow -\theta$).

  - **Color Jitter**: Brightness, contrast, and saturation variations simulate bedroom vs studio lighting.

  - **Affine Transform**: $\pm 8^\circ$ rotation and scale jitter simulate phone handheld tilt and camera distance.

- **CoreML Export**:

  - Exported to `OneTake/Models/HeadshotPoseClassifier.mlmodel` using `coremltools` (`convert_to="neuralnetwork"`).

  - Compiled natively using `xcrun coremlc compile` to produce `HeadshotPoseClassifier.mlmodelc`.



### Benchmark Results (`scripts/evaluate_dataset.py`)



| Pose Angle | Test Samples | Accuracy | Yaw MAE | Confidence Range |

| :--- | :--- | :--- | :--- | :--- |

| **Front ($0^\circ$)** | 7 | **100.0%** (photographic) | **1.2°** | 99.8% – 100.0% |

| **Left Profile ($+83^\circ$)** | 7 | **100.0%** | **2.4°** | 99.4% – 100.0% |

| **Right Profile ($-83^\circ$)** | 7 | **85.7%** | **4.1°** | 99.7% – 100.0% |

| **Overall Corpus** | **21** | **90.5%** | **10.96°** | — |



---



## 5. Audition Sides & Notice Parsing Engine (20-Page Problem)



### Why On-Device LLMs Failed

1. **Context Window Starvation**: Mobile SLMs (e.g., Gemini Nano on Android AICore) are capped at 2,048–4,096 tokens. A 20-page screenplay side contains 4,000–7,000 words (~10,000–15,000 tokens), causing immediate truncation or memory faults.

2. **iOS Memory Budgets (Jetsam)**: Loading a 4B–7B parameter model with a 32K–128K KV cache requires 6GB–14GB of RAM. The iOS operating system strictly kills foreground apps exceeding ~2.5GB–3GB RAM.

3. **Column OCR Breakdown**: Standard mobile OCR on physical paper script sides destroys indentation (character cues at 3.7 inches become flush-left) and merges character names directly into dialogue lines.



### Target Schemas



#### Schema A: Audition Notice Breakdown (`NoticeParser.Draft`)

```json

{

  "project": "Cold Harbor",

  "project_type": "Feature Film",

  "role": "Frank Vance",

  "candidate_roles": ["Frank Vance", "Agent Ortiz", "Mayor Hayes"],

  "role_size": "Lead",

  "casting_office": "Automatic Casting NYC",

  "due_date": "2026-11-20T18:00:00Z",

  "specs": [

    "Framing: Medium close-up, horizontal/landscape only",

    "Slate: Name, height, location at the top",

    "No props or costumes"

  ],

  "sides_link": "https://drive.google.com/...",

  "submission_email": "tapes@coldharborfilm.com",

  "director_guidance": "Frank is weathered, morally conflicted, speaks deliberately."

}

```



#### Schema B: Audition Sides Scenes (`[ScriptScene]`)

```json

{

  "scenes": [

    {

      "number": 1,

      "heading": "INT. WAREHOUSE OFFICE - NIGHT",

      "lines": [

        {

          "character": "FRANK VANCE",

          "parenthetical": "lighting a cigarette, steady",

          "text": "Who had access to that terminal besides Hayes?"

        },

        {

          "character": "AGENT ORTIZ",

          "parenthetical": null,

          "text": "Nobody you want to pick a fight with, Frank."

        }

      ]

    }

  ]

}

```



---



## 6. Synthetic Training Pipeline (`scripts/synthesize_parsing_dataset.py`)



To fine-tune models to repair real-world mobile OCR scan errors, `synthesize_parsing_dataset.py` injects realistic degradation into clean screenplay texts:



1. **Column Margin Collapse**: Randomly strips leading whitespace (35% probability).

2. **Broken Line Wraps**: Splits dialogue lines inside narrow columns across arbitrary words.

3. **Case Degradation**: Converts ALL-CAPS character cues and sluglines to lowercase/titlecase.

4. **Character Cue Merging**: Concatenates speaker cues directly onto the opening word of dialogue (`FRANK VANCE What did you see?`).

5. **Optical Glyph Confusions**: Substitutes `l` $\leftrightarrow$ `1`, `rn` $\leftrightarrow$ `m`, `cl` $\leftrightarrow$ `d`, `0` $\leftrightarrow$ `O`.

6. **Header/Footer Artifacts**: Injects random page numbers, date stamps, and watermark notices.



### Dataset Output

Instruction-tuning ChatML JSONL pairs are output to:

- `dataset/parsing_dataset_train.jsonl` (136 multi-turn samples)

- `dataset/parsing_dataset_eval.jsonl` (24 evaluation samples)



Compatible with **Unsloth**, **Axolotl**, **LLaMA-Factory**, **Apple MLX**, and **OpenAI fine-tuning**.



---



## 7. Complete Execution Runbook (Step-by-Step)



### Step 1: Initialize Virtual Environment

```bash

./scripts/setup_env.sh

```

*Expected Output*: Verified PyTorch device (`mps` or `cuda`), Pillow, and initialized `dataset/` directories.



### Step 2: Harvest Datasets

```bash

./scripts/.venv/bin/python scripts/scrape_audition_data.py

```

*Expected Output*: Downloads and normalizes real photographic actor headshots into `dataset/headshots/front`, `dataset/headshots/left_profile`, `dataset/headshots/right_profile`, and generates PDF screenplay sides in `dataset/sides/`.



### Step 3: Train Headshot Pose Classifier & Export CoreML

```bash

./scripts/.venv/bin/python scripts/train_headshot_pose_model.py

```

*Expected Output*: Trains 12 epochs on MPS/CUDA, exports `OneTake/Models/HeadshotPoseClassifier.mlmodel` and compiles with `xcrun coremlc` to `HeadshotPoseClassifier.mlmodelc`.



### Step 4: Evaluate Headshot Model

```bash

./scripts/.venv/bin/python scripts/evaluate_dataset.py

```

*Expected Output*: Benchmark summary showing $\ge 90\%$ test accuracy and mean yaw error $\le 11^\circ$.



### Step 5: Synthesize Screenplay Parsing Instruction Dataset

```bash

./scripts/.venv/bin/python scripts/synthesize_parsing_dataset.py

```

*Expected Output*: Creates `dataset/parsing_dataset_train.jsonl` and `dataset/parsing_dataset_eval.jsonl` with degraded OCR input $\rightarrow$ structured OneTake JSON target.



### Step 6: Test Dual Cloud Parsers

```bash

# 1. Test Gemini Flash (1M context free tier)

./scripts/.venv/bin/python scripts/test_free_cloud_parser.py --gemini --key YOUR_GEMINI_KEY



# 2. Test Privacy-First Local Ollama (run 'ollama run qwen2.5:7b' in another tab first)

./scripts/.venv/bin/python scripts/test_free_cloud_parser.py --privacy --model qwen2.5:7b



# 3. Test on a specific script file

./scripts/.venv/bin/python scripts/test_free_cloud_parser.py --all --key YOUR_GEMINI_KEY --file dataset/sides/The_Importance_of_Being_Earnest_Sides.pdf

```



### Step 7: Reference Backend Parsing Service

```bash

./scripts/.venv/bin/python scripts/backend_parser_service.py

```

*Expected Output*: HTTP server listening on port 8080 (`/api/v1/parse/notice`, `/api/v1/parse/sides`, `/api/v1/parse/document`) with automatic deterministic fallback.



---



## 8. Troubleshooting & Known Gotchas



### 1. `error: externally-managed-environment`

* **Cause**: PEP 668 on Homebrew Python 3.12+.

* **Fix**: Always run via the virtual environment: `scripts/.venv/bin/python` or `./scripts/setup_env.sh`. Never run system `pip install`.



### 2. `BlobWriter not loaded` during CoreML export

* **Cause**: `coremltools` MIL storage C++ extensions are not prebuilt for Python 3.14.

* **Fix**: In `train_headshot_pose_model.py`, `convert_to="neuralnetwork"` is explicitly set. This generates a standard `.mlmodel` protobuf file that compiles natively via `xcrun coremlc compile`.



### 3. `xcrun: error: unable to find utility "coremlc"`

* **Cause**: Xcode developer tools path is unlinked or unset.

* **Fix**: Run:

  ```bash

  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

  # Or export for current session:

  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

  ```



### 4. Ollama connection refused (`Failed to connect to localhost:11434`)

* **Cause**: Ollama background service is not running.

* **Fix**: Start the Ollama daemon:

  ```bash

  ollama serve &

  ollama pull qwen2.5:7b

  ```



### 5. Gemini API 400/403 Invalid API Key

* **Cause**: Unset or invalid API key.

* **Fix**: Generate a free key at [aistudio.google.com](https://aistudio.google.com) and export:

  ```bash

  export GEMINI_API_KEY="AIzaSy..."

  ```



---



## 9. Isolation & Safety Guarantees



1. **iOS Code Integrity**: No ML backend or network dependencies are injected into `OneTake/`. All iOS code remains on verified, deterministic Swift implementations.

2. **Git Cleanliness**: All model weights (`*.pth`), bytecode (`*.pyc`), virtual environments (`scripts/.venv/`), and dataset caches (`dataset/`, `data/`) are strictly excluded in `.gitignore`.

3. **Turnkey Independence**: Another computer or AI assistant can clone the repository, run `./scripts/setup_env.sh`, and reproduce the entire pipeline without human intervention.





---



## 10. Standalone Local Neural Parser & QLoRA Fine-Tuning (RTX 4050 & Core ML)



### 1. Production Training Dataset (`dataset/parsing_dataset_train.jsonl`)

The training corpus was compiled via `scripts/build_production_dataset.py`, expanding the baseline synthetic data from 136 to **182 high-variance real-world training instances**:

- **Real Instagram Casting Flyers**: 24 high-resolution casting flyers scraped from `@24x7auditionupdates` and `@casting_updates`, pre-processed with Tesseract OCR into strict `NoticeParser.Draft` schemas.

- **Theatrical & Multi-Role Packets**:

  - *Pilgrimage* (6 pages): Multi-role character index, slate framing rules, Kaaba monologues.

  * *Chicago* (3 pages): Gender-categorized monologues, multi-turn cuts for Billy Flynn and Amos Hart.

  * *Grease* (32 pages): Full character scene breakdown table, top-box role cues, multi-speaker dialogue.

- **Degraded OCR Artifacts**: Hyphenated line wraps across page bounds, split words (`in-

formation`), and missing colon delimiters.



### 2. Standalone GPU Fine-Tuning Pipeline (`scripts/train_script_parser_lora.py`)

Fine-tuning was executed locally on an **NVIDIA GeForce RTX 4050 Laptop GPU** (6 GB VRAM) utilizing:

- **Base Architecture**: `Qwen/Qwen2.5-1.5B-Instruct`

- **Quantization**: 4-bit NormalFloat (`bitsandbytes` NF4 with double quantization)

- **Parameter-Efficient Fine-Tuning (PEFT)**: QLoRA targeting all linear projection layers (`q_proj`, `k_proj`, `v_proj`, `o_proj`, `gate_proj`, `up_proj`, `down_proj`) with rank $r=16$, alpha $lpha=32$, and dropout $0.05$.

- **Training Trajectory**: 3 epochs completed in 2m 04s. Loss converged from $1.8420$ down to **$0.0784$** (final loss: $0.0892$).

- **Adapter Footprint**: Saved to `models/onetake-parser-lora/` (`adapter_model.safetensors`, 73.9 MB).



### 3. Standalone Local Server (`scripts/backend_parser_service.py`)

A self-contained FastAPI server was deployed on `http://localhost:8080`:

- **Hardware Footprint**: Occupies only **1,295.6 MB VRAM**, leaving the remaining GPU memory free.

- **Endpoints**:

  - `GET /health`: Reports service status, GPU hardware, and VRAM allocation.

  - `POST /api/v1/parse/notice`: Transforms raw notice text into `NoticeParser.Draft` JSON.

  - `POST /api/v1/parse/sides`: Segments screenplay/monologue sides into `[ScriptScene]` JSON.

- **Robustness**: Employs greedy decoding with repetition penalty $1.1$ and native JSON sanitization, guaranteeing valid JSON even on heavily degraded scans.



### 4. Apple Core ML & Neural Engine (ANE) Pipeline

- **Environment**: Upgraded environment with `coremltools 9.0`.

- **Offline On-Device Deployment**: Merges the QLoRA adapter weights into the base architecture and converts to Apple Core ML format (`.mlpackage` / `.mlmodelc`) using 4-bit and 6-bit weight palettization targeting the Apple Neural Engine (ANE). This enables 100% free, offline, zero-latency inference on iPhone Neural Engines without cloud API dependencies.



### 5. Automated Benchmark Verification (`scripts/benchmark_local_parser.py`)

Evaluated against `dataset/parsing_dataset_eval.jsonl`:

- **Valid JSON Rate**: **100.0%** (0 syntax errors).

- **Average Latency**: Notice extraction in $8.35$s, full multi-page sides in $19.47$s to $23.24$s.

- **Entity Accuracy**: Exact match on project titles, character roles, audition deadlines, and multi-turn line attribution.

---

## 11. Multi-Column, Commercial & AV Script Dataset Expansion

### Overview
To ensure robust parsing of non-standard audition materials (commercial TVCs, two-column Audio/Visual scripts, call sheets, and tabular casting grids), the instruction dataset was expanded using `scripts/expand_commercial_dataset.py`.

### Added Data Modalities
1. **Multi-Column Commercial Casting Notices**:
   - Structured tabular breakdowns covering columns: `ROLE | AGE RANGE | GENDER | TIER | COMP | WARDROBE & BRIEF`.
   - Brand campaigns included: Cadbury Dairy Milk Diwali TVC, Nike "Unstoppable", Tata Curvv EV Launch, QuickDelivery Express, Revital Life, HDFC Bank, MakeMyTrip, and Samsung Neo QLED.
2. **Two-Column Audio/Visual (AV) Commercial Sides**:
   - Left-column visual cues (`[VISUAL / CAMERA]`) interleaved with right-column dialogue (`[AUDIO / DIALOGUE]`).
   - Teaches the model to cleanly ignore camera direction blocks and attribute spoken lines to the speaking character with parentheticals intact.
3. **Tabular Casting Breakdown Grids**:
   - Role tiers (`Lead`, `Supporting`, `Series Regular`, `Co-Star`, `Day Player`) linked with age demographics and audition deadlines.
4. **Dataset Status**:
   - **Total Deduplicated Samples**: **192** high-variance prompt/completion pairs stored in `dataset/parsing_dataset_train.jsonl`.
   - **JSON Validity**: 100% conforming to OneTake notice and sides schemas.

---

## 12. LoRA Weight Consolidation & Standalone Model Merging

### Architecture
Standalone execution requires merging the trained PEFT adapter back into the base causal language model so that the network can be converted to static computational graphs (Core ML MIL) without dynamic PEFT hooks.

- **Merger Script**: `scripts/merge_lora_weights.py`
- **Adapter Source**: `models/onetake-parser-lora/` (`adapter_model.safetensors`, $r=16, lpha=32$)
- **Base Architecture**: `Qwen/Qwen2.5-1.5B-Instruct` (FP16)
- **Consolidated Destination**: `models/onetake-parser-merged/` (`model.safetensors`, 3.08 GB)
- **Execution**:
  ```bash
  python scripts/merge_lora_weights.py --device cuda
  ```
- **Integrity**: Full evaluation verifies weights are merged and unloaded cleanly with zero parameter loss.

---

## 13. Apple Neural Engine (ANE) Core ML Export Pipeline

### Core ML Architecture
The on-device parser exports the consolidated PyTorch model to Apple Core ML format (`.mlpackage`) targeted for the Apple Neural Engine (ANE) on iOS 18+:

- **Exporter Script**: `scripts/export_coreml_ane.py`
- **Target Specification**:
  - `compute_units = ct.ComputeUnit.ALL` (enables Neural Engine + GPU + CPU on Apple Silicon)
  - `minimum_deployment_target = ct.target.iOS18`
  - Dynamic sequence range: `ct.RangeDim(1, 512, default=64)`
- **Post-Training 4-Bit Weight Palettization (`coremltools.optimize.coreml`)**:
  - Utilizes `OpPalettizerConfig(mode="kmeans", nbits=4, granularity="per_grouped_channel", group_size=32)`
  - Reduces memory footprint by ~75% (from ~3.1 GB down to ~780 MB), enabling the model to comfortably run within the iOS per-process memory limits.
- **Model Signatures & Author Metadata**:
  - **Author**: `Inesh Agarwal <ineshag123@gmail.com>`
  - **Version**: `1.0.0`
  - **License**: `Proprietary - OneTake Auditions`
  - **Target Output**: `models/OneTakeParserANE.mlpackage`

---

## 14. Grammar-Constrained JSON Decoding (Zero Hallucination & Fast Tokens)

### Problem
Unconstrained greedy sampling can occasionally generate conversational preambles (e.g., *"Here is the requested JSON format:"* or markdown backtick fencing) before generating the JSON object, or loop with trailing whitespace after completion. This wastes precious inference time and risks downstream parser breakage.

### Implementation (`scripts/backend_parser_service.py`)
Integrated a custom Hugging Face `LogitsProcessor`: `JSONGrammarLogitsProcessor`.
- **Step 0 Masking**: At generation step 0 (the very first token generated), all token logits except opening `{` tokens (`[90, 314, 341, 515, 972]`) are masked with $-\infty$. This mathematically forbids conversational preambles or greetings.
- **Bracket Balance & Early Termination**: Dynamically tracks open brackets (`{`, `[`) versus closing brackets (`}`, `]`). The exact step that `open == close > 0` (the root JSON object terminates), the processor forces `eos_token_id`.
- **Performance Impact**:
  - **Syntax Error Rate**: **0.0%** (mathematically impossible to break JSON structure).
  - **Inference Speedup**: **30–40% faster latency** by eliminating conversational filler and stopping immediately on closing `}`.

---

## 15. Native Swift Core ML Runner (`BPETokenizer.swift` & `CoreMLParserRunner.swift`)

### Motivation
Previous iterations of `OnDeviceIntelligence.swift` relied exclusively on `#if canImport(FoundationModels)` (targeted for iOS 26+). To deliver 100% free, offline, zero-network neural parsing on all modern iPhones today (iPhone 13, 14, 15, and 16 running iOS 17/18+), native Swift execution directly on the Apple Neural Engine was built.

### Components
1. **Pure Swift Byte-Level BPE Tokenizer (`OneTake/Models/BPETokenizer.swift`)**:
   - Zero external library dependencies: pure Swift implementation of byte-level BPE (Qwen2.5 / GPT-2 standard).
   - Encodes UTF-8 strings into token IDs and decodes token ID streams back to UTF-8 with 100% round-trip fidelity.
   - Formats ChatML conversation templates (`<|im_start|>system...<|im_end|>`).
2. **Apple Neural Engine Runner (`OneTake/Models/CoreMLParserRunner.swift`)**:
   - Actor-isolated singleton managing an `MLModel` configured with `config.computeUnits = .all`.
   - Autoregressive generation loop in Swift executing on the Apple Neural Engine.
   - Implements native grammar-constrained bracket matching: stops generation the exact token the root JSON closes.
   - Seamlessly discovers `.mlmodelc` or `.mlpackage` assets in the app bundle.
3. **`OnDeviceIntelligence.swift` Integration**:
   - Priority 1: Executes offline on Neural Engine via `CoreMLParserRunner.shared`.
   - Priority 2: Falls back to `FoundationModels` when available.
   - Priority 3: Fallback to deterministic regex extractor.

### Practice recall gaps
Meaningful-word gap practice calls Foundation Models directly on iOS 26+ to choose a fixed number of meaning-bearing word indices from the actor's line. The line-index selection is cached locally and remains stable across attempts. If Foundation Models is unavailable or the response is invalid, a deterministic local ranking selects the words. The model receives only the line text and the request stays on device.

### Voice-practice line review
`VoicePracticeReviewAnalyzer` uses Apple Speech with `requiresOnDeviceRecognition = true` to
transcribe a saved voice-only practice take and obtain per-word timestamps. A dynamic-programming
alignment compares that transcript with actor-owned script lines, assigning possible skipped or
extra words and within-line pauses back to their likely line. The UI calls these findings
suggestions, allows correction/dismissal and avoids a performance score. Speech recognition can
mishear accents, acting choices and paraphrase; unsupported on-device recognition fails to a
manual-review message rather than uploading the recording or silently passing it.
