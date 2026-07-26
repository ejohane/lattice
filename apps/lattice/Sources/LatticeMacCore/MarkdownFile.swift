import Foundation

public struct MarkdownFile: Identifiable, Hashable, Sendable {
  public let url: URL
  public let relativePath: String

  public var id: URL { url }

  public init(url: URL, relativePath: String) {
    self.url = url
    self.relativePath = relativePath
  }
}
