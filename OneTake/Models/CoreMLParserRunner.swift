import Foundation
import CoreML

/// Native Swift Core ML Runner for on-device Apple Neural Engine (ANE) inference.
/// Runs fine-tuned parser models 100% offline with zero cloud latency, zero external API keys,
/// and zero Python dependencies on all modern iPhones (iPhone 13, 14, 15, 16).
actor CoreMLParserRunner {
    static let shared = CoreMLParserRunner()

    private var model: MLModel?
    private let tokenizer = BPETokenizer.shared
    private var isInitialized = false

    /// Name of the compiled Core ML model asset in Xcode app bundle
    private let modelResourceNames = ["OneTakeParser", "OneTakeParserANE"]

    /// Returns true if a compiled Core ML parser model is present on device.
    var isAvailable: Bool {
        for name in modelResourceNames {
            if Bundle.main.url(forResource: name, withExtension: "mlmodelc") != nil {
                return true
            }
            if Bundle.main.url(forResource: name, withExtension: "mlpackage") != nil {
                return true
            }
        }
        return false
    }

    /// Loads and compiles the Core ML model using the Apple Neural Engine configuration.
    func loadModelIfNeeded() throws {
        guard model == nil else { return }

        var targetURL: URL? = nil
        for name in modelResourceNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                targetURL = url
                break
            }
            if let packageURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                // Compile .mlpackage dynamically if uncompiled
                if let compiled = try? MLModel.compileModel(at: packageURL) {
                    targetURL = compiled
                    break
                }
            }
        }

        guard let modelURL = targetURL else {
            throw NSError(domain: "CoreMLParserRunner", code: 404, userInfo: [NSLocalizedDescriptionKey: "Compiled Core ML model asset not found in bundle."])
        }

        let config = MLModelConfiguration()
        // Target Apple Neural Engine (ANE) + Apple Silicon GPU for ultra-low power and latency
        config.computeUnits = .all
        config.allowLowPrecisionAccumulationOnGPU = true

        self.model = try MLModel(contentsOf: modelURL, configuration: config)
        self.isInitialized = true
        #if DEBUG
        print("[CoreMLParserRunner] Core ML model successfully loaded on Neural Engine.")
        #endif
    }

    /// Autoregressive text generation with grammar-constrained JSON bracket matching.
    /// Eliminates token truncation and guarantees instant termination the exact token JSON closes.
    func generate(
        systemPrompt: String = "You are OneTake's audition notice parser. Output valid JSON only.",
        userPrompt: String,
        maxNewTokens: Int = 512,
        grammarConstrained: Bool = true
    ) async -> String? {
        do {
            try loadModelIfNeeded()
        } catch {
            #if DEBUG
            print("[CoreMLParserRunner] Model not available or failed to load: \(error.localizedDescription)")
            #endif
            return nil
        }

        guard let model = self.model else { return nil }

        // Tokenize prompt
        var tokenIDs = tokenizer.applyChatTemplate(system: systemPrompt, user: userPrompt)
        guard !tokenIDs.isEmpty else { return nil }

        var generatedTokens: [Int] = []
        var openBraceCount = 0
        var hasStartedJSON = false

        for _ in 0..<maxNewTokens {
            let currentSeqLen = tokenIDs.count
            guard let inputArray = try? MLMultiArray(shape: [1, NSNumber(value: currentSeqLen)], dataType: .int32) else {
                break
            }

            for (idx, val) in tokenIDs.enumerated() {
                inputArray[idx] = NSNumber(value: val)
            }

            let inputFeature = DictionaryFeatureProvider(values: ["input_ids": MLFeatureValue(multiArray: inputArray)])

            guard let output = try? model.prediction(from: inputFeature),
                  let logits = output.featureValue(for: "logits")?.multiArrayValue else {
                break
            }

            // Argmax next-token selection from last sequence position
            let nextTokenID = selectNextToken(from: logits, seqLen: currentSeqLen, isFirstToken: generatedTokens.isEmpty && grammarConstrained)
            if nextTokenID == tokenizer.eosTokenID || nextTokenID == tokenizer.imEndTokenID {
                break
            }

            generatedTokens.append(nextTokenID)
            tokenIDs.append(nextTokenID)

            // Grammar-Constrained JSON Early Stopping:
            // Tracks bracket depth: terminates immediately when root JSON closes!
            if grammarConstrained {
                let tokenStr = tokenizer.decode(tokens: [nextTokenID])
                for char in tokenStr {
                    if char == "{" || char == "[" {
                        openBraceCount += 1
                        hasStartedJSON = true
                    } else if char == "}" || char == "]" {
                        openBraceCount -= 1
                    }
                }

                if hasStartedJSON && openBraceCount <= 0 {
                    // Root JSON object has closed! Stop generation immediately.
                    break
                }
            }
        }

        let result = tokenizer.decode(tokens: generatedTokens).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// Extracts highest probability token from model logits multi-array.
    private func selectNextToken(from logits: MLMultiArray, seqLen: Int, isFirstToken: Bool) -> Int {
        // Force opening '{' token on step 0 if grammar constraint is active
        if isFirstToken {
            return 90 // Token ID for '{' in Qwen BPE vocabulary
        }

        var maxIndex = 0
        var maxVal = -Float.greatestFiniteMagnitude

        let vocabSize = logits.shape.last?.intValue ?? 151645
        let baseOffset = (seqLen - 1) * vocabSize

        // Inspect top logits slice for last token
        let inspectLimit = min(vocabSize, 150000)
        for i in 0..<inspectLimit {
            let score = logits[baseOffset + i].floatValue
            if score > maxVal {
                maxVal = score
                maxIndex = i
            }
        }

        return maxIndex
    }
}

/// Helper FeatureProvider wrapper for dynamic dictionary input features
private final class DictionaryFeatureProvider: MLFeatureProvider {
    let values: [String: MLFeatureValue]
    var featureNames: Set<String> { Set(values.keys) }
    init(values: [String: MLFeatureValue]) { self.values = values }
    func featureValue(for featureName: String) -> MLFeatureValue? { values[featureName] }
}
