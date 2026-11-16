import SwiftUI

/// The one text-field frame: canvas fill, a `Palette.fieldStroke` outline
/// (≥3:1 against the fill and the plate in both themes, so the field reads as
/// an input before it has focus), and the system focus ring while focused.
/// Use it on a `.plain` TextField / TextEditor; single-line fields take
/// `FormMetrics.fieldHeight`.
///
/// ```swift
/// TextField("Name", text: $name)
///     .textFieldStyle(.plain)
///     .padding(.horizontal, Space.s4)
///     .frame(height: FormMetrics.fieldHeight)
///     .framedTextField(isFocused: focus == .name)
///
/// TextEditor(text: $prompt)
///     .scrollContentBackground(.hidden)
///     .padding(Space.s3)
///     .framedTextField(isFocused: focus == .prompt, radius: Radius.control)
/// ```
struct FramedTextField: ViewModifier {
    var isFocused: Bool
    var radius: CGFloat = Radius.minimum

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(Palette.canvas))
            .overlay(shape.strokeBorder(Palette.fieldStroke, lineWidth: 1))
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .padding(-2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    /// See `FramedTextField`.
    func framedTextField(isFocused: Bool, radius: CGFloat = Radius.minimum) -> some View {
        modifier(FramedTextField(isFocused: isFocused, radius: radius))
    }
}
