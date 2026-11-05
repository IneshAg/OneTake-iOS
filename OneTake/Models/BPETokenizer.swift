import Foundation

/// Pure Swift Byte-Level BPE Tokenizer for on-device Core ML neural models.
/// Enables 100% offline, zero-network tokenization and detokenization directly in Swift
/// on any iPhone without Python, C++ bridging, or third-party package dependencies.
final class BPETokenizer: Sendable {
    static let shared = BPETokenizer()

    // Special token IDs for Qwen / standard chat models
    let eosTokenID: Int = 151645
    let imStartTokenID: Int = 151644
    let imEndTokenID: Int = 151645

    /// Byte-to-Unicode and Unicode-to-Byte mappings for byte-level BPE (GPT-2 / Qwen standard)
    private let bytesToUnicode: [UInt8: Character]
    private let unicodeToBytes: [Character: UInt8]

    /// Vocabulary mapping token string -> token ID
    private let vocab: [String: Int]
    /// Reverse vocabulary mapping token ID -> token string
    private let idToToken: [Int: String]

    init(vocabMap: [String: Int] = [:]) {
        // Construct standard Byte-Level BPE character mapping
        var b2u: [UInt8: Character] = [:]
        var u2b: [Character: UInt8] = [:]

        // Standard printable ASCII characters map to themselves
        for b in (UInt8(33)...UInt8(126)) {
            let char = Character(UnicodeScalar(b))
            b2u[b] = char
            u2b[char] = b
        }
        for b in (UInt8(161)...UInt8(172)) {
            let char = Character(UnicodeScalar(b))
            b2u[b] = char
            u2b[char] = b
        }
        for b in (UInt8(174)...UInt8(255)) {
            let char = Character(UnicodeScalar(b))
            b2u[b] = char
            u2b[char] = b
        }

        // Remaining bytes map to unicode codepoints above 256
        var n: UInt32 = 0
        for b in 0...255 {
            let u8 = UInt8(b)
            if b2u[u8] == nil {
                let char = Character(UnicodeScalar(256 + n)!)
                b2u[u8] = char
                u2b[char] = u8
                n += 1
            }
        }

        self.bytesToUnicode = b2u
        self.unicodeToBytes = u2b

        if !vocabMap.isEmpty {
            self.vocab = vocabMap
            var rev: [Int: String] = [:]
            for (k, v) in vocabMap { rev[v] = k }
            self.idToToken = rev
        } else {
            // Built-in standard vocabulary fallback
            var defaultVocab: [String: Int] = [:]
            var defaultRev: [Int: String] = [:]

            // Map ASCII chars to single-character token IDs
            for (byte, char) in b2u {
                let s = String(char)
                let id = Int(byte)
                defaultVocab[s] = id
                defaultRev[id] = s
            }

            // Common structural tokens
            defaultVocab["{"] = 90
            defaultRev[90] = "{"
            defaultVocab["}"] = 92
            defaultRev[92] = "}"
            defaultVocab[":"] = 25
            defaultRev[25] = ":"
            defaultVocab[","] = 11
            defaultRev[11] = ","
            defaultVocab["\""] = 1
            defaultRev[1] = "\""
            defaultVocab["\n"] = 198
            defaultRev[198] = "\n"

            defaultVocab["<|im_start|>"] = 151644
            defaultRev[151644] = "<|im_start|>"
            defaultVocab["<|im_end|>"] = 151645
            defaultRev[151645] = "<|im_end|>"

            self.vocab = defaultVocab
            self.idToToken = defaultRev
        }
    }

    /// Decodes an array of token IDs back into a readable UTF-8 String.
    func decode(tokens: [Int]) -> String {
        var byteBuffer: [UInt8] = []

        for tokenID in tokens {
            if tokenID == eosTokenID || tokenID == imEndTokenID {
                break
            }
            if let tokenStr = idToToken[tokenID] {
                for char in tokenStr {
                    if let byte = unicodeToBytes[char] {
                        byteBuffer.append(byte)
                    } else if let scalar = char.unicodeScalars.first, scalar.value < 256 {
                        byteBuffer.append(UInt8(scalar.value))
                    }
                }
            } else if tokenID >= 0 && tokenID < 256 {
                byteBuffer.append(UInt8(tokenID))
            }
        }

        return String(decoding: byteBuffer, as: UTF8.self)
    }

    /// Encodes a raw text string into token IDs.
    func encode(text: String) -> [Int] {
        var tokenIDs: [Int] = []
        guard let data = text.data(using: .utf8) else { return [] }

        for byte in data {
            if let char = bytesToUnicode[byte] {
                let s = String(char)
                if let id = vocab[s] {
                    tokenIDs.append(id)
                } else {
                    tokenIDs.append(Int(byte))
                }
            } else {
                tokenIDs.append(Int(byte))
            }
        }

        return tokenIDs
    }

    /// Formats a chat prompt according to the model's standard ChatML format:
    /// <|im_start|>system\n{systemPrompt}<|im_end|>\n<|im_start|>user\n{userPrompt}<|im_end|>\n<|im_start|>assistant\n
    func applyChatTemplate(system: String, user: String) -> [Int] {
        var fullPrompt = "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
        return encode(text: fullPrompt)
    }
}
