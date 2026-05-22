import UIKit
import SwiftUI
import Social
import UniformTypeIdentifiers
import MobileCoreServices

// MARK: - ShareViewController

/// Root UIViewController for the Claw share extension.
/// Extracts shared items from the extension context, presents ShareExtensionUI
/// in a hosting controller, writes intake items to the App Group queue,
/// and then deep-links into the main app via claw:// URL.
class ShareViewController: UIViewController {

    // MARK: - Private state

    private var sharedItems: [PendingShareItem] = []
    private var hostingController: UIHostingController<AnyView>?

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Color.clawBg)
        extractSharedItems()
    }

    // MARK: - Item extraction

    private func extractSharedItems() {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            presentUI()
            return
        }

        var items: [PendingShareItem] = []
        let group = DispatchGroup()

        for inputItem in inputItems {
            for provider in inputItem.attachments ?? [] {
                group.enter()
                extractItem(from: provider) { pending in
                    if let pending { items.append(pending) }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.sharedItems = items
            self?.presentUI()
        }
    }

    private func extractItem(
        from provider: NSItemProvider,
        completion: @escaping (PendingShareItem?) -> Void
    ) {
        // URL
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                let url = item as? URL
                let pending = PendingShareItem(contentType: .url, url: url, fileName: nil, data: nil, text: nil)
                DispatchQueue.main.async { completion(pending) }
            }
            return
        }

        // PDF
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) { data, _ in
                let pending = PendingShareItem(
                    contentType: .pdf,
                    url: nil,
                    fileName: "document.pdf",
                    data: data,
                    text: nil
                )
                DispatchQueue.main.async { completion(pending) }
            }
            return
        }

        // Image
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                let pending = PendingShareItem(
                    contentType: .image,
                    url: nil,
                    fileName: "image.jpg",
                    data: data,
                    text: nil
                )
                DispatchQueue.main.async { completion(pending) }
            }
            return
        }

        // Plain text (includes code, logs)
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                let text = item as? String
                // Try to infer code vs logs from content
                let contentType: ShareContentType = {
                    guard let t = text else { return .text }
                    let lower = t.lowercased()
                    if lower.contains("error:") || lower.contains("fatal:") ||
                       lower.contains("exception") || lower.contains("stack trace") {
                        return .logs
                    }
                    if lower.contains("func ") || lower.contains("import ") ||
                       lower.contains("class ") || lower.contains("let ") {
                        return .code
                    }
                    return .text
                }()
                let pending = PendingShareItem(
                    contentType: contentType,
                    url: nil,
                    fileName: nil,
                    data: nil,
                    text: text
                )
                DispatchQueue.main.async { completion(pending) }
            }
            return
        }

        // Generic file
        if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
                var data: Data?
                var fileName: String?
                var contentType = ShareContentType.file
                if let url {
                    data = try? Data(contentsOf: url)
                    fileName = url.lastPathComponent
                    let ext = url.pathExtension
                    contentType = ShareContentType.from(fileExtension: ext)
                }
                let pending = PendingShareItem(
                    contentType: contentType,
                    url: nil,
                    fileName: fileName,
                    data: data,
                    text: nil
                )
                DispatchQueue.main.async { completion(pending) }
            }
            return
        }

        DispatchQueue.main.async { completion(nil) }
    }

    // MARK: - Hosting controller presentation

    private func presentUI() {
        // Build SwiftUI view with bindings
        let swiftUIView = ShareExtensionUI(
            sharedItems: .constant(sharedItems),
            onCancel: { [weak self] in self?.cancel() },
            onConfirm: { [weak self] items in self?.confirm(items: items) }
        )

        let host = UIHostingController(rootView: AnyView(swiftUIView))
        host.view.backgroundColor = UIColor(Color.clawBg)
        addChild(host)
        let container = self.view!
        container.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    // MARK: - Actions

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "ai.clawos.share",
            code: NSUserCancelledError
        ))
    }

    private func confirm(items: [ShareIntakeItem]) {
        // Write items to the App Group queue
        let queue = ShareIntakeQueue.shared
        queue.enqueue(contentsOf: items)

        // Deep-link into main app
        openMainApp()

        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func openMainApp() {
        // claw://share?pending=1
        guard let url = URL(string: "claw://share?pending=1") else { return }

        // Walk up the responder chain to find openURL: — only works if extension has
        // the com.apple.security.application-groups entitlement and the host app is
        // registered for the claw:// scheme.
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: #selector(UIApplication.open(_:options:completionHandler:))) {
                let app = r as? UIApplication
                app?.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
    }
}
