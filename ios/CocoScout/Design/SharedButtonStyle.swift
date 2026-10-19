import SwiftUI

/// The app's own buttons, drawn exactly like the website's shared/button
/// partial (app/views/shared/_button.html.erb), which can't render inside a
/// native screen. Every button the app draws itself uses this, never a
/// one-off style.
///
///     Button("Sign out") { ... }
///         .buttonStyle(SharedButtonStyle(variant: .secondary, size: .small))
struct SharedButtonStyle: ButtonStyle {
    /// shared/button's variants the app uses so far.
    enum Variant {
        /// "primary": bg-pink-500 hover:bg-pink-600 text-white
        case primary
        /// "secondary": bg-white border border-gray-300 hover:bg-gray-50 text-gray-700
        case secondary
    }

    /// shared/button's sizes: "small" is px-3 py-1.5 text-sm; "medium" is
    /// px-5 py-2.5 at sm and up (phones use the small padding on the web too);
    /// "large" is px-8 py-3 at sm and up, 44 points tall.
    enum Size {
        case small
        case medium
        case large
    }

    var variant: Variant = .primary
    var size: Size = .medium
    /// shared/button with classes: "w-full justify-center".
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: 14, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(variant == .primary ? Color.white : Tailwind.gray700)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(background(pressed: pressed))
            )
            .overlay {
                if variant == .secondary {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Tailwind.gray300, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 4))
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small: 12
        case .medium: 20
        case .large: 32
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .small: 6
        case .medium: 10
        case .large: 12
        }
    }

    private func background(pressed: Bool) -> Color {
        switch variant {
        case .primary: pressed ? Tailwind.pink600 : Tailwind.pink500
        case .secondary: pressed ? Tailwind.gray50 : .white
        }
    }
}

/// The Tailwind v4 colors the website compiles to (app/assets/builds/tailwind.css),
/// so native pieces match the pages around them.
enum Tailwind {
    static let pink500 = Color(red: 0xF6 / 255, green: 0x33 / 255, blue: 0x9A / 255)
    static let pink600 = Color(red: 0xE6 / 255, green: 0x00 / 255, blue: 0x76 / 255)
    static let gray50 = Color(red: 0xF9 / 255, green: 0xFA / 255, blue: 0xFB / 255)
    static let gray300 = Color(red: 0xD1 / 255, green: 0xD5 / 255, blue: 0xDC / 255)
    static let gray700 = Color(red: 0x36 / 255, green: 0x41 / 255, blue: 0x53 / 255)
    static let gray900 = Color(red: 0x10 / 255, green: 0x18 / 255, blue: 0x28 / 255)
    // The door's result banner: green-600 in, amber-300 already in, red-600 no.
    static let green600 = Color(red: 0x00 / 255, green: 0xA6 / 255, blue: 0x3E / 255)
    static let amber300 = Color(red: 0xFF / 255, green: 0xD2 / 255, blue: 0x30 / 255)
    static let red600 = Color(red: 0xE7 / 255, green: 0x00 / 255, blue: 0x0B / 255)
}
