import Foundation
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

/// Thread-safe cached storage for the underlying `NLModel`.
private final class ClassifierStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedModel: NLModel?
    private var didAttemptLoad = false

    func model() -> NLModel? {
        lock.lock()
        defer { lock.unlock() }
        if !didAttemptLoad {
            didAttemptLoad = true
            cachedModel = CoreMLScriptParserRunner.resolveAndLoadModel()
        }
        return cachedModel
    }
}

private final class _ScriptParserRunnerBundleToken {}

/// Native Core ML runner for on-device screenplay element classification.
/// Evaluates script lines into sluglines, cues, dialogue, parentheticals, action, and metadata
/// in <1ms latency on the Apple Neural Engine and CPU.
public actor CoreMLScriptParserRunner {
    public static let shared = CoreMLScriptParserRunner()

    private let storage = ClassifierStorage()

    /// Returns true if the compiled `ScriptElementClassifier` model asset is available on device.
    public nonisolated var isAvailable: Bool {
        storage.model() != nil
    }

    /// Synchronous, thread-safe line classification.
    public nonisolated func classifySync(line: String) -> ScriptElementClass? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let nlModel = storage.model() else { return nil }
        guard let label = nlModel.predictedLabel(for: line) else { return nil }
        return ScriptElementClass(rawValue: label)
    }

    /// Asynchronous line classification on the actor.
    public func classify(line: String) async -> ScriptElementClass? {
        classifySync(line: line)
    }

    /// Classifies an array of script lines in order.
    public func classify(lines: [String]) async -> [ScriptElementClass?] {
        lines.map { classifySync(line: $0) }
    }

    /// Searches bundles and filesystem for the compiled `ScriptElementClassifier` asset and initializes `NLModel`.
    fileprivate static func resolveAndLoadModel() -> NLModel? {
        if let compiledURL = resolveCompiledModelURL() {
            if let model = try? NLModel(contentsOf: compiledURL) {
                return model
            }
        }
        return nil
    }

    private static func resolveCompiledModelURL() -> URL? {
        let modelName = "ScriptElementClassifier"

        // 1. Check main bundle for compiled model (.mlmodelc)
        if let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            return url
        }

        // 2. Check token class bundle
        let tokenBundle = Bundle(for: _ScriptParserRunnerBundleToken.self)
        if let url = tokenBundle.url(forResource: modelName, withExtension: "mlmodelc") {
            return url
        }

        // 3. Check all loaded bundles and frameworks
        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            if let url = bundle.url(forResource: modelName, withExtension: "mlmodelc") {
                return url
            }
        }

        // 4. Check for uncompiled .mlmodel in bundles and dynamically compile
        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            if let url = bundle.url(forResource: modelName, withExtension: "mlmodel") {
                if let compiled = try? MLModel.compileModel(at: url) {
                    return compiled
                }
            }
        }

        // 5. Fallback filesystem check for simulator and test execution
        let candidatePaths = [
            "OneTake/Core/Models/\(modelName).mlmodel",
            "../OneTake/Core/Models/\(modelName).mlmodel",
            "../../OneTake/Core/Models/\(modelName).mlmodel"
        ]

        for path in candidatePaths {
            let fileURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let compiled = try? MLModel.compileModel(at: fileURL) {
                    return compiled
                }
            }
        }

        return nil
    }
}
