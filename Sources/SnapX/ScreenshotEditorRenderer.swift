import AppKit
import CoreGraphics
@preconcurrency import CoreImage
@preconcurrency import CoreImage.CIFilterBuiltins

enum ScreenshotEditorRenderer {
    private static let ciContext = CIContext()

    static func render(image: NSImage, annotations: [ScreenshotEditorAnnotation]) -> NSImage {
        let size = image.size
        let renderedImage = NSImage(size: size)
        renderedImage.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            renderedImage.unlockFocus()
            return image
        }

        context.interpolationQuality = .high
        image.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)

        if annotations.contains(where: { annotation in
            if case .mosaic = annotation {
                return true
            }
            return false
        }), let cgImage = image.cgImageRepresentation,
           let pixelatedCGImage = makePixelatedCGImage(for: cgImage) {
            drawMosaics(annotations, pixelatedImage: pixelatedCGImage, in: context, size: size)
        }

        drawVectors(annotations, in: context, size: size)
        renderedImage.unlockFocus()
        return renderedImage
    }

    static func makePixelatedPreviewImage(for image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImageRepresentation,
              let pixelatedCGImage = makePixelatedCGImage(for: cgImage) else {
            return nil
        }

        return NSImage(cgImage: pixelatedCGImage, size: image.size)
    }

    private static func makePixelatedCGImage(for cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.pixellate()
        filter.inputImage = ciImage
        filter.scale = 18

        guard let outputImage = filter.outputImage?.cropped(to: ciImage.extent) else {
            return nil
        }

        return ciContext.createCGImage(outputImage, from: outputImage.extent)
    }

    private static func drawMosaics(
        _ annotations: [ScreenshotEditorAnnotation],
        pixelatedImage: CGImage,
        in context: CGContext,
        size: CGSize
    ) {
        for annotation in annotations {
            guard case let .mosaic(mosaic) = annotation else { continue }

            if mosaic.points.count == 1, let point = mosaic.points.first {
                let convertedPoint = appKitPoint(fromTopLeftPoint: point, canvasSize: size)
                let rect = CGRect(
                    x: convertedPoint.x - (mosaic.brushSize / 2),
                    y: convertedPoint.y - (mosaic.brushSize / 2),
                    width: mosaic.brushSize,
                    height: mosaic.brushSize
                )
                context.saveGState()
                context.addEllipse(in: rect)
                context.clip()
                context.draw(pixelatedImage, in: CGRect(origin: .zero, size: size))
                context.restoreGState()
                continue
            }

            let path = CGMutablePath()
            if let first = mosaic.points.first {
                path.move(to: appKitPoint(fromTopLeftPoint: first, canvasSize: size))
                for point in mosaic.points.dropFirst() {
                    path.addLine(to: appKitPoint(fromTopLeftPoint: point, canvasSize: size))
                }
            }

            let strokedPath = path.copy(
                strokingWithWidth: mosaic.brushSize,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 1
            )

            context.saveGState()
            context.addPath(strokedPath)
            context.clip()
            context.draw(pixelatedImage, in: CGRect(origin: .zero, size: size))
            context.restoreGState()
        }
    }

    private static func drawVectors(
        _ annotations: [ScreenshotEditorAnnotation],
        in context: CGContext,
        size: CGSize
    ) {
        for annotation in annotations {
            switch annotation {
            case let .rectangle(rectangle):
                let path = CGPath(
                    roundedRect: appKitRect(fromTopLeftRect: rectangle.rect, canvasSize: size),
                    cornerWidth: 6,
                    cornerHeight: 6,
                    transform: nil
                )
                context.setStrokeColor(rectangle.color.nsColor.cgColor)
                context.setLineWidth(rectangle.lineWidth)
                context.addPath(path)
                context.strokePath()

            case let .highlight(highlight):
                let rect = appKitRect(fromTopLeftRect: highlight.rect, canvasSize: size)
                let path = CGPath(
                    roundedRect: rect,
                    cornerWidth: 6,
                    cornerHeight: 6,
                    transform: nil
                )
                context.setFillColor(highlight.color.nsColor.withAlphaComponent(highlight.opacity).cgColor)
                context.addPath(path)
                context.fillPath()

            case let .arrow(arrow):
                let start = appKitPoint(fromTopLeftPoint: arrow.start, canvasSize: size)
                let end = appKitPoint(fromTopLeftPoint: arrow.end, canvasSize: size)
                context.setStrokeColor(arrow.color.nsColor.cgColor)
                context.setLineWidth(arrow.lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.beginPath()
                context.move(to: start)
                context.addLine(to: end)

                let angle = atan2(end.y - start.y, end.x - start.x)
                let headLength = max(arrow.lineWidth * 4.8, 12)
                let leftPoint = CGPoint(
                    x: end.x - cos(angle - .pi / 6) * headLength,
                    y: end.y - sin(angle - .pi / 6) * headLength
                )
                let rightPoint = CGPoint(
                    x: end.x - cos(angle + .pi / 6) * headLength,
                    y: end.y - sin(angle + .pi / 6) * headLength
                )
                context.move(to: end)
                context.addLine(to: leftPoint)
                context.move(to: end)
                context.addLine(to: rightPoint)
                context.strokePath()

            case let .line(line):
                let start = appKitPoint(fromTopLeftPoint: line.start, canvasSize: size)
                let end = appKitPoint(fromTopLeftPoint: line.end, canvasSize: size)
                context.setStrokeColor(line.color.nsColor.cgColor)
                context.setLineWidth(line.lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.beginPath()
                context.move(to: start)
                context.addLine(to: end)
                context.strokePath()

            case let .pen(pen):
                context.setStrokeColor(pen.color.nsColor.cgColor)
                context.setLineWidth(pen.lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.beginPath()
                if let first = pen.points.first {
                    context.move(to: appKitPoint(fromTopLeftPoint: first, canvasSize: size))
                    for point in pen.points.dropFirst() {
                        context.addLine(to: appKitPoint(fromTopLeftPoint: point, canvasSize: size))
                    }
                }
                context.strokePath()

            case let .text(text):
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping

                var fontTraits: NSFontDescriptor.SymbolicTraits = []
                if text.isBold {
                    fontTraits.insert(.bold)
                }
                if text.isItalic {
                    fontTraits.insert(.italic)
                }

                let baseFont = NSFont.systemFont(ofSize: text.fontSize, weight: text.isBold ? .bold : .semibold)
                var font = baseFont

                if text.isItalic {
                    let descriptor = baseFont.fontDescriptor.withSymbolicTraits(fontTraits)
                    font = NSFont(descriptor: descriptor, size: text.fontSize) ?? baseFont
                }

                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: text.color.nsColor,
                    .paragraphStyle: paragraph,
                ]

                if text.isUnderline {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    attributes[.underlineColor] = text.color.nsColor
                }

                let attributedText = NSAttributedString(string: text.text, attributes: attributes)
                let textHeight = max(size.height - text.origin.y - 8, text.fontSize + 12)
                let textRect = CGRect(
                    x: text.origin.x,
                    y: size.height - text.origin.y - textHeight,
                    width: size.width - text.origin.x - 8,
                    height: textHeight
                )
                attributedText.draw(in: textRect)

            case .mosaic:
                break
            }
        }
    }

    private static func appKitPoint(fromTopLeftPoint point: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: point.x,
            y: canvasSize.height - point.y
        )
    }

    private static func appKitRect(fromTopLeftRect rect: CGRect, canvasSize: CGSize) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: canvasSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

extension NSImage {
    var cgImageRepresentation: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        if let cgImage = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return cgImage
        }

        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.cgImage
    }

    var pngRepresentation: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}