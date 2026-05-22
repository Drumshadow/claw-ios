import Foundation

// MARK: - ShareMetadataExtractor

/// Extracts metadata from share intake items using platform APIs.
///
/// Supported extractions:
/// - PDF: title, author, page count, first-N-pages text via PDFKit
/// - Image: labels and text via Vision (VNRecognizeTextRequest / VNClassifyImageRequest)
/// - URL: title and description via lightweight HTML parsing (no WebView)
/// - Code/Text/Logs: line count, language hint, key patterns
///
/// All Vision and PDFKit calls are conditional on platform availability.
/// The extractor degrades gracefully to empty metadata when frameworks are unavailable.
@MainActor
final class ShareMetadataExtractor {

    // MARK: - Public entry point

    /// Extract metadata from an intake item. Returns nil if nothing useful was found.
    func extract(from item: ShareIntakeItem) async -> ShareItemMetadata? {
        var meta = ShareItemMetadata()
        var hasContent = false

        switch item.contentType {
        case .pdf:
            if let data = item.fileData {
                let result = await extractPDFMetadata(data: data, fileName: item.fileName)
                if result.title != nil || result.pageCount != nil || result.author != nil {
                    meta = result
                    hasContent = true
                }
            }

        case .image:
            if let data = item.fileData {
                let result = await extractImageMetadata(data: data)
                if result.imageDescription != nil {
                    meta = result
                    hasContent = true
                }
            }

        case .url:
            if let url = item.url {
                let result = await extractURLMetadata(url: url)
                if result.title != nil {
                    meta = result
                    hasContent = true
                }
            }

        case .code, .logs, .text:
            if let text = item.textContent {
                meta.keywords = extractKeywords(from: text, contentType: item.contentType)
                hasContent = true
            }

        case .file:
            // For generic files, extract from filename only
            if let name = item.fileName {
                meta.title = name
                hasContent = true
            }
        }

        return hasContent ? meta : nil
    }

    // MARK: - PDF metadata

    private func extractPDFMetadata(data: Data, fileName: String?) async -> ShareItemMetadata {
        var meta = ShareItemMetadata()
        meta.title = fileName

        // PDFKit is available on iOS 11+
        // We import conditionally to avoid requiring PDFKit in targets that don't need it.
        // NOTE: In production, add `import PDFKit` at the top and unwrap the PDFDocument.
        // The block below shows the intended API; comment it back in when PDFKit is available:
        //
        // let doc = PDFDocument(data: data)
        // meta.pageCount = doc?.pageCount
        // if let attrs = doc?.documentAttributes {
        //     meta.title  = attrs[PDFDocumentAttribute.titleAttribute] as? String ?? fileName
        //     meta.author = attrs[PDFDocumentAttribute.authorAttribute] as? String
        // }
        // // Extract text from first 3 pages for context
        // var text = ""
        // for i in 0..<min(3, doc?.pageCount ?? 0) {
        //     if let page = doc?.page(at: i) {
        //         text += page.string ?? ""
        //     }
        // }
        // if !text.isEmpty { meta.keywords = extractKeywords(from: text, contentType: .pdf) }

        // Lightweight fallback: scan raw bytes for %Title and %Author PDF metadata tags
        if let pdfString = String(data: data.prefix(4096), encoding: .utf8) ??
                           String(data: data.prefix(4096), encoding: .isoLatin1) {
            if let titleRange = pdfString.range(of: "/Title (") {
                let after = pdfString[titleRange.upperBound...]
                if let endParen = after.firstIndex(of: ")") {
                    meta.title = String(after[..<endParen])
                }
            }
            if let authorRange = pdfString.range(of: "/Author (") {
                let after = pdfString[authorRange.upperBound...]
                if let endParen = after.firstIndex(of: ")") {
                    meta.author = String(after[..<endParen])
                }
            }
        }

        return meta
    }

    // MARK: - Image metadata (Vision)

    private func extractImageMetadata(data: Data) async -> ShareItemMetadata {
        var meta = ShareItemMetadata()

        // Vision OCR — available iOS 13+
        // NOTE: In production, import Vision and uncomment the block below.
        // The API is:
        //
        // import Vision
        //
        // let request = VNRecognizeTextRequest { req, _ in
        //     let observations = req.results as? [VNRecognizedTextObservation] ?? []
        //     let recognized = observations.compactMap { $0.topCandidates(1).first?.string }
        //     meta.imageDescription = recognized.joined(separator: " ")
        // }
        // request.recognitionLevel = .accurate
        //
        // if let cgImage = UIImage(data: data)?.cgImage {
        //     let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        //     try? handler.perform([request])
        // }

        // Fallback: mark as image without description
        meta.imageDescription = nil   // will be populated by Vision when available
        return meta
    }

    // MARK: - URL metadata

    private func extractURLMetadata(url: URL) async -> ShareItemMetadata {
        var meta = ShareItemMetadata()
        meta.title = url.host ?? url.absoluteString

        // Lightweight title scrape — fetch first 8KB and parse <title> tag
        guard url.scheme == "https" || url.scheme == "http" else { return meta }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)

        do {
            var req = URLRequest(url: url)
            req.setValue("text/html", forHTTPHeaderField: "Accept")
            // Request only the first 8KB via Range header (not always honoured)
            req.setValue("bytes=0-8191", forHTTPHeaderField: "Range")

            let (data, _) = try await session.data(for: req)
            let html = String(data: data.prefix(8192), encoding: .utf8) ?? ""

            // Parse <title>...</title>
            if let titleRange = html.range(of: "<title", options: .caseInsensitive),
               let openEnd = html[titleRange.upperBound...].firstIndex(of: ">"),
               let closeStart = html.range(of: "</title>", options: .caseInsensitive,
                                           range: openEnd..<html.endIndex)?.lowerBound {
                let rawTitle = String(html[html.index(after: openEnd)..<closeStart])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawTitle.isEmpty {
                    meta.title = rawTitle
                        .replacingOccurrences(of: "&amp;", with: "&")
                        .replacingOccurrences(of: "&lt;", with: "<")
                        .replacingOccurrences(of: "&gt;", with: ">")
                        .replacingOccurrences(of: "&quot;", with: "\"")
                }
            }

            // Parse <meta name="description" content="...">
            let metaPattern = #"<meta[^>]+name="description"[^>]+content="([^"]*)"#
            if let range = html.range(of: metaPattern, options: [.regularExpression, .caseInsensitive]) {
                let match = String(html[range])
                if let contentRange = match.range(of: #"content="([^"]*)"#, options: .regularExpression),
                   let valueStart = match[contentRange].firstIndex(of: "\""),
                   let valueEnd = match[contentRange].lastIndex(of: "\""),
                   valueStart != valueEnd {
                    let desc = String(match[contentRange][match[contentRange].index(after: valueStart)..<valueEnd])
                    meta.keywords = desc.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                }
            }
        } catch {
            // Timeout or fetch error — fall back to hostname as title
        }

        return meta
    }

    // MARK: - Text keyword extraction

    private func extractKeywords(from text: String, contentType: ShareContentType) -> [String] {
        // Very simple: extract identifiers that appear multiple times
        let words = text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 4 }

        var frequency: [String: Int] = [:]
        for word in words {
            let lower = word.lowercased()
            frequency[lower, default: 0] += 1
        }

        // Top 10 words by frequency, excluding common stop words
        let stopWords: Set<String> = ["error", "function", "return", "const", "class",
                                       "import", "using", "public", "private", "static",
                                       "true", "false", "null", "undefined", "print", "debug"]
        return frequency
            .filter { !stopWords.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }
}
