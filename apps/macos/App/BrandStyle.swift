import AppKit
import SwiftUI

/// Shared appearance roles for the menu bar panel and settings window.
enum BrandPalette {
    private static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        func component(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                    green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? component(dark) : component(light)
        })
    }

    static let background = color(0xF6F1E9, 0x202225)
    static let sidebar = color(0xEFE9DF, 0x292B2E)
    static let surface = color(0xFAF7F1, 0x2B2D31)
    static let separator = color(0xD5CCC0, 0x414347)
    static let text = color(0x34312D, 0xF3F1EB)
    static let muted = color(0x68625C, 0xA2A5AA)
    static let accent = Color(red: 246 / 255, green: 130 / 255, blue: 31 / 255)
    /// Accessible accent for text; the brand orange itself is for fills and marks.
    static let accentText = color(0xA84400, 0xFFAD62)
    static let onAccent = Color(red: 32 / 255, green: 34 / 255, blue: 37 / 255)
    static let success = color(0x286B42, 0x8BDDA2)
    static let warning = color(0x8A5100, 0xFFD18A)
    static let danger = color(0xA12F2F, 0xFFAAAA)
    static let selection = color(0xF4DDC5, 0x49382F)
}

enum BrandMetrics {
    static let xs: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xlarge: CGFloat = 32
    static let cornerRadius: CGFloat = 12
}

/// Existing extension-derived lightning and quota mark; not a Cloudflare logo.
struct BrandMark: View {
    var size: CGFloat = 40
    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct BrandHeader: View {
    @Environment(\.locale) private var locale
    var body: some View {
        HStack(spacing: BrandMetrics.small) {
            BrandMark(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Billing Helper").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BrandPalette.text)
                Text("for Cloudflare®")
                    .font(.system(size: 12)).foregroundStyle(BrandPalette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A top-level semantic section; do not nest inside another BillingSection.
struct BillingSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: BrandMetrics.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(BrandPalette.text)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(BrandPalette.muted).fixedSize(horizontal: false, vertical: true) }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandMetrics.large)
        .background(BrandPalette.surface, in: RoundedRectangle(cornerRadius: BrandMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: BrandMetrics.cornerRadius).strokeBorder(BrandPalette.separator, lineWidth: 1))
    }
}

enum StatusTone { case neutral, success, warning, danger }
struct StatusPill: View {
    let text: String
    var tone: StatusTone = .neutral
    init(_ text: String, tone: StatusTone = .neutral) { self.text = text; self.tone = tone }
    private var color: Color {
        switch tone {
        case .neutral: return BrandPalette.muted
        case .success: return BrandPalette.success
        case .warning: return BrandPalette.warning
        case .danger: return BrandPalette.danger
        }
    }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

struct SecondaryText: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: 13)).foregroundStyle(BrandPalette.muted)
    }
}
extension View {
    func secondaryText() -> some View { modifier(SecondaryText()) }
}
