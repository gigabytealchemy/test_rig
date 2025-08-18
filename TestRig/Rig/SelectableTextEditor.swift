import SwiftUI

struct SelectableTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: Range<String.Index>?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.delegate = context.coordinator
        textView.string = text  // Set initial text

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let tv = scroll.documentView as? NSTextView {
            if tv.string != text {
                context.coordinator.isUpdating = true
                tv.string = text
                context.coordinator.isUpdating = false
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
