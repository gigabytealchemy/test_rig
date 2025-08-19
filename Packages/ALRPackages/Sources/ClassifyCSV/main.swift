import Foundation
import Analyzers
import CoreTypes

// Simple CSV parser that handles quoted fields
func parseCSVLine(_ line: String) -> [String] {
    var fields: [String] = []
    var currentField = ""
    var inQuotes = false
    var previousChar: Character? = nil
    
    for char in line {
        if char == "\"" && previousChar != "\\" {
            inQuotes.toggle()
        } else if char == "," && !inQuotes {
            fields.append(currentField)
            currentField = ""
        } else {
            currentField.append(char)
        }
        previousChar = char
    }
    
    // Add the last field
    fields.append(currentField)
    
    return fields
}

// Escape quotes in a field for CSV output
func escapeCSVField(_ field: String) -> String {
    if field.contains("\"") || field.contains(",") || field.contains("\n") {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
    return field
}

// Convert array of fields to CSV line
func fieldsToCSVLine(_ fields: [String]) -> String {
    return fields.map { escapeCSVField($0) }.joined(separator: ",")
}

// Main processing
func processCSV() {
    // Use current directory as project root
    let currentDirectory = FileManager.default.currentDirectoryPath
    
    let inputPath = "\(currentDirectory)/data/data.csv"
    let outputPath = "\(currentDirectory)/data/data_with_classifications.csv"
    
    print("Processing CSV file: \(inputPath)")
    
    // Read input file
    guard let inputContent = try? String(contentsOfFile: inputPath, encoding: .utf8) else {
        print("Error: Could not read input file at \(inputPath)")
        print("Current directory: \(currentDirectory)")
        exit(1)
    }
    
    let lines = inputContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
    
    guard lines.count > 0 else {
        print("Error: Input file is empty")
        exit(1)
    }
    
    // Create analyzers
    let emotionAnalyzer = EmotionProAnalyzer()
    let domainAnalyzer = DomainProAnalyzer()
    let alrProAnalyzer = ALR_EnginePro()
    
    var outputLines: [String] = []
    
    // Process header
    let headerFields = parseCSVLine(lines[0])
    var newHeaderFields = headerFields
    newHeaderFields.append("EmotionPro")
    newHeaderFields.append("DomainPro")
    newHeaderFields.append("ALR_EnginePro")
    outputLines.append(fieldsToCSVLine(newHeaderFields))
    
    // Process data rows
    for i in 1..<lines.count {
        let fields = parseCSVLine(lines[i])
        
        if fields.isEmpty {
            continue
        }
        
        // Get the journal entry (first column)
        let journalEntry = fields[0]
        
        // Analyze the text
        let input = AnalyzerInput(
            fullText: journalEntry,
            selectedRange: nil,
            fallbackEmotion: nil
        )
        
        var emotionResult = "Error"
        var domainResult = "Error"
        var alrProResult = "Error"
        
        do {
            let emotionOutput = try emotionAnalyzer.analyze(input)
            emotionResult = emotionOutput.result
        } catch {
            print("Warning: Error analyzing emotion for row \(i): \(error)")
        }
        
        do {
            let domainOutput = try domainAnalyzer.analyze(input)
            domainResult = domainOutput.result
        } catch {
            print("Warning: Error analyzing domain for row \(i): \(error)")
        }
        
        do {
            let alrProOutput = try alrProAnalyzer.analyze(input)
            alrProResult = alrProOutput.result
        } catch {
            print("Warning: Error analyzing ALR Pro for row \(i): \(error)")
        }
        
        // Create output row
        var newFields = fields
        newFields.append(emotionResult)
        newFields.append(domainResult)
        newFields.append(alrProResult)
        outputLines.append(fieldsToCSVLine(newFields))
        
        // Progress indicator
        if i % 10 == 0 {
            print("Processed \(i)/\(lines.count - 1) rows...")
        }
    }
    
    // Write output file
    let outputContent = outputLines.joined(separator: "\n")
    do {
        try outputContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
        print("\nSuccessfully wrote output to: \(outputPath)")
        print("Processed \(lines.count - 1) journal entries")
    } catch {
        print("Error: Could not write output file: \(error)")
        exit(1)
    }
}

// Run the processing
processCSV()