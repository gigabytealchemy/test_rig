import AppKit
import SwiftUI

struct SelectableTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: Range<String.Index>?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.importsGraphics = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.delegate = context.coordinator
        textView.string = text // Set initial text

        // Configure text container
        textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else {
            print("DEBUG: No text view found in updateNSView")
            return
        }

        print("DEBUG: updateNSView called - text length: \(text.count), tv.string length: \(tv.string.count)")

        // Always update if the text is different
        if tv.string != text {
            print("DEBUG: Text differs, updating NSTextView")
            context.coordinator.isUpdating = true

            // Use DispatchQueue to ensure UI update happens
            DispatchQueue.main.async {
                tv.string = text
                tv.needsDisplay = true
                context.coordinator.isUpdating = false
                print("DEBUG: NSTextView updated with \(text.count) characters")
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableTextEditor
        var isUpdating = false

        init(_ parent: SelectableTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating else { return }
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let nsr = tv.selectedRange()
            if let r = Range(nsr, in: parent.text) {
                parent.selection = r
            } else {
                parent.selection = nil
            }
        }
    }
}
