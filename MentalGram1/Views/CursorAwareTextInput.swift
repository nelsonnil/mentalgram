import UIKit

// MARK: - UIWindow: first responder lookup

extension UIWindow {
    /// Walks the view hierarchy to find the currently active first responder.
    var currentFirstResponder: UIResponder? {
        findFirstResponder(in: self)
    }

    private func findFirstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let found = findFirstResponder(in: sub) { return found }
        }
        return nil
    }
}

// MARK: - Cursor-aware token insertion

/// Inserts `token` at the current cursor position of the focused UITextView or UITextField
/// that is a descendant of `window`. Falls back to appending to `binding` when no
/// focusable text input is found (e.g., field is not focused).
func insertTokenAtCursor(_ token: String, fallback binding: inout String) {
    let keyWindow = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }

    guard let window = keyWindow else {
        binding += token
        return
    }

    let responder = window.currentFirstResponder

    // ── UITextView (TextEditor) ────────────────────────────────────────────────
    if let tv = responder as? UITextView {
        let selectedRange = tv.selectedRange
        guard let swiftRange = Range(selectedRange, in: tv.text) else {
            tv.text += token
            tv.delegate?.textViewDidChange?(tv)
            binding = tv.text
            return
        }
        let newText = tv.text.replacingCharacters(in: swiftRange, with: token)
        tv.text = newText
        let newCursor = selectedRange.location + (token as NSString).length
        tv.selectedRange = NSRange(location: newCursor, length: 0)
        tv.delegate?.textViewDidChange?(tv)
        binding = newText
        return
    }

    // ── UITextField (TextField) ───────────────────────────────────────────────
    if let tf = responder as? UITextField {
        if let sel = tf.selectedTextRange {
            tf.replace(sel, withText: token)
            tf.sendActions(for: .editingChanged)
            binding = tf.text ?? ""
        } else {
            binding += token
        }
        return
    }

    // ── Fallback ──────────────────────────────────────────────────────────────
    binding += token
}
