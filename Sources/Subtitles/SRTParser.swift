import Foundation

enum SRTParser {
  static func parse(url: URL) throws -> [SubtitleCue] {
    let data = try Data(contentsOf: url)

    guard let rawText = decode(data) else {
      throw ParserError.unsupportedEncoding
    }

    return parse(text: rawText)
  }

  static func parse(text: String) -> [SubtitleCue] {
    let normalizedText = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    let blocks = normalizedText.components(separatedBy: "\n\n")
    var cues: [SubtitleCue] = []

    for block in blocks {
      let lines = block
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

      guard
        let timingIndex = lines.firstIndex(where: { $0.contains("-->") }),
        timingIndex < lines.count
      else {
        continue
      }

      let timingLine = lines[timingIndex]
      let timingParts = timingLine.components(separatedBy: "-->")

      guard
        timingParts.count == 2,
        let start = parseTimestamp(timingParts[0]),
        let end = parseTimestamp(timingParts[1]),
        end > start
      else {
        continue
      }

      let textLines = Array(lines.dropFirst(timingIndex + 1))
      guard !textLines.isEmpty else {
        continue
      }

      let cueText = textLines.joined(separator: "\n")
      cues.append(SubtitleCue(start: start, end: end, text: cueText))
    }

    return cues.sorted { $0.start < $1.start }
  }

  private static func parseTimestamp(_ rawValue: String) -> TimeInterval? {
    let token = rawValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .components(separatedBy: .whitespaces)
      .first ?? ""

    let normalized = token.replacingOccurrences(of: ",", with: ".")
    let segments = normalized.split(separator: ":")
    guard segments.count == 3 else {
      return nil
    }

    guard
      let hours = Double(segments[0]),
      let minutes = Double(segments[1])
    else {
      return nil
    }

    let secondSegments = segments[2].split(separator: ".", maxSplits: 1)

    guard let seconds = Double(secondSegments[0]) else {
      return nil
    }

    var fractionalSeconds: Double = 0
    if secondSegments.count == 2 {
      fractionalSeconds = Double("0." + secondSegments[1]) ?? 0
    }

    return hours * 3600 + minutes * 60 + seconds + fractionalSeconds
  }

  private static func decode(_ data: Data) -> String? {
    if let text = String(data: data, encoding: .utf8) {
      return text
    }

    if let text = String(data: data, encoding: .utf16LittleEndian) {
      return text
    }

    if let text = String(data: data, encoding: .utf16BigEndian) {
      return text
    }

    return String(data: data, encoding: .unicode)
  }
}

extension SRTParser {
  enum ParserError: Error {
    case unsupportedEncoding
  }
}
