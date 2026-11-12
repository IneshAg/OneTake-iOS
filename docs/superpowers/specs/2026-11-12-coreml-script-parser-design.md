# Core ML Script Element Classifier Design Specification

- **Date:** 2026-11-12
- **Topic:** Replacing Regex Heuristics with Native Core ML Text Element Classification in `ScriptParser`
- **Target:** iOS 18.0+, Apple Silicon / Neural Engine (ANE)
- **Document Status:** Approved for Implementation

---

## 1. Problem Statement & Motivation

Currently, `ScriptParser.swift` turns raw text (from camera OCR, document scanner, PDF, or pasted sides) into structured screenplay scenes (`ScriptScene`) and spoken lines (`ScriptLine`) using fragile regular expressions and string heuristics:
- `characterHeaderRegex`, `periodCueRegex`, `isLikelyCue`
- Slugline prefixes (`INT.`, `EXT.`, `SCENE 1`, `ACT I`)
- Parenthetical stripping and action direction detection

These regex heuristics suffer from:
1. **Misclassification of Left-Aligned / Formatted Text:** Modern digitized sides and mobile OCR frequently strip indentations and drop capitalization, causing actor character cues to be swallowed into preceding dialogue or action blocks.
2. **Action / Dialogue Contamination:** Narrative scene descriptions (e.g., *"Maya nervously checks her phone at the kitchen counter."*) frequently get appended to dialogue lines if character cues aren't formatted in strict all-caps.
3. **Multi-Role Sides Breakdown Fragility:** Sides packets with character descriptions or casting notices inline frequently trick regexes into generating phantom scenes or dummy dialogue lines.

The previous attempt to solve this via a 3.1 GB Qwen 1.5B LLM (`Inesh016/onetake-parser-merged`) was rejected because:
- Its 3.1 GB weight size cannot be distributed over-the-air in an iOS app.
- Generating tokens autoregressively without a stateful KV cache takes 15–45 seconds per page and consumes >1.5 GB of RAM, triggering kernel jetsam (OOM crashes) on 4–6 GB devices.

---

## 2. Solution: Dedicated Core ML Script Classifier (`ScriptElementClassifier`)

We introduce **`ScriptElementClassifier.mlmodel`**, a specialized, native Core ML text classification model trained directly on screenplay text structures.

### 2.1 Model Specifications
* **Artifact:** `OneTake/Core/Models/ScriptElementClassifier.mlmodel` (compiled to `ScriptElementClassifier.mlmodelc` during Xcode build).
* **Model Type:** Multiclass Text Classifier leveraging Apple's `NaturalLanguage` text embedding / MaxEnt/BiLSTM classifier or Core ML Neural Network.
* **Size:** < 3 MB.
* **Latency:** < 5 ms for a full multi-page sides document on Apple Neural Engine (ANE) / CPU.
* **Memory:** < 5 MB RAM, unloaded cleanly when inference finishes.
* **Target Classes:**
  1. `scene_heading`: Sluglines (`INT. CAFÉ — DAY`, `EXT. STREET — NIGHT`, `SCENE 1`, `ACT I`)
  2. `character_cue`: Speaker identity cues (`MAYA`, `ARJUN (CONT'D)`, `DANNY:`, `Patty (O.S.)`)
  3. `dialogue`: Spoken dialogue lines (`You're late.`, `I know. Traffic was terrible.`)
  4. `parenthetical`: Delivery instructions (`(whispering)`, `(beat)`, `(to Arjun)`)
  5. `action`: Narrative action / stage directions (`Maya nervous paces around the room.`)
  6. `metadata`: Page headers, footers, watermarks (`CONFIDENTIAL`, `PAGE 4 OF 12`, `AUDITION SIDES ONLY`)

---

## 3. Architecture & Integration Pipeline

```
+--------------------------------------------------------+
|                      Raw Script Text                   |
|   (from NoticeOCR / PDFKit / Scanner / Clipboard)      |
+--------------------------------------------------------+
                           |
                           v
+--------------------------------------------------------+
|           Line Normalizer & Cleaning Filter            |
|   - Strips zero-width chars and OCR noise             |
|   - Preserves line-breaks & speaker boundaries         |
+--------------------------------------------------------+
                           |
                           v
+--------------------------------------------------------+
|       Core ML ScriptElementClassifier Engine           |
|   - Evaluates each line on Apple Neural Engine (ANE)   |
|   - Predicts class: heading / cue / dialogue / etc.    |
+--------------------------------------------------------+
                           |
                           v
+--------------------------------------------------------+
|           ScriptParser Scene & Line Assembler          |
|   - scene_heading    -> creates new ScriptScene        |
|   - character_cue    -> switches active speaker        |
|   - dialogue         -> formats & appends ScriptLine   |
|   - parenthetical    -> strips / logs delivery cue     |
|   - action/metadata  -> flushes buffer (no dialogue)   |
+--------------------------------------------------------+
                           |
                           v
+--------------------------------------------------------+
|                 [ScriptScene] Array                    |
|   (Passed to AddAudition, Practice, Shoot, and Reader) |
+--------------------------------------------------------+
```

### 3.1 Inference Engine: `CoreMLScriptParserRunner`
An actor that provides zero-cost asynchronous predictions with graceful fallback:
```swift
actor CoreMLScriptParserRunner {
    static let shared = CoreMLScriptParserRunner()
    
    enum ElementClass: String {
        case sceneHeading = "scene_heading"
        case characterCue = "character_cue"
        case dialogue = "dialogue"
        case parenthetical = "parenthetical"
        case action = "action"
        case metadata = "metadata"
    }

    func classify(line: String) -> ElementClass?
    func parseScenes(from text: String, myRole: String) -> [ScriptScene]?
}
```

### 3.2 Dual-Layer Guardrail
If the model asset is not present or an anomalous string is encountered, `ScriptParser` falls back gracefully to deterministic heuristics, ensuring 100% backward compatibility and test stability.

---

## 4. Upstream Integration: Merging Commit `c3a1da4`

Alongside the Core ML model, we extract and adapt the upstream improvements from commit `c3a1da4`:
1. **`MediaStore.persist` Atomic Rollback:** Backs up superseded files before moving new recordings so a failed retake never deletes existing takes.
2. **`NoticeOCR` Enhancements:** Dynamic runtime language queries and 2x bounded enlargement pass for fine-print flyers.
3. **Audition Sides Revisions & Staging:** Preserves prior takes under `.previousSides`, tracks `sidesRevision`, and migrates reader audio.
4. **Stable Scene-Level Reader Cue Indexing:** Unifies cue IDs across recording, scrubbing, trimming, and multi-reader character setups.
5. **Audition List Filters:** Adds `isArchived` flag and `[Active] [Submitted] [Archived]` state to `AuditionsView`.
6. **In-Camera Recording Recovery:** Listens for `AVCaptureSession.wasInterruptedNotification` and presents `InterruptedTakeReviewSheet`.

---

## 5. Verification & Testing Strategy

1. **Model Accuracy & Unit Tests:**
   - All 21 existing tests in `ScriptParserTests.swift` pass.
   - New `testCoreMLScriptParserClassification()` verifying high accuracy across headings, cues, parentheticals, and dialogue.
   - Comprehensive persistence tests in `PersistenceTests.swift` verifying atomic rollback and sides revision migration.
2. **Design System & Architectural Compliance:**
   - Zero violations on `./scripts/lint-design-system.sh --strict`.
   - Strict 800-line ceiling maintained across all refactored and extracted files.
   - All xcodebuild tests succeed.
