import SwiftUI
import UIKit
import VisionKit
@preconcurrency import Vision

// MARK: - Parsed receipt

/// Fields extracted from a scanned receipt. Any of these may be nil if the OCR
/// couldn't find a confident match.
struct ScannedReceipt {
    var date: Date?
    var description: String?
    var amount: Double?
    /// Whether the receipt already lists a tip/gratuity line. If false, the UI
    /// offers to bump the amount by 20%.
    var tipIncluded: Bool
}

// MARK: - Document scanner (VisionKit) wrapped for SwiftUI

/// Presents Apple's document camera to capture a receipt, runs OCR on the first
/// page, and returns the parsed fields.
struct ReceiptScannerView: UIViewControllerRepresentable {
    let onResult: (ScannedReceipt) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: ReceiptScannerView
        init(_ parent: ReceiptScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { parent.onCancel(); return }
            let image = scan.imageOfPage(at: 0)
            Task {
                let receipt = await ReceiptParser.parse(image: image)
                await MainActor.run { self.parent.onResult(receipt) }
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}

// MARK: - OCR + parsing

enum ReceiptParser {
    static func parse(image: UIImage) async -> ScannedReceipt {
        let lines = await recognizeText(image: image)
        return parseLines(lines)
    }

    /// Runs Vision text recognition and returns the recognized lines, top to bottom.
    private static func recognizeText(image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])   // completion handler resumes the continuation
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Heuristic parse of receipt lines into date / merchant / total / tip.
    static func parseLines(_ lines: [String]) -> ScannedReceipt {
        var receipt = ScannedReceipt(date: nil, description: nil, amount: nil, tipIncluded: false)

        // Merchant name: the first line with real letters (receipts put it at top).
        receipt.description = lines.first { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 3 && trimmed.rangeOfCharacter(from: .letters) != nil
        } ?? lines.first

        // A tip/gratuity line means the total already includes it.
        receipt.tipIncluded = lines.contains { line in
            let lower = line.lowercased()
            return lower.contains("tip") || lower.contains("gratuity")
        }

        receipt.amount = extractTotal(from: lines)
        receipt.date = extractDate(from: lines)
        return receipt
    }

    /// All currency-looking values in a line (e.g. "12.34", "1,234.56").
    private static func currencyValues(in line: String) -> [Double] {
        let pattern = #"\d{1,3}(?:,\d{3})+(?:\.\d{2})?|\d+\.\d{2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = line as NSString
        return regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap {
            Double(ns.substring(with: $0.range).replacingOccurrences(of: ",", with: ""))
        }
    }

    /// Prefer an explicit "total" line (ignoring "subtotal"); otherwise the
    /// largest monetary value on the receipt.
    private static func extractTotal(from lines: [String]) -> Double? {
        var totals: [Double] = []
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("total"), !lower.contains("subtotal") {
                totals.append(contentsOf: currencyValues(in: line))
            }
        }
        if let best = totals.max() { return best }
        return lines.flatMap { currencyValues(in: $0) }.max()
    }

    /// First date found in the text (NSDataDetector handles many formats).
    private static func extractDate(from lines: [String]) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        for line in lines {
            if let match = detector.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let date = match.date {
                return date
            }
        }
        return nil
    }
}
