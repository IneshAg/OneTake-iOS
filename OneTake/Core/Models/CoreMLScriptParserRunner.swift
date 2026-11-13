import Foundation
import CoreGraphics
import CoreML
import NaturalLanguage

/// Screenplay element semantic classification categories predicted by `ScriptElementClassifier`.
public enum ScriptElementClass: String, CaseIterable, Sendable {
    case sceneHeading = "scene_heading"
    case characterCue = "character_cue"
    case dialogue = "dialogue"
    case parenthetical = "parenthetical"
    case action = "action"
    case metadata = "metadata"
}

public typealias ElementClass = ScriptElementClass

/// Thread-safe cached storage for the underlying v1 `NLModel` and optional v2 contextual `MLModel`.
private final class ClassifierStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedV1Model: NLModel?
    private var cachedV2Model: MLModel?
    private var didAttemptLoad = false

    func v1Model() -> NLModel? {
        loadIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return cachedV1Model
    }

    func v2Model() -> MLModel? {
        loadIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return cachedV2Model
    }

    private func loadIfNeeded() {
        lock.lock()
        let needsLoad = !didAttemptLoad
        lock.unlock()
        guard needsLoad else { return }

        let v2 = CoreMLScriptParserRunner.resolveAndLoadV2Model()
        let v1 = CoreMLScriptParserRunner.resolveAndLoadV1Model()

        lock.lock()
        if !didAttemptLoad {
            cachedV2Model = v2
            cachedV1Model = v1
            didAttemptLoad = true
        }
        lock.unlock()
    }
}

private final class _ScriptParserRunnerBundleToken {}

/// Native Core ML runner for on-device screenplay element classification.
/// Evaluates script lines into sluglines, cues, dialogue, parentheticals, action, and metadata
/// in <1ms latency on the Apple Neural Engine and CPU.
public actor CoreMLScriptParserRunner {
    public static let shared = CoreMLScriptParserRunner()

    private static let v1ModelName = "ScriptElementClassifier"
    private static let v2ModelName = "ScriptElementClassifierV2"
    private static let v2VocabSize = 4096
    private static let v2MaxTokens = 24
    private static let v2LayoutFeatureCount = 13

    private let storage = ClassifierStorage()

    /// Returns true if either `ScriptElementClassifierV2` or `ScriptElementClassifier` is available on device.
    public nonisolated var isAvailable: Bool {
        storage.v2Model() != nil || storage.v1Model() != nil
    }

    /// Returns true when the contextual hybrid v2 `.mlmodel` asset is bundled and active.
    public nonisolated var isV2Available: Bool {
        storage.v2Model() != nil
    }

    /// Synchronous, thread-safe single-line classification.
    public nonisolated func classifySync(line: String) -> ScriptElementClass? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let nlModel = storage.v1Model(), let label = nlModel.predictedLabel(for: line) {
            return ScriptElementClass(rawValue: label)
        }
        if storage.v2Model() != nil {
            let synthetic = LayoutLine(
                text: trimmed,
                rect: CGRect(x: 0.08, y: 0.5, width: 0.84, height: 0.02),
                pageIndex: 0
            )
            return classifyContextual(lines: [synthetic]).first ?? nil
        }
        return nil
    }

    /// Asynchronous single-line classification on the actor.
    public func classify(line: String) async -> ScriptElementClass? {
        classifySync(line: line)
    }

    /// Classifies an array of raw script lines in order.
    public func classify(lines: [String]) async -> [ScriptElementClass?] {
        lines.map { classifySync(line: $0) }
    }

    /// Classifies ordered `LayoutLine` elements using normalized indentation, vertical spacing,
    /// character casing, and prior-line class context. Uses `ScriptElementClassifierV2` when bundled,
    /// falling back cleanly to `ScriptElementClassifier` + deterministic contextual geometry rules.
    nonisolated func classifyContextual(lines: [LayoutLine]) -> [ScriptElementClass?] {
        guard !lines.isEmpty else { return [] }

        let v2Model = storage.v2Model()
        let v1Model = storage.v1Model()

        var results: [ScriptElementClass?] = []
        results.reserveCapacity(lines.count)
        var prevClass: ScriptElementClass?

        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                results.append(nil)
                continue
            }

            let leftX = min(max(Double(line.estimatedIndent), 0.0), 1.0)
            let widthRatio = min(max(Double(line.rect.width), 0.0), 1.0)
            let blankBefore = hasBlankGapBefore(index: index, in: lines)
            let blankAfter = hasBlankGapAfter(index: index, in: lines)
            let uppercaseRatio = Self.computeUppercaseRatio(trimmed)

            let predicted: ScriptElementClass?
            if let v2Model,
               let v2Class = predictWithV2(
                   model: v2Model,
                   text: trimmed,
                   leftX: leftX,
                   widthRatio: widthRatio,
                   blankBefore: blankBefore,
                   blankAfter: blankAfter,
                   uppercaseRatio: uppercaseRatio,
                   lineLength: trimmed.count,
                   prevClass: prevClass
               ) {
                predicted = v2Class
            } else {
                let baseClass = v1Model?.predictedLabel(for: trimmed).flatMap(ScriptElementClass.init(rawValue:))
                predicted = resolveContextualFallback(
                    trimmed: trimmed,
                    leftX: leftX,
                    widthRatio: widthRatio,
                    blankBefore: blankBefore,
                    blankAfter: blankAfter,
                    uppercaseRatio: uppercaseRatio,
                    lineLength: trimmed.count,
                    baseClass: baseClass,
                    prevClass: prevClass
                )
            }

            results.append(predicted)
            if let predicted, !(predicted == .metadata && Self.isPageMetadataLine(trimmed)) {
                prevClass = predicted
            }
        }

        return results
    }

    // MARK: - V2 Hybrid Inference & Tokenization

    private nonisolated func predictWithV2(
        model: MLModel,
        text: String,
        leftX: Double,
        widthRatio: Double,
        blankBefore: Bool,
        blankAfter: Bool,
        uppercaseRatio: Double,
        lineLength: Int,
        prevClass: ScriptElementClass?
    ) -> ScriptElementClass? {
        guard let tokenArray = try? MLMultiArray(shape: [1, NSNumber(value: Self.v2MaxTokens)], dataType: .int32),
              let layoutArray = try? MLMultiArray(shape: [1, NSNumber(value: Self.v2LayoutFeatureCount)], dataType: .float32) else {
            return nil
        }

        let tokenIDs = Self.tokenizeForV2(text)
        let tokenPtr = tokenArray.dataPointer.assumingMemoryBound(to: Int32.self)
        for i in 0..<Self.v2MaxTokens {
            tokenPtr[i] = tokenIDs[i]
        }

        let layoutPtr = layoutArray.dataPointer.assumingMemoryBound(to: Float32.self)
        layoutPtr[0] = Float32(leftX)
        layoutPtr[1] = Float32(widthRatio)
        layoutPtr[2] = blankBefore ? 1.0 : 0.0
        layoutPtr[3] = blankAfter ? 1.0 : 0.0
        layoutPtr[4] = Float32(uppercaseRatio)
        layoutPtr[5] = Float32(Double(min(lineLength, 120)) / 120.0)

        let prevIndex: Int
        switch prevClass {
        case .none: prevIndex = 0
        case .sceneHeading: prevIndex = 1
        case .characterCue: prevIndex = 2
        case .dialogue: prevIndex = 3
        case .parenthetical: prevIndex = 4
        case .action: prevIndex = 5
        case .metadata: prevIndex = 6
        }
        for offset in 0..<7 {
            layoutPtr[6 + offset] = (offset == prevIndex) ? 1.0 : 0.0
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [
            "text_tokens": MLFeatureValue(multiArray: tokenArray),
            "layout_features": MLFeatureValue(multiArray: layoutArray)
        ]),
              let output = try? model.prediction(from: provider),
              let label = output.featureValue(for: "classLabel")?.stringValue else {
            return nil
        }
        return ScriptElementClass(rawValue: label)
    }

    /// Deterministic word + char-trigram FNV-1a tokenizer matching `train_script_classifier_v2.py`.
    static func tokenizeForV2(_ text: String) -> [Int32] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else {
            return Array(repeating: 0, count: v2MaxTokens)
        }

        var rawWords: [String] = []
        var current = ""
        let punctuationTokens: Set<Character> = ["(", ")", ":", ".", "-", "!", "?", "/"]

        for ch in cleaned {
            if ch.isASCII && (ch.isLetter || ch.isNumber || ch == "'") {
                current.append(ch)
            } else {
                if !current.isEmpty {
                    rawWords.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                if punctuationTokens.contains(ch) {
                    rawWords.append(String(ch))
                }
            }
        }
        if !current.isEmpty {
            rawWords.append(current)
        }

        var featureTokens: [String] = []
        featureTokens.reserveCapacity(v2MaxTokens)
        for word in rawWords.prefix(12) {
            featureTokens.append("w:\(word)")
            if word.count >= 3 && word.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                let chars = Array(word)
                for i in 0...(chars.count - 3) {
                    featureTokens.append("c:\(String(chars[i..<(i + 3)]))")
                }
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") {
            featureTokens.append("s:end_period_bang")
        }
        if trimmed.hasSuffix("?") {
            featureTokens.append("s:end_question")
        }
        if trimmed.hasSuffix(":") {
            featureTokens.append("s:end_colon")
        }
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            featureTokens.append("s:parens")
        }

        var ids = Array(repeating: Int32(0), count: v2MaxTokens)
        let mod = UInt32(v2VocabSize - 1)
        for (idx, tok) in featureTokens.prefix(v2MaxTokens).enumerated() {
            ids[idx] = Int32((fnv1a32(tok) % mod) + 1)
        }
        return ids
    }

    private static func fnv1a32(_ text: String) -> UInt32 {
        var hash: UInt32 = 0x811C9DC5
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x01000193
        }
        return hash
    }

    // MARK: - V1 + Geometric Contextual Fallback

    private nonisolated func resolveContextualFallback(
        trimmed: String,
        leftX: Double,
        widthRatio: Double,
        blankBefore: Bool,
        blankAfter: Bool,
        uppercaseRatio: Double,
        lineLength: Int,
        baseClass: ScriptElementClass?,
        prevClass: ScriptElementClass?
    ) -> ScriptElementClass? {
        if Self.isPageMetadataLine(trimmed) {
            return .metadata
        }

        if ScriptParser.isSceneHeading(trimmed) {
            return .sceneHeading
        }

        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            return .parenthetical
        }
        if baseClass == .parenthetical,
           leftX >= 0.18,
           widthRatio <= 0.50,
           (prevClass == .characterCue || prevClass == .dialogue || prevClass == .parenthetical) {
            return .parenthetical
        }

        let plausibleCue = ScriptParser.isPlausibleCueName(trimmed)
        let hasCueIndent = leftX >= 0.30 && widthRatio <= 0.45

        if hasCueIndent,
           plausibleCue,
           !trimmed.hasSuffix("."),
           !trimmed.hasSuffix("!"),
           !trimmed.hasSuffix("?"),
           (uppercaseRatio >= 0.80 || !blankAfter) {
            return .characterCue
        }

        // Left-aligned geometric action disambiguation (e.g. "MAYA picks up the phone." at x=0.15)
        if leftX < 0.22, widthRatio < 0.80, !plausibleCue {
            if (trimmed.hasSuffix(".") || trimmed.hasSuffix("!"))
                && (prevClass == nil || prevClass == .sceneHeading || prevClass == .action || prevClass == .metadata || (prevClass == .dialogue && blankBefore)) {
                return .action
            }
            if uppercaseRatio < 0.60,
               !trimmed.hasSuffix("?"),
               (prevClass == .sceneHeading || prevClass == .action || (prevClass == .dialogue && blankBefore)) {
                return .action
            }
        }

        if (prevClass == .characterCue || prevClass == .parenthetical), !plausibleCue {
            return .dialogue
        }

        if prevClass == .dialogue,
           !blankBefore,
           !plausibleCue,
           (leftX >= 0.18 || widthRatio >= 0.80 || baseClass == .dialogue) {
            return .dialogue
        }

        if baseClass == .sceneHeading {
            let validHeading = trimmed.contains(where: \.isLetter)
                && !trimmed.hasSuffix(".")
                && !trimmed.hasSuffix("!")
                && !trimmed.hasSuffix("?")
                && leftX < 0.30
            if validHeading {
                return .sceneHeading
            }
        }

        if baseClass == .characterCue {
            let validCue = plausibleCue && (
                hasCueIndent
                || (uppercaseRatio >= 0.85
                    && lineLength < 28
                    && !trimmed.hasSuffix(".")
                    && !trimmed.hasSuffix("!")
                    && !trimmed.hasSuffix("?")
                    && (widthRatio >= 0.80 || leftX >= 0.22 || !blankAfter))
            )
            if validCue {
                return .characterCue
            }
            return (prevClass == .characterCue || prevClass == .parenthetical) ? .dialogue : .action
        }

        return baseClass ?? ((prevClass == .characterCue || prevClass == .parenthetical) ? .dialogue : .action)
    }

    private nonisolated func hasBlankGapBefore(index: Int, in lines: [LayoutLine]) -> Bool {
        var cursor = index - 1
        while cursor >= 0 {
            let candidate = lines[cursor].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty {
                return true
            }
            if Self.isPageMetadataLine(candidate) {
                cursor -= 1
                continue
            }
            return Self.verticalGapIndicatesBlank(between: lines[cursor], and: lines[index])
        }
        return true
    }

    private nonisolated func hasBlankGapAfter(index: Int, in lines: [LayoutLine]) -> Bool {
        var cursor = index + 1
        while cursor < lines.count {
            let candidate = lines[cursor].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty {
                return true
            }
            if Self.isPageMetadataLine(candidate) {
                cursor += 1
                continue
            }
            return Self.verticalGapIndicatesBlank(between: lines[index], and: lines[cursor])
        }
        return true
    }

    private static func verticalGapIndicatesBlank(between first: LayoutLine, and second: LayoutLine) -> Bool {
        guard first.pageIndex == second.pageIndex else { return true }
        let avgHeight = max(0.004, Double(first.rect.height + second.rect.height) * 0.5)
        let gap = max(
            Double(first.rect.minY - second.rect.maxY),
            Double(second.rect.minY - first.rect.maxY)
        )
        return gap > avgHeight * 1.15
    }

    private static func computeUppercaseRatio(_ text: String) -> Double {
        var totalLetters = 0
        var upperLetters = 0
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            totalLetters += 1
            if CharacterSet.uppercaseLetters.contains(scalar) {
                upperLetters += 1
            }
        }
        guard totalLetters > 0 else { return 0.0 }
        return Double(upperLetters) / Double(totalLetters)
    }

    private static func isPageMetadataLine(_ trimmed: String) -> Bool {
        let upper = trimmed.uppercased()
        if upper == "CONFIDENTIAL" || upper == "DO NOT DISTRIBUTE" || upper == "AUDITION SIDES ONLY"
            || upper == "FINAL SHOOTING DRAFT" || upper == "REVISED SHOOTING DRAFT" {
            return true
        }
        if upper.hasPrefix("PROPERTY OF ") || upper.hasPrefix("PAGE ") || upper.hasPrefix("PG. ") || upper.hasPrefix("P. ") {
            return true
        }
        let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#.-–— "))
        return !stripped.isEmpty && stripped.allSatisfy(\.isNumber)
    }

    // MARK: - Model Loading

    /// Searches bundles and filesystem for the compiled `ScriptElementClassifier` v1 asset and initializes `NLModel`.
    fileprivate static func resolveAndLoadV1Model() -> NLModel? {
        guard let compiledURL = resolveCompiledModelURL(named: v1ModelName) else { return nil }
        return try? NLModel(contentsOf: compiledURL)
    }

    /// Searches bundles and filesystem for the optional `ScriptElementClassifierV2` hybrid asset and initializes `MLModel`.
    fileprivate static func resolveAndLoadV2Model() -> MLModel? {
        guard let compiledURL = resolveCompiledModelURL(named: v2ModelName) else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        return try? MLModel(contentsOf: compiledURL, configuration: config)
    }

    private static func resolveCompiledModelURL(named modelName: String) -> URL? {
        if let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            return url
        }

        let tokenBundle = Bundle(for: _ScriptParserRunnerBundleToken.self)
        if let url = tokenBundle.url(forResource: modelName, withExtension: "mlmodelc") {
            return url
        }

        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            if let url = bundle.url(forResource: modelName, withExtension: "mlmodelc") {
                return url
            }
        }

        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            if let url = bundle.url(forResource: modelName, withExtension: "mlmodel"),
               let compiled = try? MLModel.compileModel(at: url) {
                return compiled
            }
        }

        let candidatePaths = [
            "OneTake/Core/Models/\(modelName).mlmodel",
            "../OneTake/Core/Models/\(modelName).mlmodel",
            "../../OneTake/Core/Models/\(modelName).mlmodel"
        ]

        for path in candidatePaths {
            let fileURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: fileURL.path),
               let compiled = try? MLModel.compileModel(at: fileURL) {
                return compiled
            }
        }

        return nil
    }
}
