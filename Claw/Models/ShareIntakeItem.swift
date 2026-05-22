import Foundation
import UniformTypeIdentifiers

// MARK: - ShareContentType

/// The type of content being shared into Claw.
enum ShareContentType: String, Codable, CaseIterable {
    case url        = "url"
    case image      = "image"
    case pdf        = "pdf"
    case text       = "text"
    case code       = "code"
    case logs       = "logs"
    case file       = "file"     // generic binary file

    var displayName: String {
        switch self {
        case .url:   return "URL"
        case .image: return "Image"
        case .pdf:   return "PDF"
        case .text:  return "Text"
        case .code:  return "Code"
        case .logs:  return "Logs"
        case .file:  return "File"
        }
    }

    var systemImage: String {
        switch self {
        case .url:   return "link"
        case .image: return "photo"
        case .pdf:   return "doc.richtext"
        case .text:  return "doc.text"
        case .code:  return "chevron.left.forwardslash.chevron.right"
        case .logs:  return "terminal"
        case .file:  return "doc"
        }
    }

    /// Infer content type from a UTType.
    static func from(uti: UTType) -> ShareContentType {
        if uti.conforms(to: .url)              { return .url   }
        if uti.conforms(to: .image)            { return .image }
        if uti.conforms(to: .pdf)              { return .pdf   }
        if uti.conforms(to: .sourceCode)       { return .code  }
        if uti.conforms(to: .plainText)        { return .text  }
        return .file
    }

    /// Infer content type from a filename extension.
    static func from(fileExtension ext: String) -> ShareContentType {
        switch ext.lowercased() {
        case "pdf":                            return .pdf
        case "png", "jpg", "jpeg", "gif",
             "webp", "heic", "heif":           return .image
        case "log", "logs", "txt", "csv":      return .text
        case "swift", "py", "ts", "js", "go",
             "rs", "kt", "java", "rb", "sh",
             "c", "cpp", "h", "m":             return .code
        default:                               return .file
        }
    }
}

// MARK: - ShareActionType

/// The agent action to perform on the shared item.
enum ShareActionType: String, Codable, CaseIterable, Identifiable {
    case diagnose        = "diagnose"
    case summarize       = "summarize"
    case createFixPlan   = "create_fix_plan"
    case generatePR      = "generate_pr"
    case deployFix       = "deploy_fix"
    case explainLogs     = "explain_logs"
    case createIncident  = "create_incident"
    case analyze         = "analyze"
    case extractData     = "extract_data"
    case custom          = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .diagnose:       return "Diagnose"
        case .summarize:      return "Summarize"
        case .createFixPlan:  return "Create Fix Plan"
        case .generatePR:     return "Generate PR"
        case .deployFix:      return "Deploy Fix"
        case .explainLogs:    return "Explain Logs"
        case .createIncident: return "Create Incident"
        case .analyze:        return "Analyze"
        case .extractData:    return "Extract Data"
        case .custom:         return "Custom…"
        }
    }

    var systemImage: String {
        switch self {
        case .diagnose:       return "stethoscope"
        case .summarize:      return "text.compress"
        case .createFixPlan:  return "wrench.and.screwdriver"
        case .generatePR:     return "arrow.triangle.pull"
        case .deployFix:      return "bolt.fill"
        case .explainLogs:    return "doc.text.magnifyingglass"
        case .createIncident: return "exclamationmark.triangle.fill"
        case .analyze:        return "chart.xyaxis.line"
        case .extractData:    return "tablecells"
        case .custom:         return "slider.horizontal.3"
        }
    }

    var description: String {
        switch self {
        case .diagnose:       return "Identify issues and root causes"
        case .summarize:      return "Generate a concise summary"
        case .createFixPlan:  return "Step-by-step plan to resolve issues"
        case .generatePR:     return "Draft a pull request with changes"
        case .deployFix:      return "Prepare and trigger a deployment"
        case .explainLogs:    return "Parse and explain log output"
        case .createIncident: return "Create a structured incident report"
        case .analyze:        return "Deep analysis with recommendations"
        case .extractData:    return "Extract structured data from content"
        case .custom:         return "Enter your own prompt"
        }
    }

    var riskLevel: VoiceCommandRisk {
        switch self {
        case .deployFix:      return .danger
        case .generatePR,
             .createIncident: return .caution
        default:              return .safe
        }
    }

    /// Actions relevant for each content type.
    static func recommended(for contentType: ShareContentType) -> [ShareActionType] {
        switch contentType {
        case .url:
            return [.summarize, .analyze, .extractData, .custom]
        case .image:
            return [.analyze, .summarize, .extractData, .custom]
        case .pdf:
            return [.summarize, .analyze, .extractData, .createIncident, .custom]
        case .text:
            return [.summarize, .diagnose, .analyze, .custom]
        case .code:
            return [.diagnose, .createFixPlan, .generatePR, .summarize, .custom]
        case .logs:
            return [.explainLogs, .diagnose, .createIncident, .createFixPlan, .custom]
        case .file:
            return [.analyze, .summarize, .extractData, .custom]
        }
    }
}

// MARK: - ShareRoutingTarget

/// Determines which session/agent receives the shared intake.
enum ShareRoutingTarget: Codable {
    /// Route to an existing session by key.
    case session(id: String, title: String)
    /// Create a new session to handle this intake.
    case newSession(agentId: String)
    /// Auto-select: pick the most recently active idle session,
    /// or create a new one if none is available.
    case autoSelect

    var displayName: String {
        switch self {
        case .session(_, let t):  return t
        case .newSession(let a):  return "New session (\(a))"
        case .autoSelect:         return "Auto-select"
        }
    }
}

// MARK: - ShareIntakeItem

/// A single item received from the share extension (or an in-app share).
/// This is the data model stored in the intake queue before routing.
struct ShareIntakeItem: Identifiable, Codable {
    let id: UUID
    let contentType: ShareContentType
    let action: ShareActionType
    let routing: ShareRoutingTarget
    let customPrompt: String?

    // Content payload — at most one will be non-nil
    let url: URL?
    let fileName: String?
    let fileData: Data?          // binary payload (image, pdf, etc.)
    let textContent: String?     // extracted or raw text

    // Metadata extracted from the payload
    var extractedMetadata: ShareItemMetadata?

    // Status tracking
    var status: IntakeStatus
    var createdAt: Date
    var intakeId: String?        // assigned by server after upload

    enum IntakeStatus: String, Codable {
        case pending     // waiting in queue
        case extracting  // metadata/OCR extraction in progress
        case ready       // ready to send
        case sending     // upload to gateway in progress
        case delivered   // gateway acknowledged receipt
        case failed      // terminal failure; user can retry

        var displayName: String {
            switch self {
            case .pending:    return "Pending"
            case .extracting: return "Processing"
            case .ready:      return "Ready"
            case .sending:    return "Sending"
            case .delivered:  return "Delivered"
            case .failed:     return "Failed"
            }
        }
    }

    // MARK: - Builder

    init(
        contentType: ShareContentType,
        action: ShareActionType,
        routing: ShareRoutingTarget = .autoSelect,
        customPrompt: String? = nil,
        url: URL? = nil,
        fileName: String? = nil,
        fileData: Data? = nil,
        textContent: String? = nil
    ) {
        self.id = UUID()
        self.contentType = contentType
        self.action = action
        self.routing = routing
        self.customPrompt = customPrompt
        self.url = url
        self.fileName = fileName
        self.fileData = fileData
        self.textContent = textContent
        self.extractedMetadata = nil
        self.status = .pending
        self.createdAt = Date()
        self.intakeId = nil
    }

    // MARK: - Compose message for agent

    /// Builds the chat message text to send to the agent.
    func composeAgentMessage() -> String {
        var parts: [String] = []

        // Action instruction
        switch action {
        case .custom:
            parts.append(customPrompt ?? "Please analyze the following.")
        default:
            parts.append(actionInstruction)
        }

        // Content
        switch contentType {
        case .url:
            if let url { parts.append("\nURL: \(url.absoluteString)") }
        case .text, .code, .logs:
            if let text = textContent {
                let capped = text.count > 8000
                    ? String(text.prefix(8000)) + "\n…[truncated, \(text.count) total chars]"
                    : text
                parts.append("\n\n```\n\(capped)\n```")
            }
        case .image:
            if let meta = extractedMetadata?.imageDescription {
                parts.append("\n\nImage description: \(meta)")
            } else if let name = fileName {
                parts.append("\n\n[Image: \(name)]")
            }
        case .pdf:
            if let text = textContent {
                let capped = text.count > 8000
                    ? String(text.prefix(8000)) + "\n…[truncated]"
                    : text
                parts.append("\n\n```\n\(capped)\n```")
            } else if let name = fileName {
                parts.append("\n\n[PDF: \(name)]")
            }
        case .file:
            if let name = fileName { parts.append("\n\n[File: \(name)]") }
        }

        // Metadata context
        if let meta = extractedMetadata {
            var metaParts: [String] = []
            if let title = meta.title     { metaParts.append("Title: \(title)") }
            if let author = meta.author   { metaParts.append("Author: \(author)") }
            if let pageCount = meta.pageCount { metaParts.append("Pages: \(pageCount)") }
            if !metaParts.isEmpty {
                parts.append("\nMetadata: " + metaParts.joined(separator: ", "))
            }
        }

        return parts.joined()
    }

    private var actionInstruction: String {
        switch action {
        case .diagnose:       return "Please diagnose the following and identify any issues:"
        case .summarize:      return "Please provide a concise summary of the following:"
        case .createFixPlan:  return "Please create a step-by-step fix plan for:"
        case .generatePR:     return "Please generate a pull request for the following changes:"
        case .deployFix:      return "Please prepare a deployment for the following fix:"
        case .explainLogs:    return "Please explain the following logs in plain English:"
        case .createIncident: return "Please create a structured incident report for:"
        case .analyze:        return "Please analyze the following in detail:"
        case .extractData:    return "Please extract the key data from the following:"
        case .custom:         return customPrompt ?? "Please process the following:"
        }
    }
}

// MARK: - ShareItemMetadata

/// Metadata extracted from a shared item (OCR, PDF text, image EXIF, etc.)
struct ShareItemMetadata: Codable {
    var title: String?
    var author: String?
    var pageCount: Int?
    var imageDescription: String?  // OCR text or Vision label
    var keywords: [String]?
    var extractedAt: Date = Date()
}
