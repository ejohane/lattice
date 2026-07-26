import Foundation

public enum MacMarkdownSpacing {
  public static let editorMaximumWidth: CGFloat = 760
  public static let editorBottomPadding: CGFloat = 48

  public static func editorHorizontalPadding(for width: CGFloat) -> CGFloat {
    min(72, max(32, width * 0.10))
  }

  public static func editorTopPadding(for height: CGFloat) -> CGFloat {
    min(64, max(32, height * 0.08))
  }
}
