//
//  ClinicalEmbeddingService.swift
//  OpenClinic
//
//  Offline embedding pipeline: CoreML MiniLM-L6-v2 primary, NLEmbedding fallback.
//  Adapted from OpenIntelligence's CoreMLSentenceEmbeddingProvider.
//

import Foundation
import CoreML
import Accelerate
import NaturalLanguage
import os

// MARK: - Protocol

/// Unified embedding interface — allows CoreML and NLEmbedding backends.
protocol ClinicalEmbeddingProvider: Sendable {
    var dimension: Int { get }
    var isAvailable: Bool { get }
    func embed(text: String) async throws -> [Float]
    func embedBatch(texts: [String]) async throws -> [[Float]]
    func countTokens(_ text: String) -> Int
}

// MARK: - Errors

enum EmbeddingError: Error, LocalizedError {
    case emptyInput
    case modelUnavailable
    case outputParsingFailed

    var errorDescription: String? {
        switch self {
        case .emptyInput: "Empty input text"
        case .modelUnavailable: "Embedding model unavailable"
        case .outputParsingFailed: "Failed to parse model output"
        }
    }
}

// MARK: - BERT Tokenizer (WordPiece)

/// Minimal BERT WordPiece tokenizer — loads vocab from JSON, handles ##subwords.
/// Ported from OpenIntelligence's BertTokenizer dependency.
final class BertWordPieceTokenizer: @unchecked Sendable {
    private let vocab: [String: Int]
    private let idToToken: [Int: String]
    private let unkId: Int

    static let clsId = 101
    static let sepId = 102
    static let padId = 0

    init(vocab: [String: Int]) {
        self.vocab = vocab
        self.idToToken = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
        self.unkId = vocab["[UNK]"] ?? 100
    }

    /// Load from a bundled vocab JSON file.
    static func fromBundle(resourceName: String = "embedding_vocab") -> BertWordPieceTokenizer? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return nil
        }
        return BertWordPieceTokenizer(vocab: dict)
    }

    /// Tokenize text into WordPiece subword IDs (no CLS/SEP — caller adds them).
    func tokenize(_ text: String) -> [Int] {
        let lowered = text.lowercased()
        let words = lowered.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var ids: [Int] = []

        for word in words {
            let cleanWord = word.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "'" }
            guard !cleanWord.isEmpty else { continue }

            // Try whole-word match
            if let id = vocab[cleanWord] {
                ids.append(id)
                continue
            }

            // WordPiece: greedily match longest prefix, then ##subwords
            var remaining = cleanWord[...]
            var isFirst = true
            while !remaining.isEmpty {
                var matched = false
                for end in stride(from: remaining.count, through: 1, by: -1) {
                    let candidate = String(remaining.prefix(end))
                    let lookup = isFirst ? candidate : "##\(candidate)"
                    if let id = vocab[lookup] {
                        ids.append(id)
                        remaining = remaining.dropFirst(end)
                        isFirst = false
                        matched = true
                        break
                    }
                }
                if !matched {
                    ids.append(unkId)
                    remaining = remaining.dropFirst(1)
                    isFirst = false
                }
            }
        }
        return ids
    }

    /// Count actual embedding tokens (including CLS + SEP).
    func countTokens(_ text: String) -> Int {
        tokenize(text).count + 2
    }
}

// MARK: - CoreML Embedding Provider

/// MiniLM-L6-v2 via CoreML — 384-dimension sentence embeddings, mean pooling + L2 norm.
final class CoreMLEmbeddingProvider: ClinicalEmbeddingProvider, @unchecked Sendable {
    let dimension: Int = 384
    private let maxSequenceLength = 512
    private var model: MLModel?
    private var tokenizer: BertWordPieceTokenizer?

    init() {
        loadModel()
        loadTokenizer()
    }

    var isAvailable: Bool { model != nil && tokenizer != nil }

    func countTokens(_ text: String) -> Int {
        tokenizer?.countTokens(text) ?? 0
    }

    // MARK: - Setup

    private func loadModel() {
        // Xcode compiles .mlpackage → .mlmodelc at build time
        if let url = Bundle.main.url(forResource: "EmbeddingModel", withExtension: "mlmodelc") {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all
                model = try MLModel(contentsOf: url, configuration: config)
                AppLogger.ai.info("✅ CoreML EmbeddingModel loaded (.mlmodelc)")
            } catch {
                AppLogger.ai.error("❌ CoreML EmbeddingModel load failed: \(error.localizedDescription)")
            }
        } else if let url = Bundle.main.url(forResource: "EmbeddingModel", withExtension: "mlpackage") {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all
                model = try MLModel(contentsOf: url, configuration: config)
                AppLogger.ai.info("✅ CoreML EmbeddingModel loaded (.mlpackage fallback)")
            } catch {
                AppLogger.ai.error("❌ CoreML EmbeddingModel mlpackage load failed: \(error.localizedDescription)")
            }
        } else {
            AppLogger.ai.warning("⚠️ EmbeddingModel not found in bundle — CoreML embeddings unavailable")
        }
    }

    private func loadTokenizer() {
        tokenizer = BertWordPieceTokenizer.fromBundle(resourceName: "embedding_vocab")
        if tokenizer != nil {
            AppLogger.ai.info("✅ BERT tokenizer loaded (embedding_vocab.json)")
        } else {
            AppLogger.ai.warning("⚠️ embedding_vocab.json not found — CoreML embeddings unavailable")
        }
    }

    // MARK: - Embed

    func embed(text: String) async throws -> [Float] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyInput
        }
        guard let model, let tokenizer else { throw EmbeddingError.modelUnavailable }

        let (inputIds, attentionMask, tokenTypeIds) = prepareInputs(text: text, tokenizer: tokenizer)

        let inputIdsArray = try MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
        let maskArray = try MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
        let tokenTypeArray = try MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)

        inputIdsArray.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
            for i in 0..<maxSequenceLength { ptr[i] = Int32(inputIds[i]) }
        }
        maskArray.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
            for i in 0..<maxSequenceLength { ptr[i] = Int32(attentionMask[i]) }
        }
        tokenTypeArray.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
            for i in 0..<maxSequenceLength { ptr[i] = Int32(tokenTypeIds[i]) }
        }

        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIdsArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray),
            "token_type_ids": MLFeatureValue(multiArray: tokenTypeArray),
        ])

        let output = try await model.prediction(from: inputs)
        guard let hiddenState = output.featureValue(for: "last_hidden_state")?.multiArrayValue else {
            throw EmbeddingError.outputParsingFailed
        }

        return meanPoolAndNormalize(hiddenState: hiddenState, attentionMask: attentionMask)
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        // Sequential for small clinical datasets (~200 chunks)
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            try results.append(await embed(text: text))
        }
        return results
    }

    // MARK: - Tokenization

    private func prepareInputs(text: String, tokenizer: BertWordPieceTokenizer) -> ([Int], [Int], [Int]) {
        var tokenIds = tokenizer.tokenize(text)

        // Truncate if too long (shouldn't happen with proper chunking)
        if tokenIds.count > self.maxSequenceLength - 2 {
            AppLogger.ai.warning("⚠️ Token truncation: \(tokenIds.count) → \(self.maxSequenceLength - 2)")
            tokenIds = Array(tokenIds.prefix(self.maxSequenceLength - 2))
        }

        var inputIds = [BertWordPieceTokenizer.clsId] + tokenIds + [BertWordPieceTokenizer.sepId]
        var attentionMask = Array(repeating: 1, count: inputIds.count)

        let padLength = maxSequenceLength - inputIds.count
        if padLength > 0 {
            inputIds.append(contentsOf: repeatElement(BertWordPieceTokenizer.padId, count: padLength))
            attentionMask.append(contentsOf: repeatElement(0, count: padLength))
        }

        let tokenTypeIds = Array(repeating: 0, count: maxSequenceLength)
        return (inputIds, attentionMask, tokenTypeIds)
    }

    // MARK: - Mean Pooling + L2 Normalization (vDSP)

    private func meanPoolAndNormalize(hiddenState: MLMultiArray, attentionMask: [Int]) -> [Float] {
        let embedDim = hiddenState.shape[2].intValue
        let seqLen = hiddenState.shape[1].intValue

        var summed = [Float](repeating: 0, count: embedDim)
        var tokenCount = 0

        if hiddenState.dataType == .float32 {
            hiddenState.withUnsafeBufferPointer(ofType: Float.self) { ptr in
                for i in 0..<seqLen where attentionMask[i] == 1 {
                    tokenCount += 1
                    let rowPtr = ptr.baseAddress! + (i * embedDim)
                    vDSP_vadd(summed, 1, rowPtr, 1, &summed, 1, vDSP_Length(embedDim))
                }
            }
        } else if hiddenState.dataType == .float16 {
            hiddenState.withUnsafeBufferPointer(ofType: Float16.self) { ptr in
                var rowFloat32 = [Float](repeating: 0, count: embedDim)
                for i in 0..<seqLen where attentionMask[i] == 1 {
                    tokenCount += 1
                    let rowOffset = i * embedDim
                    for j in 0..<embedDim { rowFloat32[j] = Float(ptr[rowOffset + j]) }
                    vDSP_vadd(summed, 1, &rowFloat32, 1, &summed, 1, vDSP_Length(embedDim))
                }
            }
        } else {
            for i in 0..<seqLen where attentionMask[i] == 1 {
                tokenCount += 1
                var rowFloat32 = [Float](repeating: 0, count: embedDim)
                for j in 0..<embedDim {
                    rowFloat32[j] = hiddenState[[0, NSNumber(value: i), NSNumber(value: j)]].floatValue
                }
                vDSP_vadd(summed, 1, &rowFloat32, 1, &summed, 1, vDSP_Length(embedDim))
            }
        }

        // Mean
        var averaged = [Float](repeating: 0, count: embedDim)
        var divisor = Float(max(tokenCount, 1))
        vDSP_vsdiv(summed, 1, &divisor, &averaged, 1, vDSP_Length(embedDim))

        // L2 normalize
        var sqSum: Float = 0
        vDSP_svesq(averaged, 1, &sqSum, vDSP_Length(embedDim))
        var norm = max(sqrt(sqSum), 1e-9)
        var normalized = [Float](repeating: 0, count: embedDim)
        vDSP_vsdiv(averaged, 1, &norm, &normalized, 1, vDSP_Length(embedDim))

        if embedDim == dimension { return normalized }
        return embedDim > dimension ? Array(normalized.prefix(dimension)) : normalized + Array(repeating: Float(0), count: dimension - embedDim)
    }
}

// MARK: - NLEmbedding Fallback Provider

/// Apple NaturalLanguage framework embedding — 512-dimension word embeddings.
/// Available on all iOS 17+ devices without any bundle assets.
final class NLEmbeddingProvider: ClinicalEmbeddingProvider, @unchecked Sendable {
    private static let fallbackDimension = 512

    private let embedding: NLEmbedding?

    var dimension: Int {
        embedding?.dimension ?? Self.fallbackDimension
    }

    init() {
        embedding = NLEmbedding.wordEmbedding(for: .english)
        if embedding != nil {
            AppLogger.ai.info("✅ NLEmbedding (English, \(self.dimension)D) loaded")
        } else {
            AppLogger.ai.warning("⚠️ NLEmbedding not available")
        }
    }

    var isAvailable: Bool { embedding != nil }

    func countTokens(_ text: String) -> Int {
        text.split(separator: " ").count + 2
    }

    func embed(text: String) async throws -> [Float] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyInput
        }
        guard let embedding else { throw EmbeddingError.modelUnavailable }

        // NLEmbedding is word-level. Average all word vectors for a sentence embedding.
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { throw EmbeddingError.emptyInput }

        let outputDimension = max(dimension, 1)
        var summed = [Double](repeating: 0, count: outputDimension)
        var validCount = 0

        for word in words {
            if let vec = embedding.vector(for: word), !vec.isEmpty {
                validCount += 1
                let validDimension = min(outputDimension, vec.count)
                for i in 0..<validDimension { summed[i] += vec[i] }
            }
        }

        guard validCount > 0 else {
            // No known words — return zero vector
            return [Float](repeating: 0, count: outputDimension)
        }

        // Mean + L2 normalize
        let mean = summed.map { Float($0 / Double(validCount)) }
        var sqSum: Float = 0
        vDSP_svesq(mean, 1, &sqSum, vDSP_Length(outputDimension))
        var norm = max(sqrt(sqSum), 1e-9)
        var normalized = [Float](repeating: 0, count: outputDimension)
        vDSP_vsdiv(mean, 1, &norm, &normalized, 1, vDSP_Length(outputDimension))

        return normalized
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            try results.append(await embed(text: text))
        }
        return results
    }
}

// MARK: - Unified Embedding Service

/// Tries CoreAI first (if iOS 27), then CoreML, falls back to NLEmbedding. Exposes the active provider's dimension.
final class ClinicalEmbeddingService: @unchecked Sendable {
    private var coreAI: Any? = nil
    private let coreML: CoreMLEmbeddingProvider
    private let nlFallback: NLEmbeddingProvider

    /// The dimension of the active provider.
    var dimension: Int { activeProvider.dimension }

    /// The active provider.
    private var activeProvider: any ClinicalEmbeddingProvider {
        if #available(iOS 27.0, *) {
            if let ai = coreAI as? CoreAIClinicalEmbeddingProvider, ai.isAvailable {
                return ai
            }
        }
        return coreML.isAvailable ? coreML : nlFallback
    }

    var providerName: String {
        if #available(iOS 27.0, *) {
            if let ai = coreAI as? CoreAIClinicalEmbeddingProvider, ai.isAvailable {
                return "CoreAI MiniLM-L6-v2 (384D)"
            }
        }
        return coreML.isAvailable ? "CoreML MiniLM-L6-v2 (384D)" : "NLEmbedding (\(nlFallback.dimension)D)"
    }

    var isAvailable: Bool { 
        if #available(iOS 27.0, *) {
            if let ai = coreAI as? CoreAIClinicalEmbeddingProvider, ai.isAvailable { return true }
        }
        return coreML.isAvailable || nlFallback.isAvailable 
    }

    init() {
        if #available(iOS 27.0, *) {
            coreAI = CoreAIClinicalEmbeddingProvider()
        }
        coreML = CoreMLEmbeddingProvider()
        nlFallback = NLEmbeddingProvider()
        AppLogger.ai.info("🧬 EmbeddingService initialized — active: \(self.providerName)")
    }

    func embed(text: String) async throws -> [Float] {
        try await activeProvider.embed(text: text)
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        try await activeProvider.embedBatch(texts: texts)
    }

    func countTokens(_ text: String) -> Int {
        activeProvider.countTokens(text)
    }
}
