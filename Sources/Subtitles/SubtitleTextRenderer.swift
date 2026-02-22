import Foundation
import SwiftUI

enum SubtitleTextRenderer {
  private static let tagRegex: NSRegularExpression? = {
    try? NSRegularExpression(pattern: "(?i)<\\s*(/?)\\s*([ibu])\\s*>")
  }()

  struct Segment: Equatable {
    let text: String
    let isItalic: Bool
    let isBold: Bool
    let isUnderlined: Bool
  }

  static func render(_ rawText: String) -> Text {
    let segments = parseSegments(in: rawText)
    guard !segments.isEmpty else {
      return Text("")
    }

    return segments.reduce(Text("")) { partial, segment in
      partial + styledText(for: segment)
    }
  }

  static func plainText(_ rawText: String) -> String {
    parseSegments(in: rawText)
      .map { $0.text }
      .joined()
  }

  private static func styledText(for segment: Segment) -> Text {
    var text = Text(segment.text)

    if segment.isItalic {
      text = text.italic()
    }

    if segment.isBold {
      text = text.bold()
    }

    if segment.isUnderlined {
      text = text.underline()
    }

    return text
  }

  private static func parseSegments(in rawText: String) -> [Segment] {
    guard let regex = tagRegex else {
      return [Segment(text: rawText, isItalic: false, isBold: false, isUnderlined: false)]
    }

    let nsText = rawText as NSString
    let matches = regex.matches(in: rawText, range: NSRange(location: 0, length: nsText.length))

    var segments: [Segment] = []
    var cursor = 0
    var isItalic = false
    var isBold = false
    var isUnderlined = false

    func appendTextSegment(_ content: String) {
      guard !content.isEmpty else {
        return
      }

      let segment = Segment(
        text: content,
        isItalic: isItalic,
        isBold: isBold,
        isUnderlined: isUnderlined
      )

      if
        let lastSegment = segments.last,
        lastSegment.isItalic == segment.isItalic,
        lastSegment.isBold == segment.isBold,
        lastSegment.isUnderlined == segment.isUnderlined
      {
        segments[segments.count - 1] = Segment(
          text: lastSegment.text + segment.text,
          isItalic: segment.isItalic,
          isBold: segment.isBold,
          isUnderlined: segment.isUnderlined
        )
      } else {
        segments.append(segment)
      }
    }

    for match in matches {
      let tagRange = match.range

      if tagRange.location > cursor {
        let textRange = NSRange(location: cursor, length: tagRange.location - cursor)
        appendTextSegment(nsText.substring(with: textRange))
      }

      let isClosingTag = !nsText.substring(with: match.range(at: 1)).isEmpty
      let tagName = nsText.substring(with: match.range(at: 2)).lowercased()
      let isEnabled = !isClosingTag

      switch tagName {
      case "i":
        isItalic = isEnabled
      case "b":
        isBold = isEnabled
      case "u":
        isUnderlined = isEnabled
      default:
        break
      }

      cursor = tagRange.location + tagRange.length
    }

    if cursor < nsText.length {
      let trailingRange = NSRange(location: cursor, length: nsText.length - cursor)
      appendTextSegment(nsText.substring(with: trailingRange))
    }

    return segments
  }
}
