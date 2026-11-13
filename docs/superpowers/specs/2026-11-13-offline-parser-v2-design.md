# Offline Document & Notice Parser v2 Design Specification

- **Date:** 2026-11-13
- **Topic:** 100% Offline Tiered Document Ingestion, Geometry-Aware Script Parsing, and On-Device VLM + Needle Notice Extraction
- **Target:** iOS 18.0+, tested down to iPhone 11 (4 GB RAM), zero cloud inference dependencies
- **Document Status:** Draft for User Review

---

## 1. Problem Statement & Goals

OneTake’s parser pipeline currently splits between:
1. Regex-heavy notice heuristics (`NoticeParser.swift`, `NoticeParser+Detectors.swift`, `NoticeParser+DatesAndRoles.swift`), because `CoreMLParserRunner.swift` (`OneTakeParser` / `OneTakeParserANE`) has no bundled weights (its prior 3.1 GB Qwen 1.5B design caused OOM/size issues) and `FoundationModels` only runs on Apple-Intelligence-enabled iOS 26+ hardware.
2. Flat `PDFPage.string` extraction in `NoticeOCR.swift`, which strips X-indentation, merges columns out of visual order, and forces `ScriptElementClassifier.mlmodel` (`NLModel`) + `ScriptParser.swift` to guess speaker cues without layout or neighbor context.
3. Missing native support for structured industry formats (`.fdx`, `.fountain`, `.docx`).

**Design Goals:**
- **100% Offline Execution:** Zero external inference API calls at runtime.
- **Lean Base Install + Optional Heavy Accuracy:** Keep base binary weight growth to `~40–60 MB` (`cactus-ios.xcframework` + `Needle 3` CQ2), while supporting an optional `~350–400 MB` background-downloaded VLM pack (`LFM2.5-VL-450M` CQ4) via direct HTTPS from Hugging Face / GitHub Releases.
- **4 GB RAM Safe:** Strictly cap active resident inference memory under `< 1 GB` so an iPhone 11 (`~2.0–2.4 GB` Jetsam headroom) never OOMs.
- **Keep Scripts Non-Generative:** Parse 25–50 page scripts in `< 0.2s` using geometry + context-aware line classification, reserving generative models exclusively for short notice/flyer extraction.
- **Colab-Reproducible:** Train, LoRA-tune, evaluate, and quantize all three ML artifacts using Google Colab scripts in `scripts/colab/`.

---

## 2. High-Level Architecture & Data Flow

```text
  [Input: UIImage(s) / PDF / .fdx / .fountain / .docx / .rtf / Pasted Text]
                                     │
                                     ▼
  ┌─────────────────────────────────────────────────────────────────────┐
  │ Stage 1: Unified Acquisition & Geometry (`NoticeOCR`)               │
  │  • .fdx / .fountain   -> Direct structured AST (`ScriptScene` fast) │
  │  • .docx / .rtf       -> XML/attributed lines + alignment/indent    │
  │  • Digital PDF        -> `PDFGeometryExtractor` normalized X/Y boxes│
  │  • Scans / Photos     -> Vision OCR boxes + footer contrast crop    │
  │  • Output: `LayoutDocument` + `DocumentPageRouter` (notice vs sides)│
  └──────────────────────────────────┬──────────────────────────────────┘
                                     │
                   ┌─────────────────┴─────────────────┐
                   ▼                                   ▼
  ┌─────────────────────────────────┐  ┌────────────────────────────────┐
  │ Stage 2A: Non-Generative        │  │ Stage 2B: Semantic Notice Tier │
  │     Script Engine               │  │    (Notice Pages / Flyers)     │
  │                                 │  │                                │
  │ • Input: `sides` pages + layout │  │ Pass 1: Deterministic exact    │
  │ • `ScriptElementClassifier` v2  │  │   tokens (email, URL, phone,   │
  │   uses (xIndent, lineHeight,    │  │   dates, duration, orientation)│
  │   prevClass, uppercase, text)   │  │                                │
  │ • `ScriptParser` O(lines) state │  │ Pass 2: Best local tier:       │
  │   machine -> `[ScriptScene]`    │  │   • Image + VLM pack ready ->  │
  │   in < 0.2s for 50 pages        │  │     `LFM2.5-VL-450M` (CQ4)     │
  └────────────────┬────────────────┘  │   • Text/PDF or Base-only ->   │
                   │                   │     `Needle 3` (CQ2, ~29 MB)   │
                   │                   │     (+ `FoundationModels` when │
                   │                   │     available on iOS 26+)      │
                   │                   │                                │
                   │                   │ Pass 3: `NoticeMergeEngine`    │
                   │                   │   Grounded merge + blacklists  │
                   └─────────┬─────────┴───────────────┬────────────────┘
                             ▼                         ▼
                   [Populated `NoticeParser.Draft` -> `NoticeReviewView`]
```

---

## 3. Component Design

### 3.1 Stage 1 — Unified Geometry & Format Acquisition (`NoticeOCR`)
- **`LayoutLine` & `LayoutDocument`:** Extend the geometric representation already used inside `OCRLayoutReconstructor.swift` so both digital PDFs and camera/photo OCR share one structured line model containing `text`, normalized `boundingBox` (`CGRect` in `[0, 1]`), `pageIndex`, and `estimatedIndent`.
- **`PDFGeometryExtractor`:** Extract line-grouped text runs and X/Y bounds directly from `PDFPage` (`PDFSelection` line slices / word rects) instead of flat `PDFPage.string`, preserving screenplay margins (~3.7" cues vs ~2.5" dialogue vs ~1.5" action) and preventing two-column tables (`Pilgrimage` character tables, commercial `VIDEO | AUDIO` scripts) from interleaving. Retain `PDFPage.string` strictly as a fallback if selection extraction returns empty.
- **Native Structured Formats:**
  - `.fdx` (Final Draft XML) parser via `Foundation.XMLParser` mapping `<Paragraph Type="Scene Heading|Character|Dialogue|Parenthetical|Action">` directly to `ScriptScene` and `ScriptLine`.
  - `.fountain` parser handling sluglines, forced cues (`@`), character/dialogue blocks, dual dialogue (`^`), and metadata headers.
  - `.docx` reader extracting `word/document.xml` paragraphs and indentation (`w:ind`) via the existing zip infrastructure and `XMLParser`.
- **`DocumentPageRouter`:** Classifies each page of a multi-page packet as `.notice` or `.sides` using dialogue cue density, slugline presence, and casting-notice anchors (`HOW TO USE THESE SIDES`, `SLATE`, email/URL/deadline patterns). Only `.notice` pages feed semantic notice models (`<= 1,024` token budget for Needle); only `.sides` pages feed `ScriptParser`.

### 3.2 Stage 2A — Context-Aware Script Engine (`CoreMLScriptParserRunner` + `ScriptParser`)
- **`ScriptElementClassifier` v2 (`< 5 MB` Core ML):** Replace isolated single-string classification with a tabular/sequence feature classifier trained on screenplay, stage-play, commercial, and multi-role packet lines:
  - Inputs: normalized `leftX` indent, `widthRatio`, `blankLineBefore`, `blankLineAfter`, `uppercaseRatio`, `lineLength`, `prevPredictedClass`, and tokenized line text features.
  - Classes: `scene_heading`, `character_cue`, `dialogue`, `parenthetical`, `action`, `metadata`.
- **`ScriptParser.swift` Integration:** Preserve the `O(lines)` deterministic state machine, `isLineOrPageNumber` pre-filter, `(CONT'D)` merging, and multi-role filtering so 25–50 page scripts stay `< 0.2s` while cutting false-positive headings and swallowed dialogue lines.

### 3.3 Stage 2B — Unified Cactus Semantic Runner (`CactusParserRunner`)
Replace the dormant `CoreMLParserRunner.swift` (`OneTakeParser`) implementation with a single serialized Swift actor `CactusParserRunner` backed by `swift-cactus` (`cactus-ios.xcframework`):
- **Single-Resident Memory Contract (iPhone 11 `4 GB` RAM):**
  - Never load `Needle 3` and `LFM2.5-VL-450M` concurrently.
  - Acquire one model at a time inside `CactusParserRunner`, execute generation under byte-level JSON grammar constraints, and immediately release native memory (`cactus_destroy`) in a `defer` block.
  - Downscale any image passed to `LFM2.5-VL-450M` to `<= 768px` max edge (matching the encoder's mobile resolution envelope) and cap Needle text inputs to `<= 1,024` tokens from `DocumentPageRouter`.
  - Enforce a hard `10s` per-document timeout; on timeout or cancellation, destroy the context cleanly and return `nil` so the deterministic parser completes the import without blocking the UI.
- **Canonical `SemanticNoticePayload` JSON Schema:** Both Needle 3 and `LFM2.5-VL-450M` emit identical schema keys:
  ```json
  {
    "project": "string | null",
    "project_type": "string | null",
    "role": "string | null",
    "candidate_roles": ["string"],
    "role_size": "string | null",
    "casting_office": "string | null",
    "due_date_text": "string | null",
    "specs": ["string"],
    "sides_link": "string | null",
    "submission_email": "string | null",
    "location": "string | null",
    "casting_notes": "string | null",
    "union_status": "string | null",
    "pay_terms": "string | null",
    "callback_dates_text": "string | null",
    "shoot_dates_text": "string | null",
    "orientation": "Landscape | Portrait | null",
    "file_naming": "string | null"
  }
  ```
- **Routing Strategy:**
  - **Image / scanned flyer + VLM pack ready:** Run Apple Vision OCR first (~0.3s, freeing its buffers) and then run `LFM2.5-VL-450M` (`4-bit` CQ4) on the resized poster image (`cactus` VLM destroys immediately after JSON extraction) so OCR and VLM peak allocations never stack on 4 GB devices.
  - **Digital PDF / `.docx` / pasted text / VLM pack not installed:** Run bundled `Needle 3` (`2-bit` CQ2, `~29 MB`) on the bounded notice text slice. On iOS 26+ devices where `SystemLanguageModel.default.isAvailable == true`, keep `OnDeviceIntelligence.refineDraftWithFoundationModel` as a supplementary pass only for remaining empty fields.

### 3.4 Deterministic Authority & `NoticeMergeEngine`
Quantized 2-bit and 4-bit models must never corrupt exact submission destinations or hallucinate roles:
- **Deterministic Overrides:** Regex/data-detector hits in `NoticeParser+Detectors.swift` remain authoritative for valid emails, URLs, phone numbers, parsed calendar dates, and explicit duration limits. If `LFM2.5-VL` recovers a valid email missed by OCR (e.g., low-contrast footer text), accept it only if it passes strict email/domain syntax validation (`@` + valid TLD) and is absent from deterministic results.
- **Semantic Wins with Grounding:** Use semantic predictions for `project`, consolidated `role` + `candidateRoles`, `castingOffice`, `location`, `asks` (`specs`), and `castingNotes`, filtered through existing grounding validators (`isGroundedProjectTitle`, `isGroundedCastingOffice`, `isGroundedNoticeValue`, `isBlacklistedNoticeWord`, `isValidCastingOfficeCandidate`) before populating `NoticeParser.Draft`.

### 3.5 Offline Pack Delivery (`ModelPackManager`)
- **Storage:** `Library/Application Support/OneTake/Models/lfm2.5-vl-450m/` (excluded from iCloud backup via `.isExcludedFromBackupKey`).
- **Remote Manifest:** Direct HTTPS fetch of `manifest.json` (`modelId`, `version`, `downloadURL`, `byteSize`, `sha256`, `minAppVersion`) hosted on your Hugging Face Hub repository / GitHub Release.
- **Atomic Download & Integrity:** Background `URLSession` download -> verify **SHA-256** digest -> atomically swap temp directory into active `current/` pack -> clean prior version. Zero impact on personal Apple Developer provisioning (`W93H964P88`).
- **User Controls:** Add an "Offline AI Poster Pack (~380 MB)" card in Profile settings showing install status, progress, storage usage, and Delete/Redownload controls; when importing an image without the pack installed, keep an unobtrusive inline tip in `NoticeReviewView` / `AddAuditionFlow` rather than blocking offline import.

---

## 4. Google Colab Training & Quantization Pipeline (`scripts/colab/`)

Replaces the dormant local 1.5B training assumptions with three reproducible Colab notebooks/scripts:
1. **Shared Corpus & Synthetic Flyer Renderer (`build_offline_v2_corpus.py`):**
   - Aggregates real samples (`Grease`, `Pilgrimage`, `Chicago`, `flyer_test.jpg`, standard breakdowns, `.fdx`/`.fountain` open screenplays) plus a synthetic HTML/Pillow casting-poster generator producing `5,000–10,000` paired examples and `500` held-out adversarial stress examples:
     - Each generated poster renders a high-variance PNG (multi-column grids, watermark badges, gradient/photo backgrounds, low-contrast white footer contact text, non-English/Indian regional casting calls, mixed Arabic/Latin/Hindi transliteration) paired with its ground-truth `SemanticNoticePayload` JSON **and** simulated OCR-degraded text.
2. **Job 1 — `ScriptElementClassifier` v2 (`train_script_classifier_v2.py`):**
   - Trains a lightweight tree/MLP classifier (`< 5 MB`) on geometric + neighbor features across 25k screenplay/play/commercial lines and exports `.mlpackage` via `coremltools`.
3. **Job 2 — `Needle 3` Base Notice LoRA (`train_needle3_lora.py`):**
   - Fine-tunes Needle 3 (`<= 1,024` token slices) via `cactus-needle[train]`, merges & quantizes via `cactus convert ... --bits 2`, verifies accuracy, and commits updated ~29 MB weight artifact for app bundling.
4. **Job 3 — `LFM2.5-VL-450M` Flyer/Notice VLM LoRA (`train_lfm25_vl_lora.py`):**
   - LoRA-tunes `LiquidAI/LFM2.5-VL-450M` on paired `(poster_image.png, schema_prompt) -> JSON`, merges & quantizes via `cactus convert LiquidAI/LFM2.5-VL-450M ... --lora ... --bits 4`, generates `manifest.json` + SHA-256, and uploads release artifacts to HF Hub / GitHub Releases.

---

## 5. Error Handling & Edge Cases

- **Missing or Corrupted VLM Pack:** `ModelPackManager` refuses activation unless SHA-256 matches `manifest.json`; any load failure inside `CactusParserRunner` falls back transparently to `Needle 3` and deterministic `NoticeParser`.
- **Encrypted / Unreadable Documents:** Password-protected PDFs or malformed `.fdx`/`.docx` files return a clear typed import error with manual photo/paste fallback rather than silent blank auditions.
- **Oversized Inputs:** Images are downscaled before VLM encoding (`<= 768px` max dimension); notice text exceeding Needle's 1K-token limit is deterministically trimmed by `DocumentPageRouter` to keep front-matter headers, email/URL footers, and requirement blocks intact.
- **App Lifecycle / Backgrounding:** `CactusParserRunner` checks `Task.isCancelled`, tears down `cactus_destroy`, and lets the user re-run extraction cleanly if backgrounded mid-import.

---

## 6. Verification Plan & Acceptance Criteria

- **Pre-Publish Colab Evaluation Gate:** Extend `scripts/evaluate_field_accuracy.py` to score both `Needle 3` and `LFM2.5-VL-450M` against the `500`-sample held-out set (target: `>= 98%` exact match on verified `submission_email` / `sides_link` after `NoticeMergeEngine`, `>= 90%` F1 on `role` / `project` / `casting_office` / `asks`).
- **On-Device Unit & Integration Tests (`OneTakeTests`):**
  - Add format fixtures & assertions for `PDFGeometryExtractor`, `.fdx`, `.fountain`, `.docx`, and `DocumentPageRouter`.
  - Add mocked + real-model unit tests for `NoticeMergeEngine` grounding rules and `ModelPackManager` SHA-256 verification / atomic swap / corruption rollback.
  - Keep all existing real fixtures (`flyer_test.jpg`, `Grease+Audition+Sides+V2.pdf`, `Pilgrimage_Casting_Sides.pdf`) passing in `RealPDFParserTests` and `ScriptParserStressTests`.
- **Physical Device Benchmarks (`Avinash’s iPhone`, iPhone 11 4 GB RAM):**
  - Peak app footprint during `LFM2.5-VL-450M` poster inference verified `< 1.4 GB` via Xcode Memory Gauge / `os_proc_available_memory` tests (no Jetsam kill across 10 consecutive imports).
  - Latency targets on iPhone 11: `< 0.25s` for 50-page digital script parsing, `< 1.5s` for `Needle 3` notice extraction, `< 10s` for `LFM2.5-VL-450M` poster VLM extraction.
- **Repo Quality Gates:**
  - `./scripts/lint-design-system.sh --strict` passes with `0` violations.
  - Every Swift file remains strictly under `800` lines (`project.yml` kept in sync via `xcodegen generate`).
