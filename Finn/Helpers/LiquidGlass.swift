import SwiftUI

// MARK: - Liquid Glass View Extensions
//
// Liquid Glass APIs (glassEffect, GlassEffectContainer, .glass/.glassProminent button styles)
// require tvOS 26+ / macOS 26+ and the corresponding SDK (Xcode 26+, Swift 6.2+).
// We use #if compiler(>=6.2) so the project builds on both older and newer Xcode versions,
// with #available runtime checks inside the new-compiler branch.

extension View {
    /// Applies Liquid Glass on tvOS 26+ / macOS 26+, falling back to `.ultraThinMaterial` on earlier versions.
    /// - Parameters:
    ///   - cornerRadius: Corner radius for the glass shape (default: capsule when nil).
    ///   - isInteractive: Whether the glass responds to touch/pointer interactions.
    @ViewBuilder
    func liquidGlass(in cornerRadius: CGFloat? = nil, isInteractive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(tvOS 26, macOS 26, *) {
            if isInteractive {
                if let cornerRadius {
                    self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                } else {
                    self.glassEffect(.regular.interactive())
                }
            } else {
                if let cornerRadius {
                    self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                } else {
                    self.glassEffect(.regular)
                }
            }
        } else {
            _liquidGlassFallback(cornerRadius: cornerRadius)
        }
        #else
        _liquidGlassFallback(cornerRadius: cornerRadius)
        #endif
    }

    /// Fallback styling for pre-tvOS 26 / pre-macOS 26.
    @ViewBuilder
    private func _liquidGlassFallback(cornerRadius: CGFloat?) -> some View {
        if let cornerRadius {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial)
        }
    }

    /// Applies a glass button style on tvOS 26+ / macOS 26+.
    /// Falls back to the default button style on earlier versions.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(tvOS 26, macOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Wraps content in a `GlassEffectContainer` on tvOS 26+ / macOS 26+.
    /// On earlier versions, passes content through unchanged.
    @ViewBuilder
    func liquidGlassContainer(spacing: CGFloat = 24) -> some View {
        #if compiler(>=6.2)
        if #available(tvOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                self
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
