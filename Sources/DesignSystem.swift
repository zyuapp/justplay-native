import SwiftUI

enum DS {
  // MARK: - Spacing (4pt-based scale)

  enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
  }

  // MARK: - Corner Radii

  enum Radii {
    static let player: CGFloat = 14
    static let controlBar: CGFloat = 12
    static let card: CGFloat = 10
    static let seekPreview: CGFloat = 6
    static let button: CGFloat = 7
  }

  // MARK: - Semantic Colors

  enum Colors {
    static let surfacePrimary = Color.white.opacity(0.05)
    static let surfaceHovered = Color.white.opacity(0.08)
    static let surfaceSelected = Color.accentColor.opacity(0.15)
    static let borderSubtle = Color.white.opacity(0.08)

    static let seekTrack = Color.white.opacity(0.15)
    static let seekFill = Color.white.opacity(0.88)
    static let seekThumb = Color.white

    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)
  }

  // MARK: - Animations

  enum Anim {
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
    static let gentle = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let seekExpand = Animation.spring(response: 0.3, dampingFraction: 0.75)
    static let controlReveal = Animation.spring(response: 0.32, dampingFraction: 0.8)
  }

  // MARK: - Shadows

  enum Shadows {
    static func controlBar() -> some ViewModifier { ShadowModifier(color: .black.opacity(0.25), radius: 12, y: 4) }
    static func playerElevation() -> some ViewModifier { ShadowModifier(color: .black.opacity(0.3), radius: 18, y: 10) }
  }

  // MARK: - Border

  static let hairline: CGFloat = 0.5
}

private struct ShadowModifier: ViewModifier {
  let color: Color
  let radius: CGFloat
  let y: CGFloat

  func body(content: Content) -> some View {
    content.shadow(color: color, radius: radius, x: 0, y: y)
  }
}

extension View {
  func dsModifier(_ modifier: some ViewModifier) -> some View {
    self.modifier(modifier)
  }
}
