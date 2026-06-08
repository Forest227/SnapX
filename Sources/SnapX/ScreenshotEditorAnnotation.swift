import AppKit
import SwiftUI

enum ScreenshotEditorTool: String, CaseIterable, Identifiable {
    case rectangle
    case highlight
    case text
    case arrow
    case line
    case pen
    case mosaic

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .rectangle:
            "square"
        case .highlight:
            "rectangle.and.pencil.and.ellipsis"
        case .text:
            "t.square"
        case .arrow:
            "arrow.up.right"
        case .line:
            "line.diagonal"
        case .pen:
            "pencil"
        case .mosaic:
            "square.grid.3x3.fill"
        }
    }

    var title: String {
        switch self {
        case .rectangle:
            "线框"
        case .highlight:
            "高亮"
        case .text:
            "文字"
        case .arrow:
            "箭头"
        case .line:
            "直线"
        case .pen:
            "画笔"
        case .mosaic:
            "马赛克"
        }
    }

    var supportsColorSelection: Bool {
        switch self {
        case .mosaic:
            false
        case .rectangle, .highlight, .text, .arrow, .line, .pen:
            true
        }
    }

    var shortcutKey: String {
        switch self {
        case .rectangle: "1"
        case .highlight: "2"
        case .text: "3"
        case .arrow: "4"
        case .line: "5"
        case .pen: "6"
        case .mosaic: "7"
        }
    }
}

enum ScreenshotAnnotationColor: String, CaseIterable, Identifiable {
    case red
    case green
    case orange
    case yellow
    case blue
    case purple
    case pink
    case white
    case black

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .red: Color(nsColor: .systemRed)
        case .green: Color(nsColor: .systemGreen)
        case .orange: Color(nsColor: .systemOrange)
        case .yellow: Color(nsColor: .systemYellow)
        case .blue: Color(nsColor: .systemBlue)
        case .purple: Color(nsColor: .systemPurple)
        case .pink: Color(nsColor: .systemPink)
        case .white: Color.white
        case .black: Color.black
        }
    }

    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .green: .systemGreen
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .white: .white
        case .black: .black
        }
    }

    static var highlightColors: [ScreenshotAnnotationColor] {
        [.yellow, .green, .orange, .red, .blue, .purple, .pink]
    }
}

enum RectangleLineStyle {
    case solid
    case dashed
    case double

    var dashPattern: [CGFloat]? {
        switch self {
        case .solid: nil
        case .dashed: [8, 4]
        case .double: nil
        }
    }
}

struct RectangleAnnotation {
    let id = UUID()
    let rect: CGRect
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
    let lineStyle: RectangleLineStyle
}

struct HighlightAnnotation {
    let id = UUID()
    let rect: CGRect
    let color: ScreenshotAnnotationColor
    let opacity: CGFloat
}

struct ArrowAnnotation {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
}

struct LineAnnotation {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
}

struct PenAnnotation {
    let id = UUID()
    let points: [CGPoint]
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
}

struct TextAnnotation {
    let id = UUID()
    let origin: CGPoint
    let text: String
    let color: ScreenshotAnnotationColor
    let fontSize: CGFloat
    let isBold: Bool
    let isItalic: Bool
    let isUnderline: Bool
}

struct MosaicAnnotation {
    let id = UUID()
    let points: [CGPoint]
    let brushSize: CGFloat
}

enum ScreenshotEditorAnnotation: Identifiable {
    case rectangle(RectangleAnnotation)
    case highlight(HighlightAnnotation)
    case arrow(ArrowAnnotation)
    case line(LineAnnotation)
    case pen(PenAnnotation)
    case text(TextAnnotation)
    case mosaic(MosaicAnnotation)

    var id: UUID {
        switch self {
        case let .rectangle(annotation): annotation.id
        case let .highlight(annotation): annotation.id
        case let .arrow(annotation): annotation.id
        case let .line(annotation): annotation.id
        case let .pen(annotation): annotation.id
        case let .text(annotation): annotation.id
        case let .mosaic(annotation): annotation.id
        }
    }
}

struct DraftArrow {
    let start: CGPoint
    let end: CGPoint
}

struct DraftLine {
    let start: CGPoint
    let end: CGPoint
}

enum CropEdge {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight
    case move
}