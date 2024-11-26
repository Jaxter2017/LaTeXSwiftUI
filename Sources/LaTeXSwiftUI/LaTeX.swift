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
    return convertArrayToEquation(emojiReplaced)
}

private func replaceBlackboardBold(_ latex: String) -> String {
    print("Input: \(latex)")
    
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

    print("Output: \(result)")
    return result
}

func convertArrayToEquation(_ input: String) -> String {
    var output = input

    // Regular expression pattern to match \begin{array}{...}...\end{array}
    let pattern = #"\\begin\{array\}\{[^\}]*\}(.*?)\\end\{array\}"#
    let regex = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])

    let nsrange = NSRange(output.startIndex..<output.endIndex, in: output)

    // Find matches in input
    let matches = regex.matches(in: output, options: [], range: nsrange)

    // Process matches in reverse order to maintain correct ranges
    for match in matches.reversed() {
        // Full range of the entire \begin{array}...\end{array}
        let fullRange = match.range(at: 0)
        // Range of the content inside the array environment
        let contentRange = match.range(at: 1)

        if let fullRange = Range(fullRange, in: output),
           let contentRange = Range(contentRange, in: output) {
            let content = String(output[contentRange])
            // Replace '\\' with '\newline '
            let modifiedContent = content.replacingOccurrences(of: #"\\\\\s*"#, with: #"\\newline "#, options: .regularExpression)
            // Replace the entire \begin{array}...\end{array} with the modified content, trimming extra whitespace
            output.replaceSubrange(fullRange, with: modifiedContent.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    return output
}

func handleEmojis(_ input: String) -> String {
    // If the string contains no emoji, return it unchanged
    if !input.containsEmoji {
        return input
    }
    
    var result = input
    
    // Remove outer \( \) LaTeX delimiters
    result = result.replacingOccurrences(of: "\\(", with: "")
    result = result.replacingOccurrences(of: "\\)", with: "")
    
    // Dictionary of LaTeX commands to Unicode symbols
    let latexToUnicode: [(pattern: String, replacement: String)] = [
        // Delimiters
        ("\\(", ""),
        ("\\)", ""),
        
        // Basic operations
        ("\\times", "×"),
        ("\\div", "÷"),
        ("\\cdot", "·"),
        ("\\pm", "±"),
        ("\\mp", "∓"),
        
        // Comparison
        ("\\leq", "≤"),
        ("\\geq", "≥"),
        ("\\neq", "≠"),
        ("\\approx", "≈"),
        ("\\equiv", "≡"),
        
        // Sets and logic
        ("\\in", "∈"),
        ("\\notin", "∉"),
        ("\\subset", "⊂"),
        ("\\supset", "⊃"),
        ("\\cup", "∪"),
        ("\\cap", "∩"),
        ("\\emptyset", "∅"),
        ("\\forall", "∀"),
        ("\\exists", "∃"),
        
        // Arrows
        ("\\rightarrow", "→"),
        ("\\leftarrow", "←"),
        ("\\Rightarrow", "⇒"),
        ("\\Leftarrow", "⇐"),
        ("\\leftrightarrow", "↔"),
        ("\\Leftrightarrow", "⇔"),
        
        // Greek letters (commonly used)
        ("\\alpha", "α"),
        ("\\beta", "β"),
        ("\\gamma", "γ"),
        ("\\delta", "δ"),
        ("\\epsilon", "ε"),
        ("\\theta", "θ"),
        ("\\lambda", "λ"),
        ("\\mu", "μ"),
        ("\\pi", "π"),
        ("\\sigma", "σ"),
        ("\\omega", "ω"),
        
        // Miscellaneous math symbols
        ("\\infty", "∞"),
        ("\\partial", "∂"),
        ("\\nabla", "∇"),
        ("\\therefore", "∴"),
        ("\\because", "∵"),
        ("\\sqrt", "√"),
        
        // Superscripts and subscripts
        ("\\^2", "²"),
        ("\\^3", "³"),
        ("_2", "₂"),
        ("_3", "₃")
    ]
    
    // Handle fractions with regex
    if let fracRegex = try? NSRegularExpression(pattern: "\\\\frac\\{([^}]+)\\}\\{([^}]+)\\}", options: []) {
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = fracRegex.stringByReplacingMatches(
            in: result,
            options: [],
            range: range,
            withTemplate: "$1 ÷ $2"
        )
    }
    
    // Handle square root with regex
    if let sqrtRegex = try? NSRegularExpression(pattern: "\\\\sqrt\\{([^}]+)\\}", options: []) {
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = sqrtRegex.stringByReplacingMatches(
            in: result,
            options: [],
            range: range,
            withTemplate: "√($1)"
        )
    }
    
    // Replace all other LaTeX commands with their Unicode equivalents
    for (pattern, replacement) in latexToUnicode {
        result = result.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: .regularExpression
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
