import LatticeShared
import Testing

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Suite("LatticeTheme")
struct LatticeThemeTests {
  @Test("uses the app background color for the editor page in every theme")
  func editorBackgroundMatchesAppBackground() {
    for themeID in LatticeThemeID.allCases {
      let theme = LatticeTheme(id: themeID)

      #if os(macOS)
      #expect(theme.nsColor(.editorBackground).rgbaComponents == theme.nsColor(.appBackground).rgbaComponents)
      #else
      #expect(theme.uiColor(.editorBackground).rgbaComponents == theme.uiColor(.appBackground).rgbaComponents)
      #endif
    }
  }
}

#if os(macOS)
private extension NSColor {
  var rgbaComponents: [CGFloat] {
    guard let color = usingColorSpace(.sRGB) else {
      return []
    }

    return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
  }
}
#else
private extension UIColor {
  var rgbaComponents: [CGFloat] {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return [red, green, blue, alpha]
  }
}
#endif
