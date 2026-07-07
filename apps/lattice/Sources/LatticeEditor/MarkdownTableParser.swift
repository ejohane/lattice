import Foundation

public struct MarkdownTableBlock: Equatable, Sendable {
  public let range: NSRange
  public let headerLineRange: NSRange
  public let separatorLineRange: NSRange
  public let bodyLineRanges: [NSRange]
  public let rows: [MarkdownTableRow]
  public let columnCount: Int

  public init(
    range: NSRange,
    headerLineRange: NSRange,
    separatorLineRange: NSRange,
    bodyLineRanges: [NSRange],
    rows: [MarkdownTableRow],
    columnCount: Int
  ) {
    self.range = range
    self.headerLineRange = headerLineRange
    self.separatorLineRange = separatorLineRange
    self.bodyLineRanges = bodyLineRanges
    self.rows = rows
    self.columnCount = columnCount
  }
}

public struct MarkdownTableRow: Equatable, Sendable {
  public let cells: [String]
  public let isHeader: Bool

  public init(cells: [String], isHeader: Bool) {
    self.cells = cells
    self.isHeader = isHeader
  }
}

public enum MarkdownTableParser {
  public static func tables(in text: String) -> [MarkdownTableBlock] {
    let nsString = text as NSString
    var tables: [MarkdownTableBlock] = []
    var location = 0
    var isInsideCodeBlock = false

    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)

      if isFenceLine(line) {
        isInsideCodeBlock.toggle()
        location = NSMaxRange(lineRange)
        continue
      }

      guard !isInsideCodeBlock else {
        location = NSMaxRange(lineRange)
        continue
      }

      if let table = tableStarting(at: lineRange, in: nsString) {
        tables.append(table)
        location = NSMaxRange(table.range)
      } else {
        location = NSMaxRange(lineRange)
      }
    }

    return tables
  }

  public static func table(containing range: NSRange, in text: String) -> MarkdownTableBlock? {
    tables(in: text).first { $0.range == range || NSIntersectionRange($0.range, range).length > 0 }
  }

  private static func tableStarting(at headerLineRange: NSRange, in nsString: NSString) -> MarkdownTableBlock? {
    let headerLine = nsString.substring(with: headerLineRange)
    guard
      let headerCells = cells(in: headerLine),
      headerCells.count >= 2,
      let separatorLineRange = nextLineRange(after: headerLineRange, in: nsString)
    else {
      return nil
    }

    let separatorLine = nsString.substring(with: separatorLineRange)
    guard
      let separatorCells = cells(in: separatorLine),
      separatorCells.count == headerCells.count,
      separatorCells.allSatisfy(isDelimiterCell)
    else {
      return nil
    }

    let columnCount = headerCells.count
    var bodyLineRanges: [NSRange] = []
    var bodyRows: [MarkdownTableRow] = []
    var cursor = separatorLineRange

    while let lineRange = nextLineRange(after: cursor, in: nsString) {
      let line = nsString.substring(with: lineRange)
      guard let rowCells = cells(in: line), rowCells.count >= 2, !rowCells.allSatisfy(isDelimiterCell) else {
        break
      }

      bodyLineRanges.append(lineRange)
      bodyRows.append(MarkdownTableRow(cells: normalized(rowCells, columnCount: columnCount), isHeader: false))
      cursor = lineRange
    }

    let endRange = bodyLineRanges.last ?? separatorLineRange
    let tableRange = NSRange(
      location: headerLineRange.location,
      length: NSMaxRange(endRange) - headerLineRange.location
    )
    let rows = [MarkdownTableRow(cells: normalized(headerCells, columnCount: columnCount), isHeader: true)] + bodyRows

    return MarkdownTableBlock(
      range: tableRange,
      headerLineRange: headerLineRange,
      separatorLineRange: separatorLineRange,
      bodyLineRanges: bodyLineRanges,
      rows: rows,
      columnCount: columnCount
    )
  }

  private static func nextLineRange(after lineRange: NSRange, in nsString: NSString) -> NSRange? {
    let nextLocation = NSMaxRange(lineRange)
    guard nextLocation < nsString.length else {
      return nil
    }
    return nsString.lineRange(for: NSRange(location: nextLocation, length: 0))
  }

  private static func cells(in line: String) -> [String]? {
    var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.contains("|") else {
      return nil
    }

    if trimmed.hasPrefix("|") {
      trimmed.removeFirst()
    }
    if trimmed.hasSuffix("|") {
      trimmed.removeLast()
    }

    let cells = trimmed
      .split(separator: "|", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    return cells.count >= 2 ? cells : nil
  }

  private static func isDelimiterCell(_ cell: String) -> Bool {
    var value = cell.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix(":") {
      value.removeFirst()
    }
    if value.hasSuffix(":") {
      value.removeLast()
    }
    return value.count >= 3 && value.allSatisfy { $0 == "-" }
  }

  private static func normalized(_ cells: [String], columnCount: Int) -> [String] {
    if cells.count == columnCount {
      return cells
    }
    if cells.count > columnCount {
      return Array(cells.prefix(columnCount))
    }
    return cells + Array(repeating: "", count: columnCount - cells.count)
  }

  private static func isFenceLine(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
  }
}
