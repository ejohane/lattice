import Foundation

public enum VimEditorMode: String, Equatable, Sendable {
  case insert
  case normal
  case visual
  case commandLine
}

public enum VimOperator: String, Equatable, Sendable {
  case delete
  case change
  case yank
}

public enum VimEditorAction: Equatable, Sendable {
  case none
  case write
}

public enum VimKeyInput: Equatable, Sendable {
  case character(String)
  case escape
  case returnKey
  case deleteBackward
}

public struct VimEditorState: Equatable, Sendable {
  public var mode: VimEditorMode
  public var pendingInput: String
  public var commandText: String
  public var preferredColumn: Int?
  public var selectionAnchor: Int?
  public var pendingOperator: VimOperator?
  public var pendingCount: Int?
  public var unnamedRegister: String

  public init(
    mode: VimEditorMode = .insert,
    pendingInput: String = "",
    commandText: String = "",
    preferredColumn: Int? = nil,
    selectionAnchor: Int? = nil,
    pendingOperator: VimOperator? = nil,
    pendingCount: Int? = nil,
    unnamedRegister: String = ""
  ) {
    self.mode = mode
    self.pendingInput = pendingInput
    self.commandText = commandText
    self.preferredColumn = preferredColumn
    self.selectionAnchor = selectionAnchor
    self.pendingOperator = pendingOperator
    self.pendingCount = pendingCount
    self.unnamedRegister = unnamedRegister
  }
}

public struct VimEditResult: Equatable, Sendable {
  public let body: String
  public let selection: NSRange
  public let state: VimEditorState
  public let replacementRange: NSRange?
  public let replacement: String?
  public let action: VimEditorAction
  public let statusMessage: String?

  public init(
    body: String,
    selection: NSRange,
    state: VimEditorState,
    replacementRange: NSRange? = nil,
    replacement: String? = nil,
    action: VimEditorAction = .none,
    statusMessage: String? = nil
  ) {
    self.body = body
    self.selection = selection
    self.state = state
    self.replacementRange = replacementRange
    self.replacement = replacement
    self.action = action
    self.statusMessage = statusMessage
  }
}

public enum VimTextEditing {
  public static func handle(
    _ input: VimKeyInput,
    body: String,
    selection: NSRange,
    state: VimEditorState
  ) -> VimEditResult {
    switch state.mode {
    case .insert:
      return handleInsert(input, body: body, selection: selection, state: state)
    case .normal:
      return handleNormal(input, body: body, selection: selection, state: state)
    case .visual:
      return handleVisual(input, body: body, selection: selection, state: state)
    case .commandLine:
      return handleCommandLine(input, body: body, selection: selection, state: state)
    }
  }

  public static func relativeLineNumber(
    lineNumber: Int,
    activeLineNumber: Int
  ) -> Int {
    lineNumber == activeLineNumber ? lineNumber : abs(lineNumber - activeLineNumber)
  }

  private static func handleInsert(
    _ input: VimKeyInput,
    body: String,
    selection: NSRange,
    state: VimEditorState
  ) -> VimEditResult {
    guard input == .escape else {
      return VimEditResult(body: body, selection: selection, state: state)
    }
    return VimEditResult(
      body: body,
      selection: clamped(selection, length: (body as NSString).length),
      state: normalState(from: state)
    )
  }

  private static func handleCommandLine(
    _ input: VimKeyInput,
    body: String,
    selection: NSRange,
    state: VimEditorState
  ) -> VimEditResult {
    var nextState = normalState(from: state)
    nextState.mode = .commandLine
    nextState.commandText = state.commandText

    switch input {
    case .escape:
      return VimEditResult(body: body, selection: selection, state: normalState(from: state))
    case .deleteBackward:
      if !nextState.commandText.isEmpty {
        nextState.commandText.removeLast()
      }
      return VimEditResult(body: body, selection: selection, state: nextState)
    case .returnKey:
      let command = nextState.commandText.trimmingCharacters(in: .whitespacesAndNewlines)
      nextState = normalState(from: state)
      if command == "w" {
        return VimEditResult(
          body: body,
          selection: selection,
          state: nextState,
          action: .write,
          statusMessage: "Saved"
        )
      }
      return VimEditResult(
        body: body,
        selection: selection,
        state: nextState,
        statusMessage: command.isEmpty ? nil : "Unsupported command: \(command)"
      )
    case .character(let character):
      nextState.commandText += character
      return VimEditResult(body: body, selection: selection, state: nextState)
    }
  }

  private static func handleNormal(
    _ input: VimKeyInput,
    body: String,
    selection: NSRange,
    state: VimEditorState
  ) -> VimEditResult {
    let nsString = body as NSString
    let range = clamped(selection, length: nsString.length)

    guard case .character(let character) = input else {
      if input == .deleteBackward, range.length > 0 {
        return apply(.delete, to: range, in: nsString, state: state)
      }
      return VimEditResult(body: body, selection: range, state: normalState(from: state))
    }

    if shouldAccumulateCount(character, state: state) {
      var nextState = state
      nextState.mode = .normal
      nextState.pendingCount = accumulatedCount(character, existing: state.pendingCount)
      return VimEditResult(body: body, selection: range, state: nextState)
    }

    if let pendingOperator = state.pendingOperator {
      return handleOperator(
        pendingOperator,
        input: character,
        body: body,
        selection: range,
        state: state
      )
    }

    if range.length > 0 {
      switch character {
      case "d", "x":
        return apply(.delete, to: range, in: nsString, state: state)
      case "c":
        return apply(.change, to: range, in: nsString, state: state)
      case "y":
        return apply(.yank, to: range, in: nsString, state: state)
      default:
        break
      }
    }

    let count = commandCount(state)
    let location = range.location
    var nextState = normalState(from: state)
    let command = state.pendingInput + character

    switch command {
    case "i":
      nextState.mode = .insert
      return VimEditResult(body: body, selection: range, state: nextState)
    case "a":
      nextState.mode = .insert
      return VimEditResult(body: body, selection: insertionRange(at: min(nsString.length, location + 1)), state: nextState)
    case "A":
      nextState.mode = .insert
      return VimEditResult(body: body, selection: insertionRange(at: lineEnd(in: nsString, location: location)), state: nextState)
    case "o":
      nextState.mode = .insert
      return openLineBelow(in: nsString, location: location, state: nextState)
    case "O":
      nextState.mode = .insert
      return replacing(
        NSRange(location: lineStart(in: nsString, location: location), length: 0),
        with: "\n",
        in: nsString,
        state: nextState
      )
    case "v":
      nextState.mode = .visual
      nextState.selectionAnchor = location
      return VimEditResult(
        body: body,
        selection: selectionRange(anchor: location, activeLocation: min(nsString.length, location + 1), length: nsString.length),
        state: nextState
      )
    case ":":
      nextState.mode = .commandLine
      nextState.commandText = ""
      return VimEditResult(body: body, selection: range, state: nextState)
    case "d":
      return beginOperator(.delete, body: body, selection: range, state: state)
    case "c":
      return beginOperator(.change, body: body, selection: range, state: state)
    case "y":
      return beginOperator(.yank, body: body, selection: range, state: state)
    case "x":
      let deleteCount = min(count, max(0, nsString.length - location))
      guard deleteCount > 0 else {
        return VimEditResult(body: body, selection: range, state: nextState)
      }
      return apply(.delete, to: NSRange(location: location, length: deleteCount), in: nsString, state: state)
    case "D":
      let target = lineEnd(in: nsString, location: location)
      guard target > location else {
        return VimEditResult(body: body, selection: range, state: nextState)
      }
      return apply(.delete, to: NSRange(location: location, length: target - location), in: nsString, state: state)
    case "p":
      return pasteRegister(after: true, body: body, selection: range, state: state)
    case "P":
      return pasteRegister(after: false, body: body, selection: range, state: state)
    case "g":
      nextState = state
      nextState.pendingInput = "g"
      return VimEditResult(body: body, selection: range, state: nextState)
    case "gg":
      return VimEditResult(body: body, selection: insertionRange(at: 0), state: nextState)
    default:
      if let motion = motionDestination(command, count: count, in: nsString, from: location, preferredColumn: state.preferredColumn) {
        nextState.preferredColumn = motion.preferredColumn
        return VimEditResult(body: body, selection: insertionRange(at: motion.location), state: nextState)
      }
      return VimEditResult(body: body, selection: range, state: nextState)
    }
  }

  private static func handleOperator(
    _ pendingOperator: VimOperator,
    input: String,
    body: String,
    selection: NSRange,
    state: VimEditorState
  ) -> VimEditResult {
    let nsString = body as NSString
    let location = selection.location

    if shouldAccumulateCount(input, state: state) {
      var nextState = state
      nextState.pendingCount = accumulatedCount(input, existing: state.pendingCount)
      return VimEditResult(body: body, selection: selection, state: nextState)
    }

    let count = commandCount(state)
    let command = state.pendingInput + input

    switch command {
    case "d" where pendingOperator == .delete:
      return apply(.delete, to: lineRange(in: nsString, location: location, count: count), in: nsString, state: state)
    case "c" where pendingOperator == .change:
      return apply(.change, to: lineRange(in: nsString, location: location, count: count), in: nsString, state: state)
    case "y" where pendingOperator == .yank:
      return apply(.yank, to: lineRange(in: nsString, location: location, count: count), in: nsString, state: state)
    case "i", "a":
      var nextState = state
      nextState.pendingInput = command
      return VimEditResult(body: body, selection: selection, state: nextState)
    case "iw":
      guard let range = wordTextObject(in: nsString, location: location, includesWhitespace: false) else {
        return VimEditResult(body: body, selection: selection, state: normalState(from: state))
      }
      return apply(pendingOperator, to: range, in: nsString, state: state)
    case "aw":
      guard let range = wordTextObject(in: nsString, location: location, includesWhitespace: true) else {
        return VimEditResult(body: body, selection: selection, state: normalState(from: state))
      }
      return apply(pendingOperator, to: range, in: nsString, state: state)
    case "g":
      var nextState = state
      nextState.pendingInput = "g"
      return VimEditResult(body: body, selection: selection, state: nextState)
    case "gg":
      let targetRange = rangeBetween(location, 0)
      return apply(pendingOperator, to: targetRange, in: nsString, state: state)
    default:
      if let operatorRange = motionRange(command, count: count, in: nsString, from: location, preferredColumn: state.preferredColumn) {
        return apply(pendingOperator, to: operatorRange.range, in: nsString, state: state)
      }
      return VimEditResult(body: body, selection: selection, state: normalState(from: state))
    }
  }

  private static func handleVisual(
    _ input: VimKeyInput,
    body: String,
    selection: NSRange,
    state: VimEditorState
  ) -> VimEditResult {
    let nsString = body as NSString
    let range = clamped(selection, length: nsString.length)
    let anchor = max(0, min(state.selectionAnchor ?? range.location, nsString.length))
    let activeLocation = activeSelectionLocation(selection: range, anchor: anchor)

    guard case .character(let character) = input else {
      if input == .deleteBackward {
        return apply(.delete, to: range, in: nsString, state: state)
      }
      return VimEditResult(body: body, selection: insertionRange(at: range.location), state: normalState(from: state))
    }

    var nextState = state
    nextState.mode = .visual

    switch state.pendingInput + character {
    case "v":
      return VimEditResult(body: body, selection: insertionRange(at: range.location), state: normalState(from: state))
    case "d", "x":
      return apply(.delete, to: range, in: nsString, state: state)
    case "c":
      return apply(.change, to: range, in: nsString, state: state)
    case "y":
      return apply(.yank, to: range, in: nsString, state: state)
    case "p", "P":
      return replaceSelectionWithRegister(range, in: nsString, state: state)
    case "i", "a", "g":
      nextState.pendingInput = state.pendingInput + character
      return VimEditResult(body: body, selection: range, state: nextState)
    case "iw":
      guard let objectRange = wordTextObject(in: nsString, location: activeLocation, includesWhitespace: false) else {
        return VimEditResult(body: body, selection: range, state: nextState)
      }
      return VimEditResult(body: body, selection: objectRange, state: visualState(from: state, anchor: objectRange.location))
    case "aw":
      guard let objectRange = wordTextObject(in: nsString, location: activeLocation, includesWhitespace: true) else {
        return VimEditResult(body: body, selection: range, state: nextState)
      }
      return VimEditResult(body: body, selection: objectRange, state: visualState(from: state, anchor: objectRange.location))
    case "gg":
      nextState.pendingInput = ""
      return visualSelection(to: 0, anchor: anchor, body: body, state: nextState)
    default:
      nextState.pendingInput = ""
      if let motion = motionDestination(String(character), count: commandCount(state), in: nsString, from: activeLocation, preferredColumn: state.preferredColumn) {
        nextState.preferredColumn = motion.preferredColumn
        return visualSelection(to: motion.location, anchor: anchor, body: body, state: nextState)
      }
      return VimEditResult(body: body, selection: range, state: nextState)
    }
  }

  private static func beginOperator(
    _ pendingOperator: VimOperator,
    body: String,
    selection: NSRange,
    state: VimEditorState
  ) -> VimEditResult {
    var nextState = state
    nextState.mode = .normal
    nextState.pendingInput = ""
    nextState.pendingOperator = pendingOperator
    return VimEditResult(body: body, selection: selection, state: nextState)
  }

  private static func apply(
    _ operation: VimOperator,
    to range: NSRange,
    in nsString: NSString,
    state: VimEditorState
  ) -> VimEditResult {
    let range = clamped(range, length: nsString.length)
    let capturedText = nsString.substring(with: range)
    var nextState = normalState(from: state)
    nextState.unnamedRegister = capturedText

    switch operation {
    case .delete:
      return replacing(range, with: "", in: nsString, state: nextState)
    case .change:
      nextState.mode = .insert
      return replacing(range, with: "", in: nsString, state: nextState)
    case .yank:
      return VimEditResult(
        body: nsString as String,
        selection: insertionRange(at: range.location),
        state: nextState,
        statusMessage: "Yanked"
      )
    }
  }

  private static func pasteRegister(
    after: Bool,
    body: String,
    selection: NSRange,
    state: VimEditorState
  ) -> VimEditResult {
    guard !state.unnamedRegister.isEmpty else {
      return VimEditResult(body: body, selection: selection, state: normalState(from: state))
    }
    let nsString = body as NSString
    let insertion = after ? min(nsString.length, selection.location + 1) : selection.location
    return replacing(
      NSRange(location: insertion, length: 0),
      with: state.unnamedRegister,
      in: nsString,
      state: normalState(from: state),
      selectionOffset: (state.unnamedRegister as NSString).length
    )
  }

  private static func replaceSelectionWithRegister(
    _ range: NSRange,
    in nsString: NSString,
    state: VimEditorState
  ) -> VimEditResult {
    guard !state.unnamedRegister.isEmpty else {
      return VimEditResult(body: nsString as String, selection: range, state: state)
    }
    var nextState = normalState(from: state)
    nextState.unnamedRegister = nsString.substring(with: clamped(range, length: nsString.length))
    return replacing(range, with: state.unnamedRegister, in: nsString, state: nextState, selectionOffset: (state.unnamedRegister as NSString).length)
  }

  private static func motionDestination(
    _ command: String,
    count: Int,
    in nsString: NSString,
    from location: Int,
    preferredColumn: Int?
  ) -> (location: Int, preferredColumn: Int?)? {
    switch command {
    case "h":
      return (max(0, location - count), nil)
    case "l":
      return (min(nsString.length, location + count), nil)
    case "j":
      var result = (location: location, preferredColumn: preferredColumn)
      for _ in 0..<count {
        let moved = moveVertically(in: nsString, location: result.location, direction: 1, preferredColumn: result.preferredColumn)
        result = (moved.location, moved.preferredColumn)
      }
      return result
    case "k":
      var result = (location: location, preferredColumn: preferredColumn)
      for _ in 0..<count {
        let moved = moveVertically(in: nsString, location: result.location, direction: -1, preferredColumn: result.preferredColumn)
        result = (moved.location, moved.preferredColumn)
      }
      return result
    case "w":
      return (repeated(count, from: location) { nextWordStart(in: nsString, from: $0) }, nil)
    case "W":
      return (repeated(count, from: location) { nextBigWordStart(in: nsString, from: $0) }, nil)
    case "b":
      return (repeated(count, from: location) { previousWordStart(in: nsString, from: $0) }, nil)
    case "B":
      return (repeated(count, from: location) { previousBigWordStart(in: nsString, from: $0) }, nil)
    case "e":
      return (repeated(count, from: location) { nextWordEnd(in: nsString, from: $0) }, nil)
    case "E":
      return (repeated(count, from: location) { nextBigWordEnd(in: nsString, from: $0) }, nil)
    case "ge":
      return (repeated(count, from: location) { previousWordEnd(in: nsString, from: $0) }, nil)
    case "0":
      return (lineStart(in: nsString, location: location), nil)
    case "$":
      return (lineEnd(in: nsString, location: location), nil)
    case "G":
      return (lastLineStart(in: nsString), nil)
    default:
      return nil
    }
  }

  private static func motionRange(
    _ command: String,
    count: Int,
    in nsString: NSString,
    from location: Int,
    preferredColumn: Int?
  ) -> (range: NSRange, preferredColumn: Int?)? {
    guard let destination = motionDestination(command, count: count, in: nsString, from: location, preferredColumn: preferredColumn) else {
      return nil
    }
    let end = ["e", "E", "ge"].contains(command) ? min(nsString.length, destination.location + 1) : destination.location
    return (rangeBetween(location, end), destination.preferredColumn)
  }

  private static func normalState(from state: VimEditorState) -> VimEditorState {
    VimEditorState(
      mode: .normal,
      unnamedRegister: state.unnamedRegister
    )
  }

  private static func visualState(from state: VimEditorState, anchor: Int) -> VimEditorState {
    VimEditorState(
      mode: .visual,
      selectionAnchor: anchor,
      unnamedRegister: state.unnamedRegister
    )
  }

  private static func visualSelection(
    to activeLocation: Int,
    anchor: Int,
    body: String,
    state: VimEditorState
  ) -> VimEditResult {
    var nextState = state
    nextState.mode = .visual
    nextState.selectionAnchor = anchor
    return VimEditResult(
      body: body,
      selection: selectionRange(anchor: anchor, activeLocation: activeLocation, length: (body as NSString).length),
      state: nextState
    )
  }

  private static func replacing(
    _ range: NSRange,
    with replacement: String,
    in nsString: NSString,
    state: VimEditorState,
    selectionOffset: Int = 0
  ) -> VimEditResult {
    let body = nsString.replacingCharacters(in: range, with: replacement)
    let nextLocation = min((body as NSString).length, range.location + selectionOffset)
    return VimEditResult(
      body: body,
      selection: insertionRange(at: nextLocation),
      state: state,
      replacementRange: range,
      replacement: replacement
    )
  }

  private static func openLineBelow(
    in nsString: NSString,
    location: Int,
    state: VimEditorState
  ) -> VimEditResult {
    let insertion = lineRangeIncludingNewline(in: nsString, location: location).upperBound
    let lineAlreadyEndsWithNewline = insertion > 0
      && nsString.substring(with: NSRange(location: insertion - 1, length: 1)) == "\n"
    return replacing(
      NSRange(location: insertion, length: 0),
      with: "\n",
      in: nsString,
      state: state,
      selectionOffset: lineAlreadyEndsWithNewline ? 0 : 1
    )
  }

  private static func shouldAccumulateCount(_ character: String, state: VimEditorState) -> Bool {
    guard character.count == 1, let scalar = character.unicodeScalars.first, CharacterSet.decimalDigits.contains(scalar) else {
      return false
    }
    return character != "0" || state.pendingCount != nil || state.pendingOperator != nil || !state.pendingInput.isEmpty
  }

  private static func accumulatedCount(_ character: String, existing: Int?) -> Int? {
    guard let digit = Int(character) else {
      return existing
    }
    return (existing ?? 0) * 10 + digit
  }

  private static func commandCount(_ state: VimEditorState) -> Int {
    max(1, state.pendingCount ?? 1)
  }

  private static func repeated(_ count: Int, from location: Int, move: (Int) -> Int) -> Int {
    var next = location
    for _ in 0..<max(1, count) {
      let moved = move(next)
      guard moved != next else {
        return moved
      }
      next = moved
    }
    return next
  }

  private static func activeSelectionLocation(selection: NSRange, anchor: Int) -> Int {
    if anchor <= selection.location {
      return NSMaxRange(selection)
    }
    return selection.location
  }

  private static func selectionRange(anchor: Int, activeLocation: Int, length: Int) -> NSRange {
    let clampedAnchor = max(0, min(anchor, length))
    let clampedActiveLocation = max(0, min(activeLocation, length))
    let lowerBound = min(clampedAnchor, clampedActiveLocation)
    let upperBound = max(clampedAnchor, clampedActiveLocation)
    if lowerBound == upperBound, lowerBound < length {
      return NSRange(location: lowerBound, length: 1)
    }
    return NSRange(location: lowerBound, length: upperBound - lowerBound)
  }

  private static func rangeBetween(_ first: Int, _ second: Int) -> NSRange {
    let lowerBound = min(first, second)
    let upperBound = max(first, second)
    return NSRange(location: lowerBound, length: upperBound - lowerBound)
  }

  private static func insertionRange(at location: Int) -> NSRange {
    NSRange(location: max(0, location), length: 0)
  }

  private static func lineStart(in nsString: NSString, location: Int) -> Int {
    nsString.lineRange(for: NSRange(location: min(location, nsString.length), length: 0)).location
  }

  private static func lineEnd(in nsString: NSString, location: Int) -> Int {
    let range = nsString.lineRange(for: NSRange(location: min(location, nsString.length), length: 0))
    var end = NSMaxRange(range)
    while end > range.location, nsString.substring(with: NSRange(location: end - 1, length: 1)) == "\n" {
      end -= 1
    }
    return end
  }

  private static func lineRangeIncludingNewline(in nsString: NSString, location: Int) -> Range<Int> {
    let range = nsString.lineRange(for: NSRange(location: min(location, nsString.length), length: 0))
    return range.location..<NSMaxRange(range)
  }

  private static func lineRange(in nsString: NSString, location: Int, count: Int) -> NSRange {
    var range = nsString.lineRange(for: NSRange(location: min(location, nsString.length), length: 0))
    var remaining = max(1, count) - 1
    while remaining > 0, NSMaxRange(range) < nsString.length {
      let nextRange = nsString.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
      range.length = NSMaxRange(nextRange) - range.location
      remaining -= 1
    }
    return range
  }

  private static func lastLineStart(in nsString: NSString) -> Int {
    guard nsString.length > 0 else {
      return 0
    }
    let location = nsString.substring(with: NSRange(location: nsString.length - 1, length: 1)) == "\n"
      ? max(0, nsString.length - 1)
      : nsString.length
    return lineStart(in: nsString, location: location)
  }

  private static func moveVertically(
    in nsString: NSString,
    location: Int,
    direction: Int,
    preferredColumn: Int?
  ) -> (location: Int, preferredColumn: Int) {
    let currentStart = lineStart(in: nsString, location: location)
    let currentEnd = lineEnd(in: nsString, location: location)
    let column = preferredColumn ?? max(0, min(location, currentEnd) - currentStart)
    let targetProbe = direction > 0 ? NSMaxRange(nsString.lineRange(for: NSRange(location: location, length: 0))) : max(0, currentStart - 1)

    guard targetProbe >= 0, targetProbe <= nsString.length, targetProbe != location || direction > 0 else {
      return (location, column)
    }

    let targetRange = nsString.lineRange(for: NSRange(location: targetProbe, length: 0))
    guard targetRange.location != currentStart else {
      return (location, column)
    }

    let targetEnd = lineEnd(in: nsString, location: targetRange.location)
    return (min(targetRange.location + column, targetEnd), column)
  }

  private static func wordTextObject(
    in nsString: NSString,
    location: Int,
    includesWhitespace: Bool
  ) -> NSRange? {
    guard let innerRange = wordRange(in: nsString, location: location) else {
      return nil
    }
    guard includesWhitespace else {
      return innerRange
    }

    var lowerBound = innerRange.location
    var upperBound = NSMaxRange(innerRange)
    while upperBound < nsString.length, isWhitespace(nsString.character(at: upperBound)) {
      upperBound += 1
    }
    if upperBound == NSMaxRange(innerRange) {
      while lowerBound > 0, isWhitespace(nsString.character(at: lowerBound - 1)) {
        lowerBound -= 1
      }
    }
    return NSRange(location: lowerBound, length: upperBound - lowerBound)
  }

  private static func wordRange(in nsString: NSString, location: Int) -> NSRange? {
    guard nsString.length > 0 else {
      return nil
    }
    var index = min(location, nsString.length - 1)
    if !isWordCharacter(nsString.character(at: index)) {
      let next = nextWordStart(in: nsString, from: index)
      if next < nsString.length {
        index = next
      } else {
        let previous = previousWordStart(in: nsString, from: index)
        guard previous < nsString.length, isWordCharacter(nsString.character(at: previous)) else {
          return nil
        }
        index = previous
      }
    }

    var lowerBound = index
    while lowerBound > 0, isWordCharacter(nsString.character(at: lowerBound - 1)) {
      lowerBound -= 1
    }
    var upperBound = index
    while upperBound < nsString.length, isWordCharacter(nsString.character(at: upperBound)) {
      upperBound += 1
    }
    return NSRange(location: lowerBound, length: upperBound - lowerBound)
  }

  private static func nextWordStart(in nsString: NSString, from location: Int) -> Int {
    var index = min(location, nsString.length)
    if index < nsString.length, isWordCharacter(nsString.character(at: index)) {
      while index < nsString.length, isWordCharacter(nsString.character(at: index)) {
        index += 1
      }
    }
    while index < nsString.length, !isWordCharacter(nsString.character(at: index)) {
      index += 1
    }
    return index
  }

  private static func nextBigWordStart(in nsString: NSString, from location: Int) -> Int {
    var index = min(location, nsString.length)
    if index < nsString.length, !isWhitespace(nsString.character(at: index)) {
      while index < nsString.length, !isWhitespace(nsString.character(at: index)) {
        index += 1
      }
    }
    while index < nsString.length, isWhitespace(nsString.character(at: index)) {
      index += 1
    }
    return index
  }

  private static func previousWordStart(in nsString: NSString, from location: Int) -> Int {
    var index = max(0, min(location, nsString.length) - 1)
    while index > 0, !isWordCharacter(nsString.character(at: index)) {
      index -= 1
    }
    while index > 0, isWordCharacter(nsString.character(at: index - 1)) {
      index -= 1
    }
    return index
  }

  private static func previousBigWordStart(in nsString: NSString, from location: Int) -> Int {
    var index = max(0, min(location, nsString.length) - 1)
    while index > 0, isWhitespace(nsString.character(at: index)) {
      index -= 1
    }
    while index > 0, !isWhitespace(nsString.character(at: index - 1)) {
      index -= 1
    }
    return index
  }

  private static func nextWordEnd(in nsString: NSString, from location: Int) -> Int {
    var index = min(location, nsString.length)
    if index < nsString.length, isWordCharacter(nsString.character(at: index)) {
      index += 1
    }
    while index < nsString.length, !isWordCharacter(nsString.character(at: index)) {
      index += 1
    }
    while index + 1 < nsString.length, isWordCharacter(nsString.character(at: index + 1)) {
      index += 1
    }
    return min(index, max(0, nsString.length - 1))
  }

  private static func nextBigWordEnd(in nsString: NSString, from location: Int) -> Int {
    var index = min(location, nsString.length)
    if index < nsString.length, !isWhitespace(nsString.character(at: index)) {
      index += 1
    }
    while index < nsString.length, isWhitespace(nsString.character(at: index)) {
      index += 1
    }
    while index + 1 < nsString.length, !isWhitespace(nsString.character(at: index + 1)) {
      index += 1
    }
    return min(index, max(0, nsString.length - 1))
  }

  private static func previousWordEnd(in nsString: NSString, from location: Int) -> Int {
    var index = max(0, min(location, nsString.length) - 1)
    while index > 0, !isWordCharacter(nsString.character(at: index)) {
      index -= 1
    }
    return index
  }

  private static func isWordCharacter(_ character: unichar) -> Bool {
    if character == 95 {
      return true
    }
    guard let scalar = UnicodeScalar(character) else {
      return false
    }
    return CharacterSet.alphanumerics.contains(scalar)
  }

  private static func isWhitespace(_ character: unichar) -> Bool {
    guard let scalar = UnicodeScalar(character) else {
      return false
    }
    return CharacterSet.whitespacesAndNewlines.contains(scalar)
  }

  private static func clamped(_ range: NSRange, length: Int) -> NSRange {
    let location = max(0, min(range.location, length))
    return NSRange(location: location, length: max(0, min(range.length, length - location)))
  }
}
