# Offline Document & Notice Parser v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a 100% offline tiered parsing architecture pairing geometry-aware document acquisition (`PDF` bounds, `.fdx`, `.fountain`, `.docx`) and a contextual `< 5 MB` script classifier with a unified Cactus runtime (`Needle 3` `~29 MB` bundled base + optional HTTPS-downloaded `LFM2.5-VL-450M` `~380 MB` poster VLM) trained via Google Colab.

**Architecture:** Digital PDFs and scanned images converge into a shared normalized bounding-box `LayoutDocument` before splitting into non-generative `ScriptParser` paths (`< 0.25s` across 50 pages) and bounded notice extraction (`DocumentPageRouter` -> deterministic regex detectors -> `LFM2.5-VL-450M` or `Needle 3` under `CactusParserRunner` -> `NoticeMergeEngine` grounding merge). Native `.fdx` and `.fountain` bypass heuristics cleanly, while `ModelPackManager` delivers the VLM pack over background `URLSession` with SHA-256 atomic activation and `< 1 GB` inference RAM headroom on iPhone 11 (`4 GB` RAM).

**Tech Stack:** Swift 5.10 (`iOS 18.0+`), XcodeGen (`project.yml`), PDFKit / CoreGraphics, Vision OCR, Foundation `XMLParser`, Core ML, `swift-cactus` (`cactus-ios.xcframework`), Python / PyTorch / LoRA / `cactus-needle` / `cactus convert` on Google Colab, XCTest.

**Spec:** [docs/superpowers/specs/2026-11-13-offline-parser-v2-design.md](../specs/2026-11-13-offline-parser-v2-design.md)

## Global Constraints

- Target **iOS 18.0+** (`Swift 5.10`); zero cloud inference calls at runtime (`100%` offline document parsing).
- Tested down to **iPhone 11 (4 GB RAM)**: peak app footprint during VLM inference must stay `< 1.4 GB`; never keep `Needle 3` and `LFM2.5-VL-450M` resident simultaneously (`cactus_destroy` in `defer` after each run, resized flyer images `<= 768px`, `Needle 3` text slice `<= 1,024` tokens, `10s` per-document timeout).
- Keep base binary growth within `~40–60 MB`; host the `~350–400 MB` `LFM2.5-VL-450M` (`4-bit` CQ4) pack via direct HTTPS (`Hugging Face` / `GitHub Releases`) downloaded into `Library/Application Support/OneTake/Models/` (excluded from iCloud backup, compatible with personal team `W93H964P88`).
- Exact deterministic detectors own `submission_email`, `sides_link`, phone numbers, parsed dates, and explicit duration strings unless a VLM-recovered email passes strict syntax verification where OCR missed it.
- Keep all Swift files strictly `< 800` lines; regenerate `OneTake.xcodeproj` via `xcodegen generate` whenever files/packages change; pass `./scripts/lint-design-system.sh --strict` with `0` violations across all 9 checks.

## Review Focus

- **OCR misses low-contrast footer email (`ojas@mccc.in`) or VLM typos domain (`@mccc.in` vs `@mccc.com`):** Assert `NoticeMergeEngine` keeps deterministic regex email/URL intact when present, and only accepts VLM-only emails passing strict syntax + TLD checks (tested in Task 8).
- **Two-column commercial / casting breakdown PDF (`VIDEO | AUDIO` or role tables):** Assert `PDFGeometryExtractor` separates left/right X-columns instead of interleaving lines row-by-row like flat `PDFPage.string` (tested in Task 1).
- **Password-protected PDF or corrupted/truncated `.docx` / `.fdx`:** Assert structured `NoticeImportError` is thrown/returned cleanly and surfaced in UI instead of silently importing blank fields (tested in Task 2).
- **10 sequential flyer imports on 4 GB RAM iPhone 11 & corrupted/interrupted VLM download:** Assert `CactusParserRunner` frees weights after each call (`os_proc_available_memory` stable) and `ModelPackManager` rejects bad SHA-256 digests and falls back cleanly to `Needle 3` (tested in Tasks 7, 9, 10).
- **Multi-role packet cover page + numeric page numbers (`Pilgrimage_Casting_Sides.pdf`, `Grease+Audition+Sides+V2.pdf`):** Assert `DocumentPageRouter` + `ScriptElementClassifier` v2 isolate notice pages from dialogue pages and never emit bogus page-number or bio scenes (tested in Tasks 3 & 4).

---

### Task 1: Unified Geometry Extraction (`LayoutLine`, `LayoutDocument`, `PDFGeometryExtractor`)

**Files:**
- Create: `OneTake/Core/Services/PDFGeometryExtractor.swift`
- Modify: `OneTake/Core/Services/OCRLayoutReconstructor.swift:8-45`
- Modify: `OneTake/Core/Services/NoticeOCR.swift:547-600`
- Test: `OneTakeTests/GeometryAndFormatParserTests.swift`

**Interfaces:**
- Consumes: `PDFDocument` / `PDFPage`, `OCRLayoutReconstructor.TextBoundingBox`
- Produces: `LayoutLine` (`text: String`, `rect: CGRect`, `pageIndex: Int`, `estimatedIndent: CGFloat`), `LayoutDocument` (`pages: [[LayoutLine]]`, `reconstructedPages: [String]`, `fullText: String`), `PDFGeometryExtractor.extractLines(from page: PDFPage, pageIndex: Int) -> [LayoutLine]`, `NoticeOCR.extractLayoutDocument(fromFileAt url: URL) async throws -> LayoutDocument`

- [ ] **Step 1: Write the failing test**

Create `OneTakeTests/GeometryAndFormatParserTests.swift` with a programmatic two-column PDF fixture (`UIGraphicsPDFRenderer`) placing `"VIDEO: Close-up on actor"` on the left column and `"AUDIO: NARRATOR (V.O.) Welcome home."` on the right column at the same baseline Y:

```swift
func testPDFGeometryExtractorSeparatesTwoColumnsCleanly() throws {
    let url = try TestPDFFixture.makeTwoColumnPDF(
        leftLines: ["VIDEO:", "Close-up on coffee cup"],
        rightLines: ["AUDIO:", "ANNOUNCER: Start fresh."]
    )
    let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
    let lines = PDFGeometryExtractor.extractLines(from: page, pageIndex: 0)
    let reconstructed = OCRLayoutReconstructor.reconstruct(layoutLines: lines)
    XCTAssertTrue(reconstructed.contains("VIDEO:\nClose-up on coffee cup"))
    XCTAssertTrue(reconstructed.contains("AUDIO:\nANNOUNCER: Start fresh."))
    XCTAssertFalse(reconstructed.contains("VIDEO: AUDIO:"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/GeometryAndFormatParserTests`
Expected: FAIL (`PDFGeometryExtractor` and `LayoutDocument` undefined).

- [ ] **Step 3: Implement `PDFGeometryExtractor`, `LayoutLine`/`LayoutDocument`, and `NoticeOCR.extractLayoutDocument`**

1. Define `LayoutLine`, `LayoutDocument`, and `OCRLayoutReconstructor.reconstruct(layoutLines:)` in `OCRLayoutReconstructor.swift` (converting bottom-left / top-left coordinates consistently into normalized `[0, 1]` Vision orientation and computing `estimatedIndent` from `rect.minX`).
2. Implement `PDFGeometryExtractor.extractLines(from:pageIndex:)` in `PDFGeometryExtractor.swift` using `PDFPage.selection(for:)` / `selectionsByLine()` over `page.string` NSRanges to capture normalized line `CGRect`s in PDF page bounds, clustering broken line fragments within tight Y-tolerance before emitting `[LayoutLine]`. Fallback to `[LayoutLine]` from `page.string` only when `selectionsByLine()` yields nothing on selectable text.
3. Add `NoticeImportError` (`encryptedPDF`, `corruptDocument`, `unsupportedFormat`) and `NoticeOCR.extractLayoutDocument(fromFileAt:)` throwing `.encryptedPDF` when `doc.isEncrypted && doc.isLocked`. Preserve existing `extractDocument(fromFileAt:)` as a thin wrapper calling `extractLayoutDocument`. Keep each file `< 800` lines and run `xcodegen generate`.

- [ ] **Step 4: Run test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/GeometryAndFormatParserTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add OneTake.xcodeproj/project.pbxproj OneTake/Core/Services/PDFGeometryExtractor.swift OneTake/Core/Services/OCRLayoutReconstructor.swift OneTake/Core/Services/NoticeOCR.swift OneTakeTests/GeometryAndFormatParserTests.swift
git commit -m "feat(ocr): add geometry-aware PDF line extraction and LayoutDocument model"
```

---

### Task 2: Native `.fdx`, `.fountain`, and `.docx` Parsers + File Importer Support

**Files:**
- Create: `OneTake/Core/Services/StructuredDocumentParsers.swift`
- Modify: `OneTake/Core/Services/NoticeOCR.swift:547-600`
- Modify: `OneTake/Features/AddAudition/AddAuditionFlow.swift:66-95`
- Modify: `OneTake/Features/AddAudition/AddDraftSidesSheet.swift`
- Modify: `OneTake/Features/Practice/PracticeSetupView.swift`
- Test: `OneTakeTests/GeometryAndFormatParserTests.swift`

**Interfaces:**
- Consumes: `ZipArchive.extract(from:to:)`, `LayoutLine`, `LayoutDocument`, `ScriptScene`, `ScriptLine`
- Produces: `StructuredDocumentParsers.parseFDX(data: Data) throws -> ([ScriptScene], LayoutDocument)`, `StructuredDocumentParsers.parseFountain(text: String) -> ([ScriptScene], LayoutDocument)`, `StructuredDocumentParsers.parseDOCX(url: URL) throws -> LayoutDocument`

- [ ] **Step 1: Write the failing tests**

Add three tests to `OneTakeTests/GeometryAndFormatParserTests.swift` pinning `.fdx` XML scenes, `.fountain` forced character cues (`@McLane`), and corrupted `.docx` / `.fdx` error paths:

```swift
func testFDXParserExtractsExactScenesAndDialogue() throws {
    let fdx = """
    <?xml version="1.0" encoding="UTF-8" ?>
    <FinalDraft DocumentType="Script" Template="No" Version="5">
      <Content>
        <Paragraph Type="Scene Heading"><Text>INT. STUDIO - NIGHT</Text></Paragraph>
        <Paragraph Type="Character"><Text>SANDY</Text></Paragraph>
        <Paragraph Type="Parenthetical"><Text>(softly)</Text></Paragraph>
        <Paragraph Type="Dialogue"><Text>Wait for me.</Text></Paragraph>
      </Content>
    </FinalDraft>
    """.data(using: .utf8)!
    let (scenes, doc) = try StructuredDocumentParsers.parseFDX(data: fdx)
    XCTAssertEqual(scenes.count, 1)
    XCTAssertEqual(scenes[0].lines.first?.character, "SANDY")
    XCTAssertEqual(scenes[0].lines.first?.text, "Wait for me.")
    XCTAssertTrue(doc.fullText.contains("INT. STUDIO - NIGHT"))
}

func testCorruptDocxOrEncryptedPDFThrowsStructuredError() async {
    let corruptURL = FileManager.default.temporaryDirectory.appendingPathComponent("broken.docx")
    try? Data("not-a-zip".utf8).write(to: corruptURL)
    do {
        _ = try await NoticeOCR.extractLayoutDocument(fromFileAt: corruptURL)
        XCTFail("Expected NoticeImportError.corruptDocument")
    } catch let error as NoticeImportError {
        XCTAssertEqual(error, .corruptDocument)
    } catch {
        XCTFail("Unexpected error: \(error)")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/GeometryAndFormatParserTests`
Expected: FAIL (`StructuredDocumentParsers` undefined).

- [ ] **Step 3: Implement `StructuredDocumentParsers.swift`, wire into `NoticeOCR`, and add file UTTypes**

1. Implement `parseFDX(data:)` (`XMLParser` mapping `<Paragraph Type="...">`), `parseFountain(text:)` (supporting sluglines, `@CHARACTER`, `(parenthetical)`, `^` dual dialogue markers), and `parseDOCX(url:)` (unzip via `ZipArchive.extract` to temp dir, clean up with `defer`, parse `word/document.xml` extracting `<w:p>` runs and `<w:ind w:left="..."/>` normalized to `LayoutLine.estimatedIndent`, throwing `NoticeImportError.corruptDocument` on unzip/XML failure).
2. Wire `.fdx`, `.fountain`, and `.docx` switches into `NoticeOCR.extractLayoutDocument(fromFileAt:)`.
3. Update `.fileImporter` `allowedContentTypes` in `AddAuditionFlow.swift`, `AddDraftSidesSheet.swift`, and `PracticeSetupView.swift` to include `UTType(filenameExtension: "fdx")`, `UTType(filenameExtension: "fountain")`, and `UTType(filenameExtension: "docx")` (`UTType.data` fallback removed where typed), plus surface `NoticeImportError` alerts cleanly in `AddAuditionFlow`. Run `xcodegen generate` and `./scripts/lint-design-system.sh --strict`.

- [ ] **Step 4: Run tests to verify pass**

Run: `./scripts/lint-design-system.sh --strict && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/GeometryAndFormatParserTests`
Expected: lint exits `0` (`0` violations) and `GeometryAndFormatParserTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add OneTake.xcodeproj/project.pbxproj OneTake/Core/Services/StructuredDocumentParsers.swift OneTake/Core/Services/NoticeOCR.swift OneTake/Features/AddAudition/AddAuditionFlow.swift OneTake/Features/AddAudition/AddDraftSidesSheet.swift OneTake/Features/Practice/PracticeSetupView.swift OneTakeTests/GeometryAndFormatParserTests.swift
git commit -m "feat(import): support .fdx, .fountain, and .docx structured document parsing"
```

---

### Task 3: `DocumentPageRouter` (Notice vs Sides Page Classification & Bounded Slice)

**Files:**
- Create: `OneTake/Core/Services/DocumentPageRouter.swift`
- Modify: `OneTake/Core/Services/NoticeParser.swift:192-215`
- Test: `OneTakeTests/RealPDFParserTests.swift`

**Interfaces:**
- Consumes: `LayoutDocument` (`pages`, `reconstructedPages`)
- Produces: `RoutedDocument` (`noticeTextSlice: String`, `noticePages: [Int]`, `sidesPages: [Int]`, `sidesLayoutLines: [LayoutLine]`), `DocumentPageRouter.route(_ document: LayoutDocument, tokenBudget: Int = 900) -> RoutedDocument`

- [ ] **Step 1: Write the failing test**

Add a test in `OneTakeTests/RealPDFParserTests.swift` using bundled `Pilgrimage_Casting_Sides.pdf` and `Grease+Audition+Sides+V2.pdf` asserting page routing separates cover/notice pages from dialogue pages and stays within Needle’s `<= 1,024`-token budget:

```swift
func testDocumentPageRouterSeparatesNoticeAndSidesPagesWithinBudget() throws {
    let url = try XCTUnwrap(Bundle(for: RealPDFParserTests.self).url(forResource: "Grease+Audition+Sides+V2", withExtension: "pdf"))
    let doc = PDFDocument(url: url)!
    let pages = (0..<doc.pageCount).map { PDFGeometryExtractor.extractLines(from: doc.page(at: $0)!, pageIndex: $0) }
    let layoutDoc = LayoutDocument(pages: pages)
    let routed = DocumentPageRouter.route(layoutDoc, tokenBudget: 900)
    XCTAssertTrue(routed.noticePages.contains(0))
    XCTAssertFalse(routed.sidesPages.isEmpty)
    XCTAssertLessThanOrEqual(routed.noticeTextSlice.split(whereSeparator: \.isWhitespace).count, 750)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/RealPDFParserTests`
Expected: FAIL (`DocumentPageRouter` undefined).

- [ ] **Step 3: Implement `DocumentPageRouter` and update `NoticeParser` packet slicing**

Score each page on dialogue cue ratio + sluglines vs notice keywords (`SLATE`, `SUBMISSION`, `DEADLINE`, emails/URLs, character bio lists) to assign `.notice` or `.sides` (`<= 1,024` approx token budget constructed by preserving top front-matter + footer contact blocks + requirement blocks). Wire `DocumentPageRouter` into `NoticeParser.parse(_:pages:sourceDocuments:)` and run `xcodegen generate`.

- [ ] **Step 4: Run tests to verify pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/RealPDFParserTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add OneTake.xcodeproj/project.pbxproj OneTake/Core/Services/DocumentPageRouter.swift OneTake/Core/Services/NoticeParser.swift OneTakeTests/RealPDFParserTests.swift
git commit -m "feat(parser): add DocumentPageRouter to separate notice and sides slices"
```

---

### Task 4: Contextual `ScriptElementClassifier` v2 & Geometry-Aware `ScriptParser`

**Files:**
- Create: `scripts/colab/train_script_classifier_v2.py`
- Modify: `OneTake/Core/Models/CoreMLScriptParserRunner.swift:39-120`
- Modify: `OneTake/Core/Models/ScriptParser.swift:71-110`
- Update: `OneTake/Core/Models/ScriptElementClassifier.mlmodel`
- Test: `OneTakeTests/ScriptParserStressTests.swift`

**Interfaces:**
- Consumes: `[LayoutLine]` (with normalized `estimatedIndent`), existing `ScriptElementClass`
- Produces: `CoreMLScriptParserRunner.classifyContextual(lines: [LayoutLine]) -> [ScriptElementClass?]`, `ScriptParser.parseScenes(from layoutLines: [LayoutLine], myRole: String) -> [ScriptScene]`

- [ ] **Step 1: Write the failing test**

Add a geometry-context test to `OneTakeTests/ScriptParserStressTests.swift` checking that an action block containing an uppercase word followed by left-aligned narration stays `.action`, whereas a centered/indented cue (`estimatedIndent >= 0.30`) is parsed cleanly as `.characterCue`:

```swift
func testContextualScriptParserUsesIndentAndNeighborContext() {
    let lines = [
        LayoutLine(text: "INT. APARTMENT - NIGHT", rect: CGRect(x: 0.15, y: 0.85, width: 0.4, height: 0.02), pageIndex: 0),
        LayoutLine(text: "PAGE 4", rect: CGRect(x: 0.85, y: 0.95, width: 0.08, height: 0.015), pageIndex: 0),
        LayoutLine(text: "MAYA picks up the phone.", rect: CGRect(x: 0.15, y: 0.78, width: 0.5, height: 0.02), pageIndex: 0),
        LayoutLine(text: "MAYA", rect: CGRect(x: 0.42, y: 0.72, width: 0.10, height: 0.02), pageIndex: 0),
        LayoutLine(text: "Are you still awake?", rect: CGRect(x: 0.28, y: 0.69, width: 0.35, height: 0.02), pageIndex: 0)
    ]
    let scenes = ScriptParser.parseScenes(from: lines, myRole: "Maya")
    XCTAssertEqual(scenes.count, 1)
    XCTAssertEqual(scenes[0].lines.count, 1)
    XCTAssertEqual(scenes[0].lines[0].character, "MAYA")
    XCTAssertEqual(scenes[0].lines[0].text, "Are you still awake?")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/ScriptParserStressTests`
Expected: FAIL (`parseScenes(from: [LayoutLine], myRole:)` undefined).

- [ ] **Step 3: Implement Colab trainer `train_script_classifier_v2.py` + contextual Swift integration**

1. Write `scripts/colab/train_script_classifier_v2.py` to generate 25k screenplay/stage/commercial/multi-role lines with layout features (`left_x`, `width_ratio`, `blank_before`, `blank_after`, `uppercase_ratio`, `prev_class`, tokenized text) and export a `< 5 MB` tabular/text hybrid `CoreML` model (`ScriptElementClassifierV2.mlmodel`) alongside falling back gracefully to `ScriptElementClassifier.mlmodel` if v2 asset isn't regenerated yet.
2. Add `classifyContextual(lines: [LayoutLine]) -> [ScriptElementClass?]` in `CoreMLScriptParserRunner.swift` and `ScriptParser.parseScenes(from layoutLines: [LayoutLine], myRole: String)` in `ScriptParser.swift`, reusing existing scene-heading / page-number / `(CONT'D)` guardrails cleanly without duplicating logic (`parseScenes(from text:)` delegates via synthetic `LayoutLine` wrapping so existing behavior stays intact).

- [ ] **Step 4: Run tests to verify pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/ScriptParserStressTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/colab/train_script_classifier_v2.py OneTake/Core/Models/CoreMLScriptParserRunner.swift OneTake/Core/Models/ScriptParser.swift OneTakeTests/ScriptParserStressTests.swift
git commit -m "feat(script): add contextual geometry-aware script classification"
```

---

### Task 5: Google Colab Dataset & Synthetic Casting Poster Generator (`scripts/colab/`)

**Files:**
- Create: `scripts/colab/build_offline_v2_corpus.py`
- Create: `scripts/colab/eval_offline_v2.py`
- Modify: `scripts/evaluate_field_accuracy.py:1-34`

**Interfaces:**
- Consumes: Repo fixtures (`OneTakeTests/Resources/flyer_test.jpg`, `Grease+Audition+Sides+V2.pdf`, `Pilgrimage_Casting_Sides.pdf`)
- Produces: JSONL training/eval records (`train_vlm.jsonl`, `eval_vlm.jsonl`, `train_needle.jsonl`, `eval_needle.jsonl`) matching canonical `SemanticNoticePayload` keys, runnable offline accuracy harness `eval_offline_v2.py`

- [ ] **Step 1: Write unit verification test for corpus schema & evaluator**

Add pytest/Python `unittest` checks inside `scripts/colab/test_corpus_pipeline.py` verifying every generated row conforms to all 18 `SemanticNoticePayload` keys, Needle slices stay `<= 1,024` tokens (measured by whitespace/subword estimate `<= 750` words), and `eval_offline_v2.py` scores exact email match (`1.0`) vs role/ask F1 accurately without fabricating scores.

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest scripts/colab/test_corpus_pipeline.py`
Expected: FAIL (`No module named 'scripts.colab.build_offline_v2_corpus'`).

- [ ] **Step 3: Implement synthetic casting flyer renderer & Colab dataset builder + evaluator**

1. Implement `scripts/colab/build_offline_v2_corpus.py` generating `5,000` training + `500` adversarial held-out posters (`768x960` PNGs via `Pillow`) combining random layouts (two-column grids, watermark clapperboards, white-on-tan low-contrast footer emails, Hindi/Punjabi/English character breakdowns, agency logos distinct from submission emails) paired with both image paths (for `LFM2.5-VL-450M`) and simulated OCR noise text (for `Needle 3`).
2. Implement `scripts/colab/eval_offline_v2.py` scoring `submission_email` / `sides_link` exact match and token-level F1 across `role`, `project`, `casting_office`, `asks`, and `location`. Update `scripts/evaluate_field_accuracy.py` header/CLI cleanly to forward `--offline-eval` if passed.

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest scripts/colab/test_corpus_pipeline.py`
Expected: PASS (exit `0`)

- [ ] **Step 5: Commit**

```bash
git add scripts/colab/build_offline_v2_corpus.py scripts/colab/eval_offline_v2.py scripts/colab/test_corpus_pipeline.py scripts/evaluate_field_accuracy.py
git commit -m "feat(colab): add synthetic casting poster corpus generator and offline evaluator"
```

---

### Task 6: Google Colab LoRA Trainers & Cactus Quantization (`Needle 3` + `LFM2.5-VL-450M`)

**Files:**
- Create: `scripts/colab/train_needle3_lora.py`
- Create: `scripts/colab/train_lfm25_vl_lora.py`
- Create: `scripts/colab/publish_release.py`
- Modify: `scripts/colab/test_corpus_pipeline.py`

**Interfaces:**
- Consumes: `train_needle.jsonl`, `eval_needle.jsonl`, `train_vlm.jsonl`, `eval_vlm.jsonl` from Task 5; `eval_offline_v2.py`
- Produces: Quantized Cactus `needle3-onetake-cq2` (`~29 MB`), `lfm2.5-vl-450m-onetake-cq4` (`~350–400 MB`), `manifest.json` (`modelId`, `version`, `downloadURL`, `byteSize`, `sha256`, `minAppVersion`) verified against the held-out gate (`>= 98%` verified email/URL accuracy post-merge, `>= 90%` F1 on core fields)

- [ ] **Step 1: Write the failing smoke test for manifest & CLI config**

Extend `scripts/colab/test_corpus_pipeline.py` testing `--dry-run` config validation in `train_needle3_lora.py`, `train_lfm25_vl_lora.py`, and SHA-256 `manifest.json` generation in `publish_release.py` (failing if held-out accuracy metrics fall below thresholds).

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest scripts/colab/test_corpus_pipeline.py`
Expected: FAIL (`train_needle3_lora`, `publish_release` missing).

- [ ] **Step 3: Implement Colab training, `cactus convert`, and release manifest scripts**

1. `train_needle3_lora.py`: LoRA fine-tunes `Needle 3` via `cactus-needle[train]`, exports via `cactus convert ... --lora ... --bits 2`, runs held-out `eval_offline_v2.py`.
2. `train_lfm25_vl_lora.py`: LoRA fine-tunes `LiquidAI/LFM2.5-VL-450M` (or fallback `LiquidAI/LFM2-VL-450M`) on `(poster_image, schema_prompt) -> JSON` on Colab L4/A100 GPU, merges & quantizes via `cactus convert LiquidAI/LFM2.5-VL-450M ... --lora ... --bits 4`.
3. `publish_release.py`: Computes SHA-256, checks accuracy gate (`email >= 0.98`, `core_f1 >= 0.90`), packages zipped CQ4 weights + `manifest.json` for Hugging Face Hub (`huggingface_hub`) or GitHub Release (`gh release upload`).

- [ ] **Step 4: Run test to verify pass**

Run: `python3 -m unittest scripts/colab/test_corpus_pipeline.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/colab/train_needle3_lora.py scripts/colab/train_lfm25_vl_lora.py scripts/colab/publish_release.py scripts/colab/test_corpus_pipeline.py
git commit -m "feat(colab): add Needle 3 CQ2 and LFM2.5-VL-450M CQ4 LoRA training and release scripts"
```

---

### Task 7: `CactusParserRunner` Integration (`swift-cactus` + Single-Resident Memory Contract)

**Files:**
- Modify: `project.yml` (add `swift-cactus` / `cactus-ios.xcframework` dependency and bundled `needle3-onetake-cq2` resource)
- Create: `OneTake/Core/Models/SemanticNoticePayload.swift`
- Create: `OneTake/Core/Models/CactusParserRunner.swift`
- Modify: `OneTake/Core/Models/CoreMLParserRunner.swift` (deprecate/forward cleanly or retire unpopulated runner once replaced)
- Test: `OneTakeTests/CactusParserRunnerTests.swift`

**Interfaces:**
- Consumes: `swift-cactus` (`cactus_init`, completion/vision call, `cactus_destroy`), bundled `Needle 3` resource, optional downloaded VLM directory URL from `ModelPackManager`
- Produces: `SemanticNoticePayload: Codable, Sendable`, `CactusParserRunner.shared.extractNotice(fromText: String) async -> SemanticNoticePayload?`, `CactusParserRunner.shared.extractNotice(fromImage: UIImage, modelDirectory: URL) async -> SemanticNoticePayload?`

- [ ] **Step 1: Write the failing unit tests**

Create `OneTakeTests/CactusParserRunnerTests.swift` testing `SemanticNoticePayload` JSON decoding (including partial nulls), image downscaling helper (`<= 768px` max edge), `Needle 3` token truncation (`<= 1,024` tokens), and serialized single-resident teardown contract (`activeModelKind == nil` after `extractNotice` finishes or times out).

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/CactusParserRunnerTests`
Expected: FAIL (`SemanticNoticePayload` and `CactusParserRunner` undefined).

- [ ] **Step 3: Wire `swift-cactus` and implement `SemanticNoticePayload` + `CactusParserRunner`**

1. Add `swift-cactus` package (or local `cactus-ios.xcframework`) to `project.yml` and regenerate `OneTake.xcodeproj`.
2. Define `SemanticNoticePayload` matching all 18 canonical schema fields cleanly.
3. Implement `actor CactusParserRunner` enforcing:
   - Single loaded engine slot (`activeKind: ModelKind? = nil`) always destroyed via `defer` before returning or switching between `Needle 3` and `LFM2.5-VL-450M`.
   - Poster resize helper scaling longest edge `<= 768px`.
   - `withThrowingTaskGroup` `10s` deadline returning `nil` on timeout/cancellation without crashing.
   - Graceful `nil` return if bundled `Needle 3` artifact isn't dropped in yet during local builds (never crash `Bundle.main` lookup).

- [ ] **Step 4: Run test to verify pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/CactusParserRunnerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add project.yml OneTake.xcodeproj/project.pbxproj OneTake/Core/Models/SemanticNoticePayload.swift OneTake/Core/Models/CactusParserRunner.swift OneTake/Core/Models/CoreMLParserRunner.swift OneTakeTests/CactusParserRunnerTests.swift
git commit -m "feat(ml): add CactusParserRunner and SemanticNoticePayload with strict teardown"
```

---

### Task 8: `NoticeMergeEngine` & End-to-End Parsing Pipeline Wiring

**Files:**
- Create: `OneTake/Core/Services/NoticeMergeEngine.swift`
- Modify: `OneTake/Core/Services/NoticeParser.swift:190-240`
- Modify: `OneTake/Core/Services/OnDeviceIntelligence.swift:249-370`
- Modify: `OneTake/Features/AddAudition/AddAuditionFlow.swift:30-134`
- Test: `OneTakeTests/NoticeMergeEngineTests.swift`
- Test: `OneTakeTests/ScriptParserStressTests.swift`

**Interfaces:**
- Consumes: `NoticeParser.Draft`, `SemanticNoticePayload`, `LayoutDocument`, `DocumentPageRouter`, `CactusParserRunner`
- Produces: `NoticeMergeEngine.merge(deterministic: NoticeParser.Draft, semantic: SemanticNoticePayload?, sourceText: String) -> NoticeParser.Draft`, `NoticeParser.parseAsync(_: LayoutDocument, posterImage: UIImage?, sourceDocuments: [AuditionSource]) async -> Draft`

- [ ] **Step 1: Write the failing grounding merge tests**

Create `OneTakeTests/NoticeMergeEngineTests.swift` testing both critical edge cases from Review Focus:
1. Deterministic email (`ojas@mccc.in`) wins even when quantized `SemanticNoticePayload.submissionEmail` hallucinates a wrong domain (`ojas@mccc.com`).
2. When OCR missed the email (`deterministic.destinationDetail == nil`) and VLM recovers a valid `nupur@mccc.in`, strict syntax validation accepts it; invalid/nonsense strings are rejected.
3. Grounding rules block ungrounded `project` / `castingOffice` (like `"Casting Sides"`) and respect open-role notices.

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/NoticeMergeEngineTests`
Expected: FAIL (`NoticeMergeEngine` undefined).

- [ ] **Step 3: Implement `NoticeMergeEngine` and wire sequential OCR -> Cactus flow**

1. Implement `NoticeMergeEngine.merge(deterministic:semantic:sourceText:)` using strict email/URL validators + existing `OnDeviceIntelligence` grounding checks (`isGroundedProjectTitle`, `isGroundedCastingOffice`, `isGroundedNoticeValue`).
2. Add `NoticeParser.parseAsync(_: LayoutDocument, posterImage: UIImage?, sourceDocuments:)` ensuring:
   - Native `.fdx`/`.fountain` pre-parsed `[ScriptScene]` is carried through when present.
   - Vision OCR finishes **before** calling `CactusParserRunner` so OCR buffers and VLM weights never overlap in RAM.
   - `AddAuditionFlow` passes the photo/scan `UIImage` (resized cleanly) and `LayoutDocument` into `NoticeParser.parseAsync`.

- [ ] **Step 4: Run tests to verify pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/NoticeMergeEngineTests -only-testing:OneTakeTests/ScriptParserStressTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add OneTake.xcodeproj/project.pbxproj OneTake/Core/Services/NoticeMergeEngine.swift OneTake/Core/Services/NoticeParser.swift OneTake/Core/Services/OnDeviceIntelligence.swift OneTake/Features/AddAudition/AddAuditionFlow.swift OneTakeTests/NoticeMergeEngineTests.swift
git commit -m "feat(parser): wire NoticeMergeEngine grounding and sequential OCR/VLM pipeline"
```

---

### Task 9: `ModelPackManager` (Direct HTTPS Delivery, SHA-256 & Profile Settings UI)

**Files:**
- Create: `OneTake/Core/Services/ModelPackManager.swift`
- Modify: `OneTake/Features/Profile/ProfileView.swift:28-45`
- Modify: `OneTake/Features/AddAudition/NoticeReviewView.swift` (optional non-blocking offline pack tip)
- Test: `OneTakeTests/ModelPackManagerTests.swift`

**Interfaces:**
- Consumes: `URLSession`, `CryptoKit.SHA256`, `ModelPackManifest` (`modelId`, `version`, `downloadURL`, `byteSize`, `sha256`, `minAppVersion`)
- Produces: `ModelPackManager.shared.state` (`notInstalled`, `downloading(progress: Double)`, `verifying`, `installed(URL, version: String)`, `failed(String)`), `installPack()`, `deletePack()`, `activeModelDirectoryURL() -> URL?`

- [ ] **Step 1: Write the failing pack integrity & rollback tests**

Create `OneTakeTests/ModelPackManagerTests.swift` verifying:
- `SHA-256` mismatch leaves prior `installed` directory untouched and sets state to `.failed`.
- Valid mock archive/manifest atomically promotes temp folder to `current/`, sets `.isExcludedFromBackupKey = true`, and `deletePack()` removes weights cleanly.

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/ModelPackManagerTests`
Expected: FAIL (`ModelPackManager` undefined).

- [ ] **Step 3: Implement `ModelPackManager` and Profile Settings UI**

1. Implement `@Observable ModelPackManager` storing packs in `Library/Application Support/OneTake/Models/lfm2.5-vl-450m/` (`URLResourceValues.isExcludedFromBackup = true`), streaming background `URLSession` download progress, checking `CryptoKit.SHA256`, unzipping via `ZipArchive.extract` if archived, and atomically swapping into `current/`.
2. Add an "Offline AI Poster Pack" section row/card in `ProfileView.swift` using strictly OneTakeUI design tokens (`OT`, `OTSpace`, `OTRadius`, no raw lint violations) showing Download (`~380 MB`) / Progress bar / Ready + Remove controls, plus an optional non-blocking banner in `NoticeReviewView.swift` when a poster was scanned without the VLM pack. Run `xcodegen generate` and `./scripts/lint-design-system.sh --strict`.

- [ ] **Step 4: Run tests to verify pass**

Run: `./scripts/lint-design-system.sh --strict && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04" -only-testing:OneTakeTests/ModelPackManagerTests`
Expected: lint exits `0` (`0` violations) and `ModelPackManagerTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add OneTake.xcodeproj/project.pbxproj OneTake/Core/Services/ModelPackManager.swift OneTake/Features/Profile/ProfileView.swift OneTake/Features/AddAudition/NoticeReviewView.swift OneTakeTests/ModelPackManagerTests.swift
git commit -m "feat(models): add ModelPackManager HTTPS downloader, SHA-256 check, and Profile UI"
```

---

### Task 10: Physical Device Memory, Latency & End-to-End Verification Gate (`iPhone 11`)

**Files:**
- Create: `OneTakeTests/OfflineParserPerformanceTests.swift`

**Interfaces:**
- Consumes: Real bundled fixtures (`flyer_test.jpg`, `Grease+Audition+Sides+V2.pdf`, `Pilgrimage_Casting_Sides.pdf`), `os_proc_available_memory()`, `CactusParserRunner`, `NoticeOCR`, `ScriptParser`
- Produces: Repeatable device/simulator benchmark tests verifying latency & memory ceilings on real hardware

- [ ] **Step 1: Write performance & 10x sequential stress test**

Create `OneTakeTests/OfflineParserPerformanceTests.swift` asserting:
1. 50-page digital script parse completes in `< 0.25s`.
2. Running 10 consecutive `flyer_test.jpg` parses keeps peak footprint safe (when `Needle` / `LFM2.5-VL` packs are present on device, `CactusParserRunner` releases active memory between iterations and stays `< 1.4 GB` / above safe `os_proc_available_memory()` floor, and every VLM run completes `< 10s`).

- [ ] **Step 2: Run full verification gates (Lint + Line Count + Simulator + Physical iPhone)**

Run on Simulator:
```bash
./scripts/lint-design-system.sh --strict
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=126DE36B-2481-4B61-B1F1-8BB496ADCE04"
```
Run targeted parser/stress/perf suite on physical **`Avinash’s iPhone`** (`00008030-000951843C33C02E`):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "id=00008030-000951843C33C02E" -only-testing:OneTakeTests/GeometryAndFormatParserTests -only-testing:OneTakeTests/RealPDFParserTests -only-testing:OneTakeTests/ScriptParserStressTests -only-testing:OneTakeTests/CactusParserRunnerTests -only-testing:OneTakeTests/NoticeMergeEngineTests -only-testing:OneTakeTests/ModelPackManagerTests -only-testing:OneTakeTests/OfflineParserPerformanceTests -allowProvisioningUpdates
```
Expected: `./scripts/lint-design-system.sh --strict` exits `0`, every Swift file `< 800` lines, and all test suites pass (`** TEST SUCCEEDED **`).

- [ ] **Step 3: Commit**

```bash
git add OneTake.xcodeproj/project.pbxproj OneTakeTests/OfflineParserPerformanceTests.swift
git commit -m "test(parser): add offline parser v2 performance and 4GB RAM sequential stress tests"
```
