//
//  CoreAIClinicalEmbeddingProvider.swift
//  OpenClinic
//
//  Silicon-native embedding engine backed by Apple's Core AI framework.
//  Adapted from OpenIntelligence's CoreAISentenceEmbeddingProvider.
//

import Foundation
import Accelerate

#if canImport(CoreAI)
import CoreAI
#endif

@available(iOS 27.0, *)
final class CoreAIClinicalEmbeddingProvider: ClinicalEmbeddingProvider, @unchecked Sendable {
    let dimension: Int = 384
    private let maxSequenceLength: Int

    #if canImport(CoreAI)
    private var model: AIModel?
    private var encodeFunction: InferenceFunction?
    #endif

    private var tokenizer: BertWordPieceTokenizer?
    private let clsId: Int = 101
    private let sepId: Int = 102
    private let padId: Int = 0

    init(maxSequenceLength: Int = 512) {
        self.maxSequenceLength = maxSequenceLength
        setup()
    }

    private func setup() {
        tokenizer = BertWordPieceTokenizer.fromBundle(resourceName: "embedding_vocab")

        #if canImport(CoreAI)
        let modelName = "EmbeddingModel"
        guard let url = Bundle.main.url(forResource: modelName, withExtension: "aimodel") else {
            return
        }

        Task {
            do {
                let loadedModel = try await AIModel(contentsOf: url)
                self.model = loadedModel
                self.encodeFunction = try loadedModel.loadFunction(named: "encode")
            } catch {
                print("Failed to load Core AI model: \(error)")
            }
        }
        #endif
    }

    var isAvailable: Bool {
        #if canImport(CoreAI)
        return model != nil && encodeFunction != nil && tokenizer != nil
        #else
        return false
        #endif
    }

    func countTokens(_ text: String) -> Int {
        guard let tokenizer = tokenizer else { return 0 }
        return tokenizer.countTokens(text)
    }

    func embed(text: String) async throws -> [Float] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyInput
        }

        #if canImport(CoreAI)
        guard let encodeFunction = encodeFunction, let tokenizer = tokenizer else {
            throw EmbeddingError.modelUnavailable
        }

        var tokenIds = tokenizer.tokenize(text)

        if tokenIds.count > maxSequenceLength - 2 {
            tokenIds = Array(tokenIds.prefix(maxSequenceLength - 2))
        }

        var inputIds = [clsId]
        inputIds.append(contentsOf: tokenIds)
        inputIds.append(sepId)

        let padLength = maxSequenceLength - inputIds.count
        if padLength > 0 {
            inputIds.append(contentsOf: repeatElement(padId, count: padLength))
        }

        let inputTensor = Tensor(shape: [1, maxSequenceLength], data: inputIds.map { Int32($0) })

        let outputs = try await encodeFunction.execute(["input_ids": inputTensor])
        guard let embeddingsTensor = outputs["embeddings"] else {
            throw EmbeddingError.outputParsingFailed
        }

        return embeddingsTensor.toArray(type: Float.self)
        #else
        throw EmbeddingError.modelUnavailable
        #endif
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
