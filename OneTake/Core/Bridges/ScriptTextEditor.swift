import SwiftUI
import UIKit

// MARK: - ScriptTextEditor (Stable, flicker-free text editor that doesn't blank out on view updates)

struct ScriptTextEditor: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont = .monospacedSystemFont(ofSize: 15, weight: .regular)
    var isEditable: Bool = true

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = font
        textView.textColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0xF3/255.0, green: 0xEE/255.0, blue: 0xF5/255.0, alpha: 1.0)
                : UIColor(red: 0x1E/255.0, green: 0x1A/255.0, blue: 0x22/255.0, alpha: 1.0)
        }
        textView.tintColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0xC8/255.0, green: 0xA8/255.0, blue: 0xE0/255.0, alpha: 1.0)
                : UIColor(red: 0x5B/255.0, green: 0x3E/255.0, blue: 0x73/255.0, alpha: 1.0)
        }
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        textView.isScrollEnabled = true
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .sentences
        textView.isEditable = isEditable
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        updateTextView(uiView)
    }

    func updateTextView(_ uiView: UITextView) {
        if uiView.text != text {
            let selectedRange = uiView.selectedRange
            uiView.text = text
            if selectedRange.location + selectedRange.length <= text.utf16.count {
                uiView.selectedRange = selectedRange
            }
        }
        uiView.font = font
        uiView.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ScriptTextEditor

        init(_ parent: ScriptTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
        }
    }
}
