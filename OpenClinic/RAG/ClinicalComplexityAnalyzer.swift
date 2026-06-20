//
//  ClinicalComplexityAnalyzer.swift
//  OpenClinic
//
//  Adapted from OpenIntelligence PageComplexityAnalyzer
//  Analyzes clinical text to determine adaptive chunking strategies.
//

import Foundation

enum ClinicalComplexity: Int, Comparable, Sendable {
    case simple = 1     // Standard prose
    case moderate = 2   // Mixed prose and lists
    case complex = 3    // Tables, dense numerics, lab results
    
    static func < (lhs: ClinicalComplexity, rhs: ClinicalComplexity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ClinicalComplexityAnalysis: Sendable {
    let complexity: ClinicalComplexity
    let tableSignature: Double
    let numericDensity: Double
    let listStrength: Double
    let headerStrength: Double
    let recommendedChunkSize: Int
}

final class ClinicalComplexityAnalyzer: @unchecked Sendable {
    static let shared = ClinicalComplexityAnalyzer()
    
    private init() {}
    
    func analyze(text: String) -> ClinicalComplexityAnalysis {
        let lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else {
            return ClinicalComplexityAnalysis(
                complexity: .simple,
                tableSignature: 0,
                numericDensity: 0,
                listStrength: 0,
                headerStrength: 0,
                recommendedChunkSize: 310
            )
        }
        
        // 1. Numeric Density
        let digits = text.filter { $0.isNumber }.count
        let numericDensity = min(1.0, Double(digits) / Double(max(1, text.count)) * 5)
        
        // 2. Table Signature
        var tableSignature = 0.0
        let pipeCount = text.filter { $0 == "|" }.count
        if pipeCount > 5 { tableSignature += min(0.5, Double(pipeCount) / 20.0) }
        
        let tabCount = text.filter { $0 == "\t" }.count
        if tabCount > 10 { tableSignature += min(0.3, Double(tabCount) / 50.0) }
        
        var alignedNumericLines = 0
        for line in lines {
            let numberGroups = line.split(whereSeparator: { !$0.isNumber && $0 != "." && $0 != "," && $0 != "-" })
                .filter { $0.count > 0 && $0.first?.isNumber == true }
            if numberGroups.count >= 3 {
                alignedNumericLines += 1
            }
        }
        if alignedNumericLines > 3 {
            tableSignature += min(0.4, Double(alignedNumericLines) / 10.0)
        }
        tableSignature = min(1.0, tableSignature)
        
        // 3. List Strength
        var listLines = 0
        let listPatterns = ["• ", "- ", "* ", "· ", "○ ", "► ", "▪ "]
        let numberedPattern = try? NSRegularExpression(pattern: "^\\s*\\d+[\\.\\)\\:]\\s", options: [])
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if listPatterns.contains(where: { trimmed.hasPrefix($0) }) ||
                (numberedPattern?.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil) {
                listLines += 1
            }
        }
        let listStrength = min(1.0, Double(listLines) / Double(lines.count) * 3)
        
        // 4. Header Strength
        var headerLines = 0
        let headerPattern = try? NSRegularExpression(pattern: "^[A-Z][A-Z\\s]{3,}$|^#{1,6}\\s|^\\*\\*.*\\*\\*$", options: [])
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if headerPattern?.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                headerLines += 1
            }
        }
        let headerStrength = min(1.0, Double(headerLines) / Double(lines.count) * 10)
        
        // Determine Complexity
        let complexity: ClinicalComplexity
        let recommendedChunkSize: Int
        
        if tableSignature > 0.4 || numericDensity > 0.3 {
            complexity = .complex
            recommendedChunkSize = 500 // Don't split tables aggressively
        } else if listStrength > 0.3 || headerStrength > 0.2 {
            complexity = .moderate
            recommendedChunkSize = 250 // Slightly smaller for lists
        } else {
            complexity = .simple
            recommendedChunkSize = 310 // Standard prose
        }
        
        return ClinicalComplexityAnalysis(
            complexity: complexity,
            tableSignature: tableSignature,
            numericDensity: numericDensity,
            listStrength: listStrength,
            headerStrength: headerStrength,
            recommendedChunkSize: recommendedChunkSize
        )
    }
}
