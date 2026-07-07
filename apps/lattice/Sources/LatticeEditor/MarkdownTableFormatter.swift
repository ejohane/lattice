import Foundation

public struct MarkdownTableFormatResult: Equatable, Sendable {
  public let body: String
  public let selection: NSRange

  public init(body: String, selection: NSRange) {
    self.body = body
    self.selection = selection
  }
}

public enum MarkdownTableFormatter {
  public static func formatTables(
    in body: String,
    selection: NSRange,
    skipsActiveTable: Bool = true
  ) -> MarkdownTableFormatResult? {
    let tables = MarkdownTableParser.tables(in: body)
    guard !tables.isEmpty else {
      return nil
    }

    let nsString = body as NSString
    var nextBody = body
    var nextSelection = selection
    var changed = false

    for table in tables.reversed() {
      if skipsActiveTable, tableRangeIsActive(table.range, selection: selection) {
        continue
      }

      let original = nsString.substring(with: table.range)
      let replacement = formattedTable(table, original: original)
      guard replacement != original else {
        continue
      }

      nextBody = (nextBody as NSString).replacingCharacters(in: table.range, with: replacement)
      nextSelection = shifted(nextSelection, replacing: table.range, originalLength: table.range.length, replacementLength: (replacement as NSString).length)
      changed = true
    }

    return changed ? MarkdownTableFormatResult(body: nextBody, selection: nextSelection) : nil
  }

  public static func formattedTable(_ table: MarkdownTableBlock) -> String {
    formattedTable(table, original: "")
  }

  private static func formattedTable(_ table: MarkdownTableBlock, original: String) -> String {
    let columnWidths = tableColumnWidths(table)
    let rowLines = table.rows.map { row in
      formattedRow(row.cells, columnWidths: columnWidths)
    }
    let separatorLine = formattedSeparator(columnWidths: columnWidths)
    var lines = [rowLines[0], separatorLine]
    lines.append(contentsOf: rowLines.dropFirst())
    return lines.joined(separator: "\n") + trailingLineEnding(in: original)
  }

  private static func tableColumnWidths(_ table: MarkdownTableBlock) -> [Int] {
    var widths = Array(repeating: 3, count: table.columnCount)
    for row in table.rows {
      for columnIndex in 0..<table.columnCount {
        let cell = columnIndex < row.cells.count ? row.cells[columnIndex] : ""
        widths[columnIndex] = max(widths[columnIndex], cell.count)
      }
    }
    return widths
  }

  private static func formattedRow(_ cells: [String], columnWidths: [Int]) -> String {
    let paddedCells = columnWidths.enumerated().map { columnIndex, width in
      let cell = columnIndex < cells.count ? cells[columnIndex] : ""
      return " \(cell.padding(toLength: width, withPad: " ", startingAt: 0)) "
    }
    return "|\(paddedCells.joined(separator: "|"))|"
  }

  private static func formattedSeparator(columnWidths: [Int]) -> String {
    let cells = columnWidths.map { width in
      " \(String(repeating: "-", count: max(3, width))) "
    }
    return "|\(cells.joined(separator: "|"))|"
  }

  private static func trailingLineEnding(in original: String) -> String {
    if original.hasSuffix("\r\n") {
      return "\r\n"
    }
    if original.hasSuffix("\n") {
      return "\n"
    }
    if original.hasSuffix("\r") {
      return "\r"
    }
    return ""
  }

  private static func tableRangeIsActive(_ tableRange: NSRange, selection: NSRange) -> Bool {
    if selection.length > 0 {
      return NSIntersectionRange(tableRange, selection).length > 0
    }
    return selection.location >= tableRange.location && selection.location <= NSMaxRange(tableRange)
  }

  private static func shifted(
    _ selection: NSRange,
    replacing range: NSRange,
    originalLength: Int,
    replacementLength: Int
  ) -> NSRange {
    let delta = replacementLength - originalLength
    if NSMaxRange(range) <= selection.location {
      return NSRange(location: selection.location + delta, length: selection.length)
    }
    if range.location < NSMaxRange(selection) && NSMaxRange(range) > selection.location {
      return NSRange(location: range.location + replacementLength, length: 0)
    }
    return selection
  }
}
