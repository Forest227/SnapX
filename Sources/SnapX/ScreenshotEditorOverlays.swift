import AppKit
import SwiftUI

// MARK: - Backdrop

struct ScreenshotEditorBackdropView: View {
    let screenSize: CGSize
    let imageRect: CGRect
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            var path = Path(CGRect(origin: .zero, size: size))
            path.addPath(Path(roundedRect: imageRect.insetBy(dx: -1, dy: -1), cornerRadius: 8))

            let opacity = colorScheme == .dark ? 0.65 : 0.48
            context.fill(
                path,
                with: .color(Color.black.opacity(opacity)),
                style: FillStyle(eoFill: true)
            )
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }
}

// MARK: - Selection Frame Chrome

struct SelectionFrameChromeView: View {
    let size: CGSize
    let borderColor: Color

    private let handleSize: CGFloat = 7

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(borderColor, lineWidth: 2)

            ForEach(Array(handleCenters.enumerated()), id: \.offset) { _, center in
                Rectangle()
                    .fill(borderColor)
                    .frame(width: handleSize, height: handleSize)
                    .position(center)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var handleCenters: [CGPoint] {
        let width = size.width
        let height = size.height

        return [
            CGPoint(x: 0, y: 0),
            CGPoint(x: width / 2, y: 0),
            CGPoint(x: width, y: 0),
            CGPoint(x: 0, y: height / 2),
            CGPoint(x: width, y: height / 2),
            CGPoint(x: 0, y: height),
            CGPoint(x: width / 2, y: height),
            CGPoint(x: width, y: height),
        ]
    }
}

// MARK: - Crop Handle Hit Area

struct CropHandleHitView: View {
    let rect: CGRect
    let tolerance: CGFloat

    var body: some View {
        Canvas { _, _ in }
            .contentShape(hitShape, eoFill: true)
    }

    private var hitShape: Path {
        var path = Path()
        path.addRect(rect.insetBy(dx: -tolerance, dy: -tolerance))
        let inner = rect.insetBy(dx: tolerance, dy: tolerance)
        if inner.width > 0, inner.height > 0 {
            path.addRect(inner)
        }
        return path
    }
}

// MARK: - Mosaic Mask

struct MosaicMaskView: View {
    let annotations: [ScreenshotEditorAnnotation]
    let draftPoints: [CGPoint]
    let imageSize: CGSize
    let displaySize: CGSize

    var body: some View {
        Canvas { context, _ in
            for annotation in annotations {
                guard case let .mosaic(mosaic) = annotation else { continue }
                strokeMosaic(points: mosaic.points, brushSize: mosaic.brushSize, in: &context)
            }

            if !draftPoints.isEmpty {
                strokeDraft(points: draftPoints, in: &context)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
    }

    private func strokeMosaic(points: [CGPoint], brushSize: CGFloat, in context: inout GraphicsContext) {
        let displayPoints = points.map(imagePointToDisplayPoint)
        let lineWidth = max(brushSize * displayScale, 10)
        stroke(points: displayPoints, lineWidth: lineWidth, in: &context)
    }

    private func strokeDraft(points: [CGPoint], in context: inout GraphicsContext) {
        stroke(points: points, lineWidth: max(28 * displayScale, 10), in: &context)
    }

    private func stroke(points: [CGPoint], lineWidth: CGFloat, in context: inout GraphicsContext) {
        guard let first = points.first else { return }

        if points.count == 1 {
            let rect = CGRect(
                x: first.x - (lineWidth / 2),
                y: first.y - (lineWidth / 2),
                width: lineWidth,
                height: lineWidth
            )
            context.fill(Path(ellipseIn: rect), with: .color(.white))
            return
        }

        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        context.stroke(
            path,
            with: .color(.white),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private var displayScale: CGFloat {
        displaySize.width / max(imageSize.width, 1)
    }

    private func imagePointToDisplayPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * displayScale,
            y: point.y * displayScale
        )
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        .scaleEffect(isAnimating ? 1 : 0.85)
        .opacity(isAnimating ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Tool Shortcuts Overlay

struct ToolShortcutsOverlay: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                shortcutItem(key: "1", tool: "线框")
                shortcutItem(key: "2", tool: "高亮")
                shortcutItem(key: "3", tool: "文字")
                shortcutItem(key: "4", tool: "箭头")
            }
            HStack(spacing: 12) {
                shortcutItem(key: "5", tool: "直线")
                shortcutItem(key: "6", tool: "画笔")
                shortcutItem(key: "7", tool: "马赛克")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
        .scaleEffect(isAnimating ? 1 : 0.9)
        .opacity(isAnimating ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                isAnimating = true
            }
        }
    }

    private func shortcutItem(key: String, tool: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.2))
                )

            Text(tool)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
