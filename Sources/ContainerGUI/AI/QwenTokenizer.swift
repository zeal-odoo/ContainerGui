import Foundation

/// The pinned Qwen tokenizer's NFC, byte-level BPE subset. No network or template execution.
struct QwenTokenizer {
    enum Failure: Error {
        case invalidTokenizer
        case unknownToken
        case contextLimit
    }

    private struct Definition: Decodable {
        struct Normalizer: Decodable { let type: String }
        struct Model: Decodable {
            let type: String
            let vocab: [String: Int]
            let merges: [[String]]
        }
        struct AddedToken: Decodable {
            let id: Int
            let content: String
        }
        let normalizer: Normalizer
        let model: Model
        let added_tokens: [AddedToken]
    }

    private struct Pair: Hashable {
        let left: String
        let right: String
    }

    private let vocabulary: [String: Int]
    private let tokens: [Int: String]
    private let addedTokens: [Int: String]
    private let ranks: [Pair: Int]
    private let pattern: NSRegularExpression

    private static let byteSymbols: [String] = {
        let visible = Array(33...126) + Array(161...172) + Array(174...255)
        var mapping = [String](repeating: "", count: 256)
        for value in visible { mapping[value] = String(UnicodeScalar(value)!) }
        var extra = 256
        for value in 0...255 where mapping[value].isEmpty {
            mapping[value] = String(UnicodeScalar(extra)!)
            extra += 1
        }
        return mapping
    }()

    private static let symbolBytes = Dictionary(uniqueKeysWithValues:
        byteSymbols.enumerated().map { ($0.element.unicodeScalars.first!, UInt8($0.offset)) }
    )

    init(data: Data) throws {
        guard data.count <= 16 * 1024 * 1024,
              let definition = try? JSONDecoder().decode(Definition.self, from: data),
              definition.normalizer.type == "NFC", definition.model.type == "BPE",
              !definition.model.vocab.isEmpty, definition.model.vocab.count <= 200_000,
              definition.model.merges.count <= 200_000 else {
            throw Failure.invalidTokenizer
        }
        var reverse: [Int: String] = [:]
        for (token, id) in definition.model.vocab {
            guard id >= 0, id < 151_643, !token.isEmpty, reverse[id] == nil else {
                throw Failure.invalidTokenizer
            }
            reverse[id] = token
        }
        var added: [Int: String] = [:]
        for token in definition.added_tokens {
            guard (151_643...151_668).contains(token.id), added[token.id] == nil else {
                throw Failure.invalidTokenizer
            }
            added[token.id] = token.content
        }
        for (id, content) in [151643: "<|endoftext|>", 151644: "<|im_start|>", 151645: "<|im_end|>", 151667: "<think>", 151668: "</think>"] {
            guard added[id] == content else { throw Failure.invalidTokenizer }
        }
        var mergeRanks: [Pair: Int] = [:]
        for (rank, merge) in definition.model.merges.enumerated() {
            guard merge.count == 2, definition.model.vocab[merge[0] + merge[1]] != nil else {
                throw Failure.invalidTokenizer
            }
            let pair = Pair(left: merge[0], right: merge[1])
            guard mergeRanks[pair] == nil else { throw Failure.invalidTokenizer }
            mergeRanks[pair] = rank
        }
        vocabulary = definition.model.vocab
        tokens = reverse
        addedTokens = added
        ranks = mergeRanks
        pattern = try NSRegularExpression(pattern:
            #"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"#
        )
    }

    /// Special-token-looking input is ordinary text; only our framing inserts control IDs.
    func encode(_ text: String) throws -> [Int] {
        let normalized = text.precomposedStringWithCanonicalMapping
        var result: [Int] = []
        for match in pattern.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
            guard let range = Range(match.range, in: normalized) else { throw Failure.invalidTokenizer }
            var symbols = normalized[range].utf8.map { Self.byteSymbols[Int($0)] }
            while symbols.count > 1 {
                var selected: Pair?
                var lowestRank = Int.max
                for index in 0..<(symbols.count - 1) {
                    let pair = Pair(left: symbols[index], right: symbols[index + 1])
                    if let rank = ranks[pair], rank < lowestRank {
                        selected = pair
                        lowestRank = rank
                    }
                }
                guard let selected else { break }
                var merged: [String] = []
                var index = 0
                while index < symbols.count {
                    if index + 1 < symbols.count,
                       symbols[index] == selected.left, symbols[index + 1] == selected.right {
                        merged.append(selected.left + selected.right)
                        index += 2
                    } else {
                        merged.append(symbols[index])
                        index += 1
                    }
                }
                symbols = merged
            }
            for symbol in symbols {
                guard let token = vocabulary[symbol] else { throw Failure.unknownToken }
                result.append(token)
            }
        }
        return result
    }

    func decode(_ tokenIDs: [Int]) throws -> String {
        var bytes: [UInt8] = []
        for id in tokenIDs {
            if let added = addedTokens[id] {
                bytes.append(contentsOf: added.utf8)
            } else if let token = tokens[id] {
                for scalar in token.unicodeScalars {
                    guard let byte = Self.symbolBytes[scalar] else { throw Failure.unknownToken }
                    bytes.append(byte)
                }
            } else {
                throw Failure.unknownToken
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    func nonThinkingPrompt(system: String, evidence: String, maximumTokens: Int = 1792) throws -> [Int] {
        let prefix = [151644] + (try encode("system\n" + system)) + [151645]
            + (try encode("\n")) + [151644] + (try encode("user\n"))
        let suffix = [151645] + (try encode("\n")) + [151644] + (try encode("assistant\n"))
            + [151667] + (try encode("\n\n")) + [151668] + (try encode("\n\n"))
        let available = maximumTokens - prefix.count - suffix.count
        guard available > 0, maximumTokens <= 1792 else { throw Failure.contextLimit }
        let evidenceTokens = try encode(evidence)
        return prefix + evidenceTokens.suffix(available) + suffix
    }
}
