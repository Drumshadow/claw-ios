import SwiftUI
import UIKit

struct TerminalTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    var onTap: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()

        // Configure appearance
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.dataDetectorTypes = []
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = UIColor(hex: 0xd4d4d8)

        // Enable scrolling
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true

        // Set up delegate
        textView.delegate = context.coordinator

        // Add tap gesture
        if onTap != nil {
            let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
            textView.addGestureRecognizer(tapGesture)
        }

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let shouldScrollToBottom = context.coordinator.shouldAutoScroll(uiView)

        // Update content
        uiView.attributedText = attributedText

        // Auto-scroll to bottom if we were already at bottom
        if shouldScrollToBottom {
            DispatchQueue.main.async {
                context.coordinator.scrollToBottom(uiView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var onTap: (() -> Void)?

        init(onTap: (() -> Void)?) {
            self.onTap = onTap
        }

        func shouldAutoScroll(_ textView: UITextView) -> Bool {
            // Check if user is scrolled to bottom (within 100 points)
            let offset = textView.contentOffset.y
            let contentHeight = textView.contentSize.height
            let frameHeight = textView.frame.size.height
            let bottomOffset = contentHeight - frameHeight

            // If content is smaller than frame, always scroll
            if bottomOffset <= 0 {
                return true
            }

            // Check if we're near the bottom
            return offset >= bottomOffset - 100
        }

        func scrollToBottom(_ textView: UITextView) {
            let contentHeight = textView.contentSize.height
            let frameHeight = textView.frame.size.height

            if contentHeight > frameHeight {
                let bottomOffset = CGPoint(x: 0, y: contentHeight - frameHeight)
                textView.setContentOffset(bottomOffset, animated: false)
            }
        }

        @objc func handleTap() {
            onTap?()
        }

        // UITextViewDelegate methods
        func textViewDidChangeSelection(_ textView: UITextView) {
            // Allow text selection for copy operations
        }
    }
}
