//
//  LaTeX.swift
//  LaTeXSwiftUI
//
//  Copyright (c) 2023 Colin Campbell
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

import HTMLEntities
import MathJaxSwift
import SwiftUI

private func transformLatex(_ latex: String) -> String {
    let bbReplaced = replaceBlackboardBold(latex)
    let emojiReplaced = handleEmojis(bbReplaced)
    let lessThanReplaced = handleLessThan(emojiReplaced)
    let convertedArrayToEquation = convertArrayToEquation(lessThanReplaced)
    let ampersandRemoved = removeAmpersandsInDisplayMath(convertedArrayToEquation)
    return replaceBracketNewline(in: ampersandRemoved)
}

private func handleLessThan(_ latex: String) -> String {
    return latex.replacingOccurrences(of: "<", with: "\\lt")
}


//func replaceBracketNewline(in input: String) -> String {
//    // This pattern matches:
//    // - `\\\]`: a literal "\]" (backslash is escaped)
//    // - `\s*`: zero or more whitespace characters (including spaces or tabs)
//    // - `\n`: a newline character
//    let pattern = #"\\\]\s*\n"#
//    
//    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
//        return input
//    }
//    
//    let range = NSRange(input.startIndex..., in: input)
//    
//    // The replacement template "\\\\]" produces the literal characters "\]"
//    let modifiedString = regex.stringByReplacingMatches(in: input,
//                                                        options: [],
//                                                        range: range,
//                                                        withTemplate: "\\\\]")
//    return modifiedString
//}

func replaceBracketNewline(in input: String, debug: Bool = true) -> String {
    var modifiedString = input
    
    // --- Step 1: Remove newline and any whitespace AFTER the closing "\]" ---
    // This pattern matches:
    // - `\\\]`: a literal "\]" (backslash is escaped)
    // - `\s*`: zero or more whitespace characters (including spaces or tabs)
    // - `\n`: a newline character
    let closingPattern = #"\\\]\s*\n"#
    
    guard let closingRegex = try? NSRegularExpression(pattern: closingPattern, options: []) else {
        return input
    }
    
    let closingRange = NSRange(modifiedString.startIndex..., in: modifiedString)
    modifiedString = closingRegex.stringByReplacingMatches(in: modifiedString,
                                                           options: [],
                                                           range: closingRange,
                                                           withTemplate: "\\\\]")
    
    // --- Step 2: Remove newline and any whitespace BEFORE the first "\[" ---
    // This pattern matches:
    // - `\n`: a newline character immediately preceding the opening delimiter
    // - `\s*`: zero or more whitespace characters before the delimiter
    // - `(\\\[)`: captures the literal "\[" (the backslash is escaped)
    let openingPattern = #"\n\s*(\\\[)"#
    
    guard let openingRegex = try? NSRegularExpression(pattern: openingPattern, options: []) else {
        return modifiedString
    }
    
    // We only want to adjust the first occurrence.
    if let firstMatch = openingRegex.firstMatch(in: modifiedString, options: [], range: NSRange(modifiedString.startIndex..., in: modifiedString)) {
        // Extract the captured literal "\[" from the match.
        if let captureRange = Range(firstMatch.range(at: 1), in: modifiedString) {
            let captured = String(modifiedString[captureRange])
            // Replace the entire match (newline, whitespace, and "\[") with just the literal "\["
            if let matchRange = Range(firstMatch.range, in: modifiedString) {
                modifiedString.replaceSubrange(matchRange, with: captured)
            }
        }
    }
    
    // --- Debug output ---
    if debug {
        print("Input: \(input)")
        print("Output: \(modifiedString)")
    }
    
    return modifiedString
}

func removeAmpersandsInDisplayMath(_ input: String, debug: Bool = true) -> String {
    var output = input

    if debug {
        print("Input string:\n\(input)\n")
    }
    
    // Regular expression pattern to match display math blocks: \[ ... \]
    let pattern = #"\\\[(.*?)\\\]"#
    let regex = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    let nsrange = NSRange(output.startIndex..<output.endIndex, in: output)
    
    // Find matches in input
    let matches = regex.matches(in: output, options: [], range: nsrange)
    if debug {
        print("Found \(matches.count) display math block match(es).\n")
    }
    
    // Process matches in reverse order to maintain correct ranges
    for (index, match) in matches.reversed().enumerated() {
        let fullRange = match.range(at: 0)
        let contentRange = match.range(at: 1)
        
        if let fullRange = Range(fullRange, in: output),
           let contentRange = Range(contentRange, in: output) {
            let fullMatch = String(output[fullRange])
            let content = String(output[contentRange])
            
            if debug {
                print("Match \(index + 1):")
                print("Full match:\n\(fullMatch)")
                print("Original content:\n\(content)")
            }
            
            // Remove all '&' characters from the content
            let modifiedContent = content.replacingOccurrences(of: "&", with: "")
            
            if debug {
                print("Modified content:\n\(modifiedContent)")
            }
            
            // Reconstruct the display math block with modified content
            let newBlock = "\\[\(modifiedContent)\\]"
            output.replaceSubrange(fullRange, with: newBlock)
        }
    }
    
    if debug {
        print("\nFinal output:\n\(output)")
    }
    
    return output
}


private func replaceBlackboardBold(_ latex: String) -> String {
    var result = ""
    var currentIndex = latex.startIndex
    
    while currentIndex < latex.endIndex {
        // Look for \mathbb{
        if let range = latex[currentIndex...].range(of: "\\mathbb{") {
            // Add everything up to \mathbb{
            result += latex[currentIndex..<range.lowerBound]
            
            // Find the closing brace
            let afterCommand = range.upperBound
            guard let closingBrace = latex[afterCommand...].firstIndex(of: "}") else {
                // If no closing brace, just append the rest and break
                result += latex[currentIndex...]
                break
            }
            
            // Get content and capitalize it
            let content = latex[afterCommand..<closingBrace]
            result += "\\mathbf{\(content.uppercased())}"
            
            // Move past the closing brace
            currentIndex = latex.index(after: closingBrace)
        } else {
            // No more \mathbb{ found, append current character and move forward
            result.append(latex[currentIndex])
            currentIndex = latex.index(after: currentIndex)
        }
    }
    return result
}

func convertArrayToEquation(_ input: String, debug: Bool = false) -> String {
    var output = input

    if debug {
        print("Input string:\n\(input)\n")
    }

    // Regular expression pattern to match either:
    //   \begin{array}{...} ... \end{array}  OR  \begin{aligned} ... \end{aligned}
    let pattern = #"\\begin\{(array|aligned)\}(?:\{[^\}]*\})?(.*?)\\end\{\1\}"#
    let regex = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    let nsrange = NSRange(output.startIndex..<output.endIndex, in: output)

    // Find matches in input
    let matches = regex.matches(in: output, options: [], range: nsrange)
    if debug {
        print("Found \(matches.count) environment match(es).\n")
    }

    // Process matches in reverse order to maintain correct ranges
    for (index, match) in matches.reversed().enumerated() {
        // The full match is in group 0
        let fullRange = match.range(at: 0)
        // The inner content is captured in group 2 (group 1 holds the environment name)
        let contentRange = match.range(at: 2)

        if let fullRange = Range(fullRange, in: output),
           let contentRange = Range(contentRange, in: output) {
            let fullMatch = String(output[fullRange])
            let content = String(output[contentRange])
            
            if debug {
                print("Match \(index + 1):")
                print("Full match:\n\(fullMatch)")
                print("Inner content:\n\(content)")
            }

            // Replace occurrences of '\\' (with any trailing whitespace) with '\\ '
            let modifiedContent = content.replacingOccurrences(of: #"\\\\\s*"#, with: #"\\\\ "#, options: .regularExpression)
            
            if debug {
                print("Modified content:\n\(modifiedContent)")
            }

            // Replace the entire \begin{...}...\end{...} block with the modified content (trimming extra whitespace)
            output.replaceSubrange(fullRange, with: modifiedContent.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    if debug {
        print("\nFinal output:\n\(output)")
    }

    return output
}

func handleEmojis(_ input: String) -> String {
    // If the string contains no emoji, return it unchanged
    if !input.containsEmoji {
        return input
    }
    
    // return if input contains '\\underbrace'
    if input.contains("\\underbrace") {
        return input
    }
    
    var result = input
    
    // Remove outer \( \) LaTeX delimiters first
    result = result.replacingOccurrences(of: "\\(", with: "")
    result = result.replacingOccurrences(of: "\\)", with: "")
    
    // Handle fractions with regex first
    if let fracRegex = try? NSRegularExpression(pattern: "\\\\frac\\{([^}]+)\\}\\{([^}]+)\\}", options: []) {
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = fracRegex.stringByReplacingMatches(
            in: result,
            options: [],
            range: range,
            withTemplate: "$1 ÷ $2"
        )
    }
    
    // Handle square root with regex - ensuring consistent parentheses
    if let sqrtRegex = try? NSRegularExpression(pattern: "\\\\sqrt\\{([^}]+)\\}", options: []) {
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = sqrtRegex.stringByReplacingMatches(
            in: result,
            options: [],
            range: range,
            withTemplate: "√($1)"
        )
    }
    
    // Dictionary of LaTeX commands to Unicode symbols - ordered by length to handle longer commands first
    let latexToUnicode: [(pattern: String, replacement: String)] = [
        // Longer commands first to avoid partial matches
        ("\\leftrightarrow", "↔"),
        ("\\Leftrightarrow", "⇔"),
        ("\\rightarrow", "→"),
        ("\\Rightarrow", "⇒"),
        ("\\leftarrow", "←"),
        ("\\Leftarrow", "⇐"),
        ("\\emptyset", "∅"),
        ("\\epsilon", "ε"),
        ("\\because", "∵"),
        ("\\forall", "∀"),
        ("\\exists", "∃"),
        ("\\lambda", "λ"),
        ("\\approx", "≈"),
        ("\\subset", "⊂"),
        ("\\supset", "⊃"),
        ("\\times", "×"),
        ("\\alpha", "α"),
        ("\\beta", "β"),
        ("\\gamma", "γ"),
        ("\\delta", "δ"),
        ("\\theta", "θ"),
        ("\\sigma", "σ"),
        ("\\omega", "ω"),
        ("\\infty", "∞"),
        ("\\nabla", "∇"),
        ("\\notin", "∉"),
        ("\\equiv", "≡"),
        ("\\cdot", "·"),
        ("\\leq", "≤"),
        ("\\geq", "≥"),
        ("\\neq", "≠"),
        ("\\div", "÷"),
        ("\\cup", "∪"),
        ("\\cap", "∩"),
        ("\\in", "∈"),
        ("\\pm", "±"),
        ("\\mp", "∓"),
        ("\\pi", "π"),
        ("\\mu", "μ"),
        
        // Handle superscripts and subscripts
        ("\\^2", "²"),
        ("\\^3", "³"),
        ("_2", "₂"),
        ("_3", "₃")
    ]
    
    // Replace all LaTeX commands with their Unicode equivalents
    for (pattern, replacement) in latexToUnicode {
        result = result.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: .literal  // Changed from .regularExpression to .literal
        )
    }
    
    // Clean up spaces
    result = result.components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespaces)
    
    // Handle multiple spaces between operators
    result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    
    return result
}

/// A view that can parse and render TeX and LaTeX equations that contain
/// math-mode marcos.
public struct LaTeX: View {
  
  // MARK: Types
  
  /// A closure that takes an equation number and returns a string to display in
  /// the view.
  public typealias FormatEquationNumber = (_ n: Int) -> String
  
  /// The view's block rendering mode.
  public enum BlockMode {
    
    /// Block equations are ignored and always rendered inline.
    case alwaysInline
    
    /// Blocks are rendered as text with newlines.
    case blockText
    
    /// Blocks are rendered as views.
    case blockViews
  }
  
  /// The view's equation number mode.
  public enum EquationNumberMode {
    
    /// The view should not number named block equations.
    case none
    
    /// The view should number named block equations on the left side.
    case left
    
    /// The view should number named block equations on the right side.
    case right
  }
  
  /// The view's error mode.
  public enum ErrorMode {
    
    /// The rendered image should be displayed (if available).
    case rendered
    
    /// The original LaTeX input should be displayed.
    case original
    
    /// The error text should be displayed.
    case error
  }
  
  /// The view's rendering mode.
  public enum ParsingMode {
    
    /// Render the entire text as the equation.
    case all
    
    /// Find equations in the text and only render the equations.
    case onlyEquations
  }
  
  /// The view's rendering style.
  public enum RenderingStyle {
    
    /// The view remains empty until its finished rendering.
    case empty
    
    /// The view displays the input text until its finished rendering.
    case original
    
    /// The view displays a progress view until its finished rendering.
    case progress
    
    /// The view blocks on the main thread until its finished rendering.
    case wait
  }
  
  // MARK: Static properties
  
  /// The package's shared data cache.
  public static var dataCache: NSCache<NSString, NSData> {
    Cache.shared.dataCache
  }
  
#if os(macOS)
  /// The package's shared image cache.
  public static var imageCache: NSCache<NSString, NSImage> {
    Cache.shared.imageCache
  }
#else
  /// The package's shared image cache.
  public static var imageCache: NSCache<NSString, UIImage> {
    Cache.shared.imageCache
  }
#endif
  
  
  // MARK: Public properties
  
  /// The view's LaTeX input string.
  public let latex: String
  
  // MARK: Environment variables
  
  /// What to do in the case of an error.
  @Environment(\.errorMode) private var errorMode
  
  /// Whether or not we should unencode the input.
  @Environment(\.unencodeHTML) private var unencodeHTML
  
  /// Should the view parse the entire input string or only equations?
  @Environment(\.parsingMode) private var parsingMode
  
  /// The view's block rendering mode.
  @Environment(\.blockMode) private var blockMode
  
  /// Whether the view should process escapes.
  @Environment(\.processEscapes) private var processEscapes
  
  /// The view's rendering style.
  @Environment(\.renderingStyle) private var renderingStyle
  
  /// The animation the view should apply to its rendered images.
  @Environment(\.renderingAnimation) private var renderingAnimation
  
  /// The view's current display scale.
  @Environment(\.displayScale) private var displayScale
  
  /// The view's font.
  @Environment(\.font) private var font
  
  /// Custom scale factor to scale font given above
  @Environment(\.scaleFactor) private var scaleFactor
  
  // MARK: Private properties
  
  /// The view's renderer.
  @StateObject private var renderer = Renderer()
  
  /// The view's preload task, if any.
  @State private var preloadTask: Task<(), Never>?
  
  // MARK: Initializers
  
  /// Initializes a view with a LaTeX input string.
  ///
  /// - Parameter latex: The LaTeX input.
  public init(_ latex: String) {
      self.latex = transformLatex(latex)
  }
  
  // MARK: View body
  
  public var body: some View {
    VStack(spacing: 0) {
      if renderer.rendered {
        // If our blocks have been rendered, display them
        bodyWithBlocks(renderer.blocks)
      }
      else if isCached() {
        // If our blocks are cached, display them
        bodyWithBlocks(renderSync())
      }
      else {
        // The view is not rendered nor cached
        switch renderingStyle {
        case .empty, .original, .progress:
          // Render the components asynchronously
          loadingView().task {
            await renderAsync()
          }
        case .wait:
          // Render the components synchronously
          bodyWithBlocks(renderSync())
        }
      }
    }
    .animation(renderingAnimation, value: renderer.rendered)
    .environmentObject(renderer)
    .onDisappear(perform: preloadTask?.cancel)
  }
  
}

// MARK: Public methods

extension LaTeX {
  
  /// Preloads the view's SVG and image data.
  public func preload() {
    preloadTask?.cancel()
    preloadTask = Task { await renderAsync() }
    Task { await preloadTask?.value }
  }
  
  /// Configures the `LaTeX` view with the given style.
  ///
  /// - Parameter style: The `LaTeX` view style to use.
  /// - Returns: A stylized view.
  public func latexStyle<S>(_ style: S) -> some View where S: LaTeXStyle {
    style.makeBody(content: self)
  }
    
    public func latexScaleFactor(_ factor: CGFloat) -> some View {
        environment(\.scaleFactor, factor)
    }
  
}

// MARK: Private methods

extension LaTeX {
  
  /// Checks the renderer's caches for the current view.
  ///
  /// If this method returns `true`, then there is no need to do an async
  /// render.
  ///
  /// - Returns: A boolean indicating whether the components to the view are
  ///   cached.
  private func isCached() -> Bool {
    renderer.isCached(
      latex: latex,
      unencodeHTML: unencodeHTML,
      parsingMode: parsingMode,
      processEscapes: processEscapes,
      errorMode: errorMode,
      font: font ?? .body,
      displayScale: displayScale)
  }
  
  /// Renders the view's components.
  private func renderAsync() async {
    await renderer.render(
      latex: latex,
      unencodeHTML: unencodeHTML,
      parsingMode: parsingMode,
      processEscapes: processEscapes,
      errorMode: errorMode,
      font: font ?? .body,
      displayScale: displayScale,
      scaleFactor: scaleFactor)
  }
  
  /// Renders the view's components synchronously.
  ///
  /// - Returns: The rendered components.
  private func renderSync() -> [ComponentBlock] {
    renderer.renderSync(
      latex: latex,
      unencodeHTML: unencodeHTML,
      parsingMode: parsingMode,
      processEscapes: processEscapes,
      errorMode: errorMode,
      font: font ?? .body,
      displayScale: displayScale,
      scaleFactor: scaleFactor)
  }
  
  /// Creates the view's body based on its block mode.
  ///
  /// - Parameter blocks: The blocks to display.
  /// - Returns: The view's body.
  @MainActor @ViewBuilder private func bodyWithBlocks(_ blocks: [ComponentBlock]) -> some View {
    switch blockMode {
    case .alwaysInline:
      ComponentBlocksText(blocks: blocks, forceInline: true)
    case .blockText:
      ComponentBlocksText(blocks: blocks)
    case .blockViews:
      ComponentBlocksViews(blocks: blocks)
    }
  }
  
  /// The view to display while its content is rendering.
  ///
  /// - Returns: The view's body.
  @MainActor @ViewBuilder private func loadingView() -> some View {
    switch renderingStyle {
    case .empty:
      Text("")
    case .original:
      Text(latex)
    case .progress:
      ProgressView()
    default:
      EmptyView()
    }
  }
  
}

private struct ScaleFactorKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var scaleFactor: CGFloat {
        get { self[ScaleFactorKey.self] }
        set { self[ScaleFactorKey.self] = newValue }
    }
}


// https://stackoverflow.com/questions/30757193/find-out-if-character-in-string-is-emoji
import Foundation
import CoreText

extension UnicodeScalar {
    var isEmoji: Bool {
        switch value {
        case 0x1F600...0x1F64F, // Emoticons
             0x1F300...0x1F5FF, // Misc Symbols and Pictographs
             0x1F680...0x1F6FF, // Transport and Map
             0x1F1E6...0x1F1FF, // Regional country flags
             0x2600...0x26FF, // Misc symbols
             0x2700...0x27BF, // Dingbats
             0xE0020...0xE007F, // Tags
             0xFE00...0xFE0F, // Variation Selectors
             0x1F900...0x1F9FF, // Supplemental Symbols and Pictographs
             0x1F018...0x1F270, // Various asian characters
             0x238C...0x2454, // Misc items
             0x20D0...0x20FF: // Combining Diacritical Marks for Symbols
            return true

        default: return false
        }
    }

    var isZeroWidthJoiner: Bool {
        return value == 8205
    }
}

extension String {
    // Not needed anymore in swift 4.2 and later, using `.count` will give you the correct result
    var glyphCount: Int {
        let richText = NSAttributedString(string: self)
        let line = CTLineCreateWithAttributedString(richText)
        return CTLineGetGlyphCount(line)
    }

    var isSingleEmoji: Bool {
        return glyphCount == 1 && containsEmoji
    }

    var containsEmoji: Bool {
        return unicodeScalars.contains { $0.isEmoji }
    }

    var containsOnlyEmoji: Bool {
        return !isEmpty
            && !unicodeScalars.contains(where: {
                !$0.isEmoji && !$0.isZeroWidthJoiner
            })
    }

    // The next tricks are mostly to demonstrate how tricky it can be to determine emoji's
    // If anyone has suggestions how to improve this, please let me know
    var emojiString: String {
        return emojiScalars.map { String($0) }.reduce("", +)
    }

    var emojis: [String] {
        var scalars: [[UnicodeScalar]] = []
        var currentScalarSet: [UnicodeScalar] = []
        var previousScalar: UnicodeScalar?

        for scalar in emojiScalars {
            if let prev = previousScalar, !prev.isZeroWidthJoiner, !scalar.isZeroWidthJoiner {
                scalars.append(currentScalarSet)
                currentScalarSet = []
            }
            currentScalarSet.append(scalar)

            previousScalar = scalar
        }

        scalars.append(currentScalarSet)

        return scalars.map { $0.map { String($0) }.reduce("", +) }
    }

    fileprivate var emojiScalars: [UnicodeScalar] {
        var chars: [UnicodeScalar] = []
        var previous: UnicodeScalar?
        for cur in unicodeScalars {
            if let previous = previous, previous.isZeroWidthJoiner, cur.isEmoji {
                chars.append(previous)
                chars.append(cur)

            } else if cur.isEmoji {
                chars.append(cur)
            }

            previous = cur
        }

        return chars
    }
}
