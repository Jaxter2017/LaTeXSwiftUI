//
//  Renderer.swift
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

import Foundation
import MathJaxSwift
import SwiftUI
import SVGView

#if os(iOS)
import UIKit
#else
import Cocoa
#endif

/// Renders equation components and updates their rendered image and offset
/// values.
internal class Renderer: ObservableObject {
  
  // MARK: Types
  
  /// A set of values used to create an array of parsed component blocks.
  struct ParsingSource: Equatable {
    
    /// The LaTeX input.
    let latex: String
    
    /// Whether or not the HTML should be unencoded.
    let unencodeHTML: Bool
    
    /// The parsing mode.
    let parsingMode: LaTeX.ParsingMode
  }
  
  // MARK: Public properties
  
  /// Whether or not the view's blocks have been rendered.
  @MainActor @Published var rendered: Bool = false
  
  /// Whether or not the receiver is currently rendering.
  @MainActor @Published var isRendering: Bool = false
  
  /// The rendered blocks.
  @MainActor @Published var blocks: [ComponentBlock] = []
  
  // MARK: Private properties
  
  /// The LaTeX input's parsed blocks.
  private var _parsedBlocks: [ComponentBlock]? = nil
  
  /// The set of values used to create the parsed blocks.
  private var _parsingSource: ParsingSource? = nil
  
  /// Semaphore for thread-safe access to `_parsedBlocks`.
  private var _parsedBlocksSemaphore = DispatchSemaphore(value: 1)
  
}

// MARK: Public methods

extension Renderer {
  
  /// Returns whether the view's components are cached.
  ///
  /// - Parameters:
  ///   - latex: The LaTeX input string.
  ///   - unencodeHTML: The `unencodeHTML` environment variable.
  ///   - parsingMode: The `parsingMode` environment variable.
  ///   - processEscapes: The `processEscapes` environment variable.
  ///   - errorMode: The `errorMode` environment variable.
  ///   - font: The `font environment` variable.
  ///   - displayScale: The `displayScale` environment variable.
  func isCached(
    latex: String,
    unencodeHTML: Bool,
    parsingMode: LaTeX.ParsingMode,
    processEscapes: Bool,
    errorMode: LaTeX.ErrorMode,
    font: Font,
    displayScale: CGFloat
  ) -> Bool {
    let texOptions = TeXInputProcessorOptions(processEscapes: processEscapes, errorMode: errorMode)
    return blocksExistInCache(
      parsedBlocks(latex: latex, unencodeHTML: unencodeHTML, parsingMode: parsingMode),
      font: font,
      displayScale: displayScale,
      texOptions: texOptions)
  }
  
  /// Renders the view's components synchronously.
  ///
  /// - Parameters:
  ///   - latex: The LaTeX input string.
  ///   - unencodeHTML: The `unencodeHTML` environment variable.
  ///   - parsingMode: The `parsingMode` environment variable.
  ///   - processEscapes: The `processEscapes` environment variable.
  ///   - errorMode: The `errorMode` environment variable.
  ///   - font: The `font environment` variable.
  ///   - displayScale: The `displayScale` environment variable.
  func renderSync(
    latex: String,
    unencodeHTML: Bool,
    parsingMode: LaTeX.ParsingMode,
    processEscapes: Bool,
    errorMode: LaTeX.ErrorMode,
    font: Font,
    displayScale: CGFloat,
    scaleFactor: CGFloat
  ) -> [ComponentBlock] {
    let texOptions = TeXInputProcessorOptions(processEscapes: processEscapes, errorMode: errorMode)
    return render(
      blocks: parsedBlocks(latex: latex, unencodeHTML: unencodeHTML, parsingMode: parsingMode),
      font: font,
      displayScale: displayScale,
      texOptions: texOptions,
      scaleFactor: scaleFactor)
  }
  
  /// Renders the view's components asynchronously.
  ///
  /// - Parameters:
  ///   - latex: The LaTeX input string.
  ///   - unencodeHTML: The `unencodeHTML` environment variable.
  ///   - parsingMode: The `parsingMode` environment variable.
  ///   - processEscapes: The `processEscapes` environment variable.
  ///   - errorMode: The `errorMode` environment variable.
  ///   - font: The `font environment` variable.
  ///   - displayScale: The `displayScale` environment variable.
  func render(
    latex: String,
    unencodeHTML: Bool,
    parsingMode: LaTeX.ParsingMode,
    processEscapes: Bool,
    errorMode: LaTeX.ErrorMode,
    font: Font,
    displayScale: CGFloat,
    scaleFactor: CGFloat
  ) async {
    let isRen = await isRendering
    let ren = await rendered
    guard !isRen && !ren else {
      return
    }
    await MainActor.run {
      isRendering = true
    }
    
    let texOptions = TeXInputProcessorOptions(processEscapes: processEscapes, errorMode: errorMode)
    let renderedBlocks = await render(
      blocks: parsedBlocks(latex: latex, unencodeHTML: unencodeHTML, parsingMode: parsingMode),
      font: font,
      displayScale: displayScale,
      texOptions: texOptions,
      scaleFactor: scaleFactor)
    
    await MainActor.run {
      blocks = renderedBlocks
      isRendering = false
      rendered = true
    }
  }
  
  /// Converts the component to a `Text` view.
  ///
  /// - Parameters:
  ///   - component: The component to convert.
  ///   - font: The font to use.
  ///   - displayScale: The view's display scale.
  ///   - renderingMode: The image rendering mode.
  ///   - errorMode: The error handling mode.
  ///   - isLastComponentInBlock: Whether or not this is the last component in
  ///     the block that contains it.
  /// - Returns: A text view.
  @MainActor func convertToText(
    component: Component,
    font: Font,
    displayScale: CGFloat,
    renderingMode: Image.TemplateRenderingMode,
    errorMode: LaTeX.ErrorMode,
    blockRenderingMode: LaTeX.BlockMode,
    isInEquationBlock: Bool,
    scaleFactor: CGFloat
  ) -> Text {
    // Get the component's text
    let text: Text
    if let svg = component.svg {
      // Do we have an error?
      if let errorText = svg.errorText, errorMode != .rendered {
        switch errorMode {
        case .original:
          // Use the original tex input
          text = Text(blockRenderingMode == .alwaysInline ? component.originalTextTrimmingNewlines : component.originalText)
        case .error:
          // Use the error text
          text = Text(errorText)
        default:
          text = Text("")
        }
      }
      else if let (image, _, _) = convertToImage(
        component: component,
        font: font,
        displayScale: displayScale,
        renderingMode: renderingMode,
        scaleFactor: scaleFactor
      ) {
        let xHeight = _Font.preferredFont(from: font).xHeight
        let offset = svg.geometry.verticalAlignment.toPoints(xHeight)
        text = Text(image).baselineOffset(blockRenderingMode == .alwaysInline || !isInEquationBlock ? offset : 0)
      }
      else {
        text = Text("")
      }
    }
    else if blockRenderingMode == .alwaysInline {
      text = Text(component.originalTextTrimmingNewlines)
          .baselineOffset(scaleFactor == 2 ? 12 : 0)
    }
    else {
        if component.originalText == " " {
            text = Text("")
        } else {
            text = Text(component.originalText)
        }
    }
    
    return text
  }
  
  /// Creates the image view and its size for the given block.
  ///
  /// If the block isn't an equation block, then this method returns `nil`.
  ///
  /// - Parameter block: The block.
  /// - Returns: The image, its size, and any associated error text.
  @MainActor func convertToImage(
    block: ComponentBlock,
    font: Font,
    displayScale: CGFloat,
    renderingMode: Image.TemplateRenderingMode,
    scaleFactor: CGFloat
  ) -> (Image, CGSize, String?)? {
    guard block.isEquationBlock, let component = block.components.first else {
      return nil
    }
    return convertToImage(
      component: component,
      font: font,
      displayScale: displayScale,
      renderingMode: renderingMode,
      scaleFactor: scaleFactor)
  }
  
  /// Creates an image from an SVG.
  ///
  /// - Parameters:
  ///   - component: The component to convert.
  ///   - font: The view's font.
  ///   - displayScale: The current display scale.
  ///   - renderingMode: The image's rendering mode.
  /// - Returns: An image and its size.
  @MainActor func convertToImage(
    component: Component,
    font: Font,
    displayScale: CGFloat,
    renderingMode: Image.TemplateRenderingMode,
    scaleFactor: CGFloat
  ) -> (Image, CGSize, String?)? {
    guard let svg = component.svg else {
      return nil
    }
    
    // Create our cache key
    let cacheKey = Cache.ImageCacheKey(svg: svg, xHeight: font.xHeight)
    
    // Check the cache for an image
    if let image = Cache.shared.imageCacheValue(for: cacheKey) {
      return (Image(image: image)
        .renderingMode(renderingMode)
        .antialiased(true)
        .interpolation(.high), image.size, svg.errorText)
    }
    
    // Continue with getting the image
//    let width = svg.geometry.width.toPoints(font.xHeight)
//    let height = svg.geometry.height.toPoints(font.xHeight)
      
      // Inject base color into SVG data
      var modifiedSVGData = svg.data
      if let svgString = String(data: modifiedSVGData, encoding: .utf8) {
          #if os(iOS)
          let isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
          #else
          let isDarkMode = NSAppearance.currentDrawing().name == .darkAqua
          #endif
          
          let baseColor = isDarkMode ? "#e5e7eb" : "#3d4d6a"
          let colorInjection = "svg { color: \(baseColor); } text { fill: currentColor; }"
          
          let modifiedSVGString = svgString.replacingOccurrences(
              of: "</svg>",
              with: "<style>\(colorInjection)</style></svg>"
          )
          modifiedSVGData = modifiedSVGString.data(using: .utf8) ?? modifiedSVGData
      }
      
    #if os(iOS)
        let contentSize = UIApplication.shared.preferredContentSizeCategory
        var systemScaleFactor: CGFloat = {
            switch contentSize {
                case .extraSmall: return 0.882758620689655
                case .small: return 0.937931034482759
                case .medium: return 1.0
                case .large: return 1.0448275862069
                case .extraLarge: return 1.16551724137931
                case .extraExtraLarge: return 1.24827586206897
                case .extraExtraExtraLarge: return 1.36551724137931
                case .accessibilityMedium: return 1.64137931034483
                case .accessibilityLarge: return 1.93793103448276
                case .accessibilityExtraLarge: return 2.33793103448276
                case .accessibilityExtraExtraLarge: return 2.77931034482759
                case .accessibilityExtraExtraExtraLarge: return 2.99310344827586
            default: return 1.0
            }
        }()
    #else
        let systemScaleFactor = NSFontMetrics.default.scaledValue(for: 1.0)
    #endif
      
      if scaleFactor == 1 { // don't even worry about it
          systemScaleFactor = 1.0
      }
      
  let width = (svg.geometry.width.toPoints(font.xHeight)) / systemScaleFactor
  let height = (svg.geometry.height.toPoints(font.xHeight)) / systemScaleFactor
    
    // Render the view
    let view = SVGView(data: modifiedSVGData)
    let renderer = ImageRenderer(content: view.frame(width: width * scaleFactor, height: height * scaleFactor))
#if os(iOS)
    renderer.scale = UIScreen.main.scale
    let image = renderer.image
#else
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 1
    let image = renderer.image
#endif
    
    if let image = image {
      Cache.shared.setImageCacheValue(image, for: cacheKey)
      return (Image(image: image)
        .renderingMode(renderingMode)
        .antialiased(true)
        .interpolation(.high), image.size, svg.errorText)
    }
    return nil
  }
  
}

// MARK: Private methods

extension Renderer {
  
  /// Gets the LaTeX input's parsed blocks.
  ///
  /// - Parameters:
  ///   - latex: The LaTeX input string.
  ///   - unencodeHTML: The `unencodeHTML` environment variable.
  ///   - parsingMode: The `parsingMode` environment variable.
  /// - Returns: The parsed blocks.
  private func parsedBlocks(
    latex: String,
    unencodeHTML: Bool,
    parsingMode: LaTeX.ParsingMode
  ) -> [ComponentBlock] {
    _parsedBlocksSemaphore.wait()
    defer { _parsedBlocksSemaphore.signal() }
    
    let currentSource = ParsingSource(latex: latex, unencodeHTML: unencodeHTML, parsingMode: parsingMode)
    if let _parsedBlocks, _parsingSource == currentSource {
      return _parsedBlocks
    }
    
    let blocks = Parser.parse(unencodeHTML ? latex.htmlUnescape() : latex, mode: parsingMode)
    _parsedBlocks = blocks
    _parsingSource = currentSource
    return blocks
  }
  
  /// Gets the error text from a possibly non-nil error.
  ///
  /// - Parameter error: The error.
  /// - Returns: The error text.
  private func getErrorText(from error: Error?) throws -> String? {
    if let mjError = error as? MathJaxError, case .conversionError(let innerError) = mjError {
      return innerError
    }
    else if let error = error {
      throw error
    }
    return nil
  }
  
  /// Renders the components and stores the new images in a new set of
  /// components.
  ///
  /// - Parameters:
  ///   - components: The components to render.
  ///   - xHeight: The xHeight of the font to use.
  ///   - displayScale: The current display scale.
  ///   - texOptions: The MathJax TeX input processor options.
  /// - Returns: An array of components.
  private func render(
    _ components: [Component],
    xHeight: CGFloat,
    displayScale: CGFloat,
    texOptions: TeXInputProcessorOptions,
    scaleFactor: CGFloat
  ) throws -> [Component] {
    // Make sure we have a MathJax instance!
    guard let mathjax = MathJax.svgRenderer else {
      return components
    }
    
    // Iterate through the input components and render
    var renderedComponents = [Component]()
    for component in components {
      // Only render equation components
      guard component.type.isEquation else {
        renderedComponents.append(component)
        continue
      }
      
      // Create our cache key
      let cacheKey = Cache.SVGCacheKey(
        componentText: component.text,
        conversionOptions: component.conversionOptions,
        texOptions: texOptions)
      
      // Do we have the SVG in the cache?
      if let svgData = Cache.shared.dataCacheValue(for: cacheKey) {
        renderedComponents.append(Component(
          text: component.text,
          type: component.type,
          svg: try SVG(data: svgData)))
        continue
      }
      
      // Perform the conversion
      var conversionError: Error?
      let svgString = mathjax.tex2svg(
        component.text,
        styles: false,
        conversionOptions: component.conversionOptions,
        inputOptions: texOptions,
        error: &conversionError)
      
      // Check for a conversion error
      let errorText = try getErrorText(from: conversionError)
      
      // Create and cache the SVG
      let svg = try SVG(svgString: svgString, errorText: errorText)
      Cache.shared.setDataCacheValue(try svg.encoded(), for: cacheKey)
      
      // Save the rendered component
      renderedComponents.append(Component(
        text: component.text,
        type: component.type,
        svg: svg))
    }
    
    // All done
    return renderedComponents
  }
  
  /// Determines and returns whether the blocks are in the renderer's cache.
  ///
  /// - Parameters:
  ///   - blocks: The blocks.
  ///   - font: The `font` environment variable.
  ///   - displayScale: The `displayScale` environment variable.
  ///   - texOptions: The `texOptions` environment variable.
  /// - Returns: Whether the blocks are in the renderer's cache.
  func blocksExistInCache(_ blocks: [ComponentBlock], font: Font, displayScale: CGFloat, texOptions: TeXInputProcessorOptions) -> Bool {
    for block in blocks {
      for component in block.components where component.type.isEquation {
        let dataCacheKey = Cache.SVGCacheKey(
          componentText: component.text,
          conversionOptions: component.conversionOptions,
          texOptions: texOptions)
        guard let svgData = Cache.shared.dataCacheValue(for: dataCacheKey) else {
          return false
        }
        
        guard let svg = try? SVG(data: svgData) else {
          return false
        }
        
        let xHeight = _Font.preferredFont(from: font).xHeight
        let imageCacheKey = Cache.ImageCacheKey(svg: svg, xHeight: xHeight)
        guard Cache.shared.imageCacheValue(for: imageCacheKey) != nil else {
          return false
        }
      }
    }
    return true
  }
  
  /// Renders the view's component blocks.
  ///
  /// - Parameters:
  ///   - blocks: The component blocks.
  ///   - font: The view's font.
  ///   - displayScale: The display scale to render at.
  ///   - texOptions: The MathJax Tex input processor options.
  /// - Returns: An array of rendered blocks.
  func render(
    blocks: [ComponentBlock],
    font: Font,
    displayScale: CGFloat,
    texOptions: TeXInputProcessorOptions,
    scaleFactor: CGFloat
  ) async -> [ComponentBlock] {
    return await withCheckedContinuation({ continuation in
      continuation.resume(returning: render(blocks: blocks, font: font, displayScale: displayScale, texOptions: texOptions, scaleFactor: scaleFactor))
    })
  }
  
  /// Renders the view's component blocks.
  ///
  /// - Parameters:
  ///   - blocks: The component blocks.
  ///   - font: The view's font.
  ///   - displayScale: The display scale to render at.
  ///   - texOptions: The MathJax Tex input processor options.
  /// - Returns: An array of rendered blocks.
  func render(
    blocks: [ComponentBlock],
    font: Font,
    displayScale: CGFloat,
    texOptions: TeXInputProcessorOptions,
    scaleFactor: CGFloat
  ) -> [ComponentBlock] {
    var newBlocks = [ComponentBlock]()
    for block in blocks {
      do {
        let newComponents = try render(
          block.components,
          xHeight: font.xHeight,
          displayScale: displayScale,
          texOptions: texOptions,
          scaleFactor: scaleFactor)
        
        newBlocks.append(ComponentBlock(components: newComponents))
      }
      catch {
        NSLog("Error rendering block: \(error)")
        newBlocks.append(block)
        continue
      }
    }
    
    return newBlocks
  }
  
}
