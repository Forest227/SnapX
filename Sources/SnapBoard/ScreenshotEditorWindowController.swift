import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import Vision

@MainActor
final class ScreenshotEditorWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: ScreenshotEditorViewModel
    private let onPin: (NSImage) -> Void
    private let onCopy: (NSImage) -> Void
    private let onClose: () -> Void
    private let layout: ScreenshotEditorLayout

    init(
        image: NSImage,
        sourceRect: CGRect?,
        onPin: @escaping (NSImage) -> Void,
        onCopy: @escaping (NSImage) -> Void,
        onClose: @escaping () -> Void
    ) {
        viewModel = ScreenshotEditorViewModel(image: image)
        self.onPin = onPin
        self.onCopy = onCopy
        self.onClose = onClose

        layout = Self.makeLayout(for: image.size, sourceRect: sourceRect)
        let window = ScreenshotEditorWindow(
            contentRect: CGRect(origin: .zero, size: layout.windowSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        super.init(window: window)
        configureWindow(window, sourceRect: sourceRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func configureWindow(_ window: NSWindow, sourceRect: CGRect?) {
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false

        let rootView = ScreenshotEditorRootView(
            viewModel: viewModel,
            layout: layout,
            onClose: { [weak self] in
                self?.close()
            },
            onDone: { [weak self] in
                self?.completeEditing()
            },
            onPin: { [weak self] in
                self?.pinImage()
            },
            onSave: { [weak self] in
                self?.saveImageToDownloads()
            },
            onExtractText: { [weak self] in
                self?.extractTextFromImage()
            }
        )

        window.contentView = NSHostingView(rootView: rootView)
        positionWindow(window, sourceRect: sourceRect)
    }

    private func completeEditing() {
        let image = viewModel.renderedImage()
        onCopy(image)
        close()
    }

    private func pinImage() {
        let image = viewModel.renderedImage()
        onCopy(image)
        onPin(image)
        close()
    }

    private func saveImageToDownloads() {
        do {
            let image = viewModel.renderedImage()
            let url = try ScreenshotEditorFileIO.saveImageToDownloads(image)
            viewModel.showToast("已保存到 \(url.lastPathComponent)")
        } catch {
            NSSound.beep()
            viewModel.showToast("保存失败")
        }
    }

    private func extractTextFromImage() {
        let image = viewModel.renderedImage()
        guard let cgImage = image.cgImageRepresentation else {
            NSSound.beep()
            viewModel.showToast("无法提取文字")
            return
        }

        viewModel.showToast("正在提取文字…")

        Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            do {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                try handler.perform([request])
                let text = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                await MainActor.run {
                    guard !text.isEmpty else {
                        NSSound.beep()
                        self.viewModel.showToast("未识别到文字")
                        return
                    }

                    ScreenshotEditorFileIO.copyTextToPasteboard(text)
                    self.viewModel.showToast("文字已复制到剪贴板")
                    RecognizedTextPresenter.present(text: text)
                }
            } catch {
                await MainActor.run {
                    NSSound.beep()
                    self.viewModel.showToast("提取失败")
                }
            }
        }
    }

    private func positionWindow(_ window: NSWindow, sourceRect: CGRect?) {
        let targetScreen = screen(for: sourceRect) ?? screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = targetScreen?.visibleFrame ?? CGRect(origin: .zero, size: layout.windowSize)

        let desiredImageOrigin = desiredImageFrameOrigin(
            for: sourceRect,
            visibleFrame: visibleFrame,
            imageSize: layout.displayImageSize
        )

        let imageInsets = layout.imageInsets
        let proposedOrigin: CGPoint
        switch layout.toolbarPlacement {
        case .below:
            proposedOrigin = CGPoint(
                x: desiredImageOrigin.x - imageInsets.x,
                y: desiredImageOrigin.y - imageInsets.y
            )

        case .above:
            proposedOrigin = CGPoint(
                x: desiredImageOrigin.x - imageInsets.x,
                y: desiredImageOrigin.y - layout.contentPadding
            )
        }

        let clampedOrigin = CGPoint(
            x: clampedAxisOrigin(
                proposedOrigin.x,
                minBound: visibleFrame.minX + 8,
                maxBound: visibleFrame.maxX - layout.windowSize.width - 8
            ),
            y: clampedAxisOrigin(
                proposedOrigin.y,
                minBound: visibleFrame.minY + 8,
                maxBound: visibleFrame.maxY - layout.windowSize.height - 8
            )
        )

        window.setFrameOrigin(clampedOrigin)
    }

    private func clampedAxisOrigin(_ value: CGFloat, minBound: CGFloat, maxBound: CGFloat) -> CGFloat {
        let resolvedMaxBound = max(minBound, maxBound)
        return min(max(value, minBound), resolvedMaxBound)
    }

    private func desiredImageFrameOrigin(
        for sourceRect: CGRect?,
        visibleFrame: CGRect,
        imageSize: CGSize
    ) -> CGPoint {
        guard let sourceRect else {
            return CGPoint(
                x: visibleFrame.midX - (imageSize.width / 2),
                y: visibleFrame.midY - (imageSize.height / 2)
            )
        }

        return CGPoint(
            x: sourceRect.midX - (imageSize.width / 2),
            y: sourceRect.midY - (imageSize.height / 2)
        )
    }

    private func screen(for sourceRect: CGRect?) -> NSScreen? {
        guard let sourceRect else { return nil }

        return NSScreen.screens.first { screen in
            screen.frame.intersects(sourceRect)
        }
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    private static func makeLayout(for imageSize: CGSize, sourceRect: CGRect?) -> ScreenshotEditorLayout {
        let targetScreen = NSScreen.screens.first { screen in
            guard let sourceRect else { return false }
            return screen.frame.intersects(sourceRect)
        } ?? NSScreen.main ?? NSScreen.screens.first

        let visibleFrame = targetScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let contentPadding: CGFloat = 12
        let toolbarHeight: CGFloat = 58
        let spacing: CGFloat = 12

        let maxImageWidth = max(visibleFrame.width - (contentPadding * 2) - 16, 240)
        let maxImageHeight = max(visibleFrame.height - toolbarHeight - spacing - (contentPadding * 2) - 20, 180)
        let widthScale = maxImageWidth / max(imageSize.width, 1)
        let heightScale = maxImageHeight / max(imageSize.height, 1)
        let scale = min(1, widthScale, heightScale)

        let displayImageSize = CGSize(
            width: max(imageSize.width * scale, 180),
            height: max(imageSize.height * scale, 120)
        )

        let toolbarWidth = min(
            max(500, min(displayImageSize.width, 620)),
            visibleFrame.width - 24
        )
        let contentWidth = max(displayImageSize.width, toolbarWidth) + (contentPadding * 2)
        let contentHeight = displayImageSize.height + toolbarHeight + spacing + (contentPadding * 2)

        let sourceMinY = sourceRect?.minY ?? visibleFrame.midY
        let toolbarPlacement: ScreenshotEditorLayout.ToolbarPlacement =
            (sourceMinY - toolbarHeight - spacing - 24 >= visibleFrame.minY) ? .below : .above

        return ScreenshotEditorLayout(
            displayImageSize: displayImageSize,
            toolbarWidth: toolbarWidth,
            toolbarHeight: toolbarHeight,
            contentPadding: contentPadding,
            spacing: spacing,
            toolbarPlacement: toolbarPlacement,
            windowSize: CGSize(width: contentWidth, height: contentHeight)
        )
    }
}

private final class ScreenshotEditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct ScreenshotEditorLayout {
    enum ToolbarPlacement {
        case below
        case above
    }

    let displayImageSize: CGSize
    let toolbarWidth: CGFloat
    let toolbarHeight: CGFloat
    let contentPadding: CGFloat
    let spacing: CGFloat
    let toolbarPlacement: ToolbarPlacement
    let windowSize: CGSize

    var imageInsets: CGPoint {
        switch toolbarPlacement {
        case .below:
            CGPoint(
                x: (windowSize.width - displayImageSize.width) / 2,
                y: contentPadding + toolbarHeight + spacing
            )

        case .above:
            CGPoint(
                x: (windowSize.width - displayImageSize.width) / 2,
                y: contentPadding
            )
        }
    }
}

@MainActor
private final class ScreenshotEditorViewModel: ObservableObject {
    let image: NSImage
    let pixelatedPreviewImage: NSImage?

    @Published var activeTool: ScreenshotEditorTool = .rectangle
    @Published var selectedColor: ScreenshotAnnotationColor = .green
    @Published var annotations: [ScreenshotEditorAnnotation] = []
    @Published var toastMessage: String?

    private var toastDismissWorkItem: DispatchWorkItem?

    init(image: NSImage) {
        self.image = image
        pixelatedPreviewImage = ScreenshotEditorRenderer.makePixelatedPreviewImage(for: image)
    }

    var canUndo: Bool {
        !annotations.isEmpty
    }

    func addAnnotation(_ annotation: ScreenshotEditorAnnotation) {
        annotations.append(annotation)
    }

    func undoLastAnnotation() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
    }

    func renderedImage() -> NSImage {
        ScreenshotEditorRenderer.render(image: image, annotations: annotations)
    }

    func showToast(_ message: String) {
        toastDismissWorkItem?.cancel()
        toastMessage = message

        let workItem = DispatchWorkItem { [weak self] in
            self?.toastMessage = nil
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }
}

private enum ScreenshotEditorTool: String, CaseIterable, Identifiable {
    case rectangle
    case text
    case arrow
    case mosaic

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .rectangle:
            "square"
        case .text:
            "textformat"
        case .arrow:
            "arrow.up.right"
        case .mosaic:
            "square.grid.3x3.fill"
        }
    }

    var title: String {
        switch self {
        case .rectangle:
            "线框"
        case .text:
            "文字"
        case .arrow:
            "箭头"
        case .mosaic:
            "马赛克"
        }
    }

    var supportsColorSelection: Bool {
        switch self {
        case .mosaic:
            false
        case .rectangle, .text, .arrow:
            true
        }
    }
}

private enum ScreenshotAnnotationColor: String, CaseIterable, Identifiable {
    case green
    case red
    case orange
    case yellow
    case blue

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .green:
            Color(nsColor: .systemGreen)
        case .red:
            Color(nsColor: .systemRed)
        case .orange:
            Color(nsColor: .systemOrange)
        case .yellow:
            Color(nsColor: .systemYellow)
        case .blue:
            Color(nsColor: .systemBlue)
        }
    }

    var nsColor: NSColor {
        switch self {
        case .green:
            .systemGreen
        case .red:
            .systemRed
        case .orange:
            .systemOrange
        case .yellow:
            .systemYellow
        case .blue:
            .systemBlue
        }
    }
}

private struct RectangleAnnotation {
    let id = UUID()
    let rect: CGRect
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
}

private struct ArrowAnnotation {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
}

private struct TextAnnotation {
    let id = UUID()
    let origin: CGPoint
    let text: String
    let color: ScreenshotAnnotationColor
    let fontSize: CGFloat
}

private struct MosaicAnnotation {
    let id = UUID()
    let points: [CGPoint]
    let brushSize: CGFloat
}

private enum ScreenshotEditorAnnotation: Identifiable {
    case rectangle(RectangleAnnotation)
    case arrow(ArrowAnnotation)
    case text(TextAnnotation)
    case mosaic(MosaicAnnotation)

    var id: UUID {
        switch self {
        case let .rectangle(annotation):
            annotation.id
        case let .arrow(annotation):
            annotation.id
        case let .text(annotation):
            annotation.id
        case let .mosaic(annotation):
            annotation.id
        }
    }
}

private struct DraftArrow {
    let start: CGPoint
    let end: CGPoint
}

private struct ScreenshotEditorRootView: View {
    @ObservedObject var viewModel: ScreenshotEditorViewModel
    let layout: ScreenshotEditorLayout
    let onClose: () -> Void
    let onDone: () -> Void
    let onPin: () -> Void
    let onSave: () -> Void
    let onExtractText: () -> Void

    @State private var draftRectangle: CGRect?
    @State private var draftArrow: DraftArrow?
    @State private var draftMosaicPoints: [CGPoint] = []
    @State private var draftTextOrigin: CGPoint?
    @State private var draftText = ""
    @FocusState private var isTextFieldFocused: Bool

    private let rectangleLineWidth: CGFloat = 4
    private let arrowLineWidth: CGFloat = 4
    private let textFontSize: CGFloat = 24
    private let mosaicBrushSize: CGFloat = 28

    var body: some View {
        VStack(spacing: layout.spacing) {
            if layout.toolbarPlacement == .above {
                toolbar
            }

            imageStage

            if layout.toolbarPlacement == .below {
                toolbar
            }
        }
        .padding(layout.contentPadding)
        .frame(width: layout.windowSize.width, height: layout.windowSize.height)
        .background(Color.clear)
        .onChange(of: viewModel.activeTool) { _ in
            commitTextDraftIfNeeded()
        }
    }

    private var imageStage: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: viewModel.image)
                .resizable()
                .interpolation(.high)
                .frame(width: layout.displayImageSize.width, height: layout.displayImageSize.height)

            if let pixelatedPreviewImage = viewModel.pixelatedPreviewImage,
               hasVisibleMosaicContent {
                Image(nsImage: pixelatedPreviewImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: layout.displayImageSize.width, height: layout.displayImageSize.height)
                    .mask(
                        MosaicMaskView(
                            annotations: viewModel.annotations,
                            draftPoints: draftMosaicPoints,
                            imageSize: viewModel.image.size,
                            displaySize: layout.displayImageSize
                        )
                    )
            }

            annotationOverlay

            if let draftTextOrigin {
                draftTextEditor(at: draftTextOrigin)
            }

            if let toastMessage = viewModel.toastMessage {
                HStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7), in: Capsule())
                }
                .padding(16)
            }
        }
        .frame(width: layout.displayImageSize.width, height: layout.displayImageSize.height)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.82), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(tapGesture)
    }

    private var annotationOverlay: some View {
        Canvas { context, _ in
            drawAnnotations(in: &context, annotations: viewModel.annotations)

            if let draftRectangle {
                let path = Path(roundedRect: draftRectangle, cornerRadius: 4)
                context.stroke(
                    path,
                    with: .color(viewModel.selectedColor.swiftUIColor),
                    style: StrokeStyle(lineWidth: displayStrokeWidth(for: rectangleLineWidth))
                )
            }

            if let draftArrow {
                let path = arrowPath(
                    start: draftArrow.start,
                    end: draftArrow.end,
                    lineWidth: displayStrokeWidth(for: arrowLineWidth)
                )
                context.stroke(
                    path,
                    with: .color(viewModel.selectedColor.swiftUIColor),
                    style: StrokeStyle(
                        lineWidth: displayStrokeWidth(for: arrowLineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .frame(width: layout.displayImageSize.width, height: layout.displayImageSize.height)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(ScreenshotEditorTool.allCases) { tool in
                    toolbarButton(
                        icon: tool.symbolName,
                        title: tool.title,
                        isSelected: viewModel.activeTool == tool
                    ) {
                        switchTool(to: tool)
                    }
                }
            }

            if viewModel.activeTool.supportsColorSelection {
                toolbarDivider

                HStack(spacing: 10) {
                    ForEach(ScreenshotAnnotationColor.allCases) { color in
                        Button {
                            viewModel.selectedColor = color
                        } label: {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            viewModel.selectedColor == color ? Color.white : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                                .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            toolbarDivider

            toolbarButton(icon: "arrow.uturn.backward", title: "撤销", isSelected: false, isDisabled: !viewModel.canUndo) {
                triggerEditingAction {
                    viewModel.undoLastAnnotation()
                }
            }

            toolbarButton(icon: "text.viewfinder", title: "提取文字", isSelected: false) {
                triggerEditingAction(action: onExtractText)
            }

            toolbarButton(icon: "square.and.arrow.down", title: "保存", isSelected: false) {
                triggerEditingAction(action: onSave)
            }

            toolbarButton(icon: "pin", title: "钉住", isSelected: false) {
                triggerEditingAction(action: onPin)
            }

            toolbarDivider

            toolbarButton(icon: "xmark", title: "关闭", isSelected: false) {
                discardDraftText()
                onClose()
            }

            toolbarButton(icon: "checkmark", title: "完成", isSelected: false, accent: true) {
                triggerEditingAction(action: onDone)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: layout.toolbarWidth, height: layout.toolbarHeight)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 16, y: 10)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1, height: 26)
    }

    private func toolbarButton(
        icon: String,
        title: String,
        isSelected: Bool,
        isDisabled: Bool = false,
        accent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(buttonForeground(isSelected: isSelected, accent: accent, isDisabled: isDisabled))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(buttonBackground(isSelected: isSelected, accent: accent, isDisabled: isDisabled))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(title)
    }

    private func buttonForeground(isSelected: Bool, accent: Bool, isDisabled: Bool) -> Color {
        if isDisabled {
            return Color.white.opacity(0.32)
        }

        if accent || isSelected {
            return .white
        }

        return Color(nsColor: .labelColor).opacity(0.9)
    }

    private func buttonBackground(isSelected: Bool, accent: Bool, isDisabled: Bool) -> Color {
        if isDisabled {
            return Color.white.opacity(0.04)
        }

        if accent {
            return Color.accentColor
        }

        if isSelected {
            return Color.accentColor.opacity(0.82)
        }

        return Color.white.opacity(0.1)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard draftTextOrigin == nil else { return }

                let start = clampedDisplayPoint(for: value.startLocation)
                let current = clampedDisplayPoint(for: value.location)

                switch viewModel.activeTool {
                case .rectangle:
                    draftRectangle = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(current.x - start.x),
                        height: abs(current.y - start.y)
                    ).integral

                case .arrow:
                    draftArrow = DraftArrow(start: start, end: current)

                case .mosaic:
                    if draftMosaicPoints.isEmpty {
                        draftMosaicPoints = [start]
                    }
                    if let last = draftMosaicPoints.last,
                       hypot(last.x - current.x, last.y - current.y) >= 2 {
                        draftMosaicPoints.append(current)
                    }

                case .text:
                    break
                }
            }
            .onEnded { value in
                let start = clampedDisplayPoint(for: value.startLocation)
                let end = clampedDisplayPoint(for: value.location)

                switch viewModel.activeTool {
                case .rectangle:
                    defer { draftRectangle = nil }
                    guard let draftRectangle, draftRectangle.width >= 8, draftRectangle.height >= 8 else { return }
                    viewModel.addAnnotation(
                        .rectangle(
                            RectangleAnnotation(
                                rect: displayRectToImageRect(draftRectangle),
                                color: viewModel.selectedColor,
                                lineWidth: rectangleLineWidth
                            )
                        )
                    )

                case .arrow:
                    defer { draftArrow = nil }
                    guard hypot(end.x - start.x, end.y - start.y) >= 10 else { return }
                    viewModel.addAnnotation(
                        .arrow(
                            ArrowAnnotation(
                                start: displayPointToImagePoint(start),
                                end: displayPointToImagePoint(end),
                                color: viewModel.selectedColor,
                                lineWidth: arrowLineWidth
                            )
                        )
                    )

                case .mosaic:
                    defer { draftMosaicPoints = [] }
                    let points = draftMosaicPoints.isEmpty ? [start] : draftMosaicPoints
                    guard !points.isEmpty else { return }
                    viewModel.addAnnotation(
                        .mosaic(
                            MosaicAnnotation(
                                points: points.map(displayPointToImagePoint),
                                brushSize: mosaicBrushSize
                            )
                        )
                    )

                case .text:
                    break
                }
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard viewModel.activeTool == .text else { return }

                let origin = clampedTextOrigin(for: value.location)
                draftTextOrigin = origin
                draftText = ""
                DispatchQueue.main.async {
                    isTextFieldFocused = true
                }
            }
    }

    private func drawAnnotations(in context: inout GraphicsContext, annotations: [ScreenshotEditorAnnotation]) {
        for annotation in annotations {
            switch annotation {
            case let .rectangle(rectangle):
                let rect = imageRectToDisplayRect(rectangle.rect)
                let path = Path(roundedRect: rect, cornerRadius: 4)
                context.stroke(
                    path,
                    with: .color(rectangle.color.swiftUIColor),
                    style: StrokeStyle(lineWidth: displayStrokeWidth(for: rectangle.lineWidth))
                )

            case let .arrow(arrow):
                let path = arrowPath(
                    start: imagePointToDisplayPoint(arrow.start),
                    end: imagePointToDisplayPoint(arrow.end),
                    lineWidth: displayStrokeWidth(for: arrow.lineWidth)
                )
                context.stroke(
                    path,
                    with: .color(arrow.color.swiftUIColor),
                    style: StrokeStyle(
                        lineWidth: displayStrokeWidth(for: arrow.lineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            case let .text(text):
                let fontSize = text.fontSize * displayScale
                var resolvedText = context.resolve(
                    Text(text.text)
                        .font(.system(size: fontSize, weight: .semibold))
                )
                resolvedText.shading = .color(text.color.swiftUIColor)
                context.draw(resolvedText, at: imagePointToDisplayPoint(text.origin), anchor: .topLeading)

            case .mosaic:
                break
            }
        }
    }

    private func arrowPath(start: CGPoint, end: CGPoint, lineWidth: CGFloat) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(lineWidth * 4.6, 12)
        let leftPoint = CGPoint(
            x: end.x - cos(angle - .pi / 6) * headLength,
            y: end.y - sin(angle - .pi / 6) * headLength
        )
        let rightPoint = CGPoint(
            x: end.x - cos(angle + .pi / 6) * headLength,
            y: end.y - sin(angle + .pi / 6) * headLength
        )
        path.move(to: end)
        path.addLine(to: leftPoint)
        path.move(to: end)
        path.addLine(to: rightPoint)

        return path
    }

    private func draftTextEditor(at origin: CGPoint) -> some View {
        TextField("输入文字", text: $draftText)
            .textFieldStyle(.plain)
            .font(.system(size: max(textFontSize * displayScale, 14), weight: .semibold))
            .foregroundStyle(viewModel.selectedColor.swiftUIColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: min(240, layout.displayImageSize.width - 24), alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.76))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .position(
                x: min(origin.x + 120, layout.displayImageSize.width - 120),
                y: min(origin.y + 18, layout.displayImageSize.height - 18)
            )
            .focused($isTextFieldFocused)
            .onSubmit {
                commitTextDraftIfNeeded()
            }
            .onChange(of: isTextFieldFocused) { focused in
                if !focused {
                    commitTextDraftIfNeeded()
                }
            }
    }

    private func switchTool(to tool: ScreenshotEditorTool) {
        commitTextDraftIfNeeded()
        viewModel.activeTool = tool
    }

    private func triggerEditingAction(action: () -> Void) {
        commitTextDraftIfNeeded()
        action()
    }

    private func commitTextDraftIfNeeded() {
        guard let draftTextOrigin else { return }
        defer {
            self.draftTextOrigin = nil
            draftText = ""
            isTextFieldFocused = false
        }

        let trimmedText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        viewModel.addAnnotation(
            .text(
                TextAnnotation(
                    origin: displayPointToImagePoint(draftTextOrigin),
                    text: trimmedText,
                    color: viewModel.selectedColor,
                    fontSize: textFontSize
                )
            )
        )
    }

    private func discardDraftText() {
        draftTextOrigin = nil
        draftText = ""
        isTextFieldFocused = false
    }

    private func clampedDisplayPoint(for point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), layout.displayImageSize.width),
            y: min(max(point.y, 0), layout.displayImageSize.height)
        )
    }

    private func clampedTextOrigin(for point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 12), max(layout.displayImageSize.width - 228, 12)),
            y: min(max(point.y, 12), max(layout.displayImageSize.height - 40, 12))
        )
    }

    private func imagePointToDisplayPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * displayScale,
            y: point.y * displayScale
        )
    }

    private func displayPointToImagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x / displayScale,
            y: point.y / displayScale
        )
    }

    private func imageRectToDisplayRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * displayScale,
            y: rect.origin.y * displayScale,
            width: rect.width * displayScale,
            height: rect.height * displayScale
        )
    }

    private func displayRectToImageRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x / displayScale,
            y: rect.origin.y / displayScale,
            width: rect.width / displayScale,
            height: rect.height / displayScale
        )
    }

    private func displayStrokeWidth(for imageStrokeWidth: CGFloat) -> CGFloat {
        max(imageStrokeWidth * displayScale, 2)
    }

    private var displayScale: CGFloat {
        layout.displayImageSize.width / max(viewModel.image.size.width, 1)
    }

    private var hasVisibleMosaicContent: Bool {
        viewModel.annotations.contains { annotation in
            if case .mosaic = annotation {
                return true
            }
            return false
        } || !draftMosaicPoints.isEmpty
    }
}

private struct MosaicMaskView: View {
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
        let lineWidth = max((brushSize * displayScale), 10)
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

private enum ScreenshotEditorRenderer {
    private static let ciContext = CIContext()

    static func render(image: NSImage, annotations: [ScreenshotEditorAnnotation]) -> NSImage {
        guard let cgImage = image.cgImageRepresentation else { return image }

        let size = image.size
        let renderedImage = NSImage(size: size)
        renderedImage.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            renderedImage.unlockFocus()
            return image
        }

        context.interpolationQuality = .high
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))

        if annotations.contains(where: { annotation in
            if case .mosaic = annotation {
                return true
            }
            return false
        }), let pixelatedCGImage = makePixelatedCGImage(for: cgImage) {
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
                let rect = CGRect(
                    x: point.x - (mosaic.brushSize / 2),
                    y: point.y - (mosaic.brushSize / 2),
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
                path.move(to: first)
                for point in mosaic.points.dropFirst() {
                    path.addLine(to: point)
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
                    roundedRect: rectangle.rect,
                    cornerWidth: 6,
                    cornerHeight: 6,
                    transform: nil
                )
                context.setStrokeColor(rectangle.color.nsColor.cgColor)
                context.setLineWidth(rectangle.lineWidth)
                context.addPath(path)
                context.strokePath()

            case let .arrow(arrow):
                context.setStrokeColor(arrow.color.nsColor.cgColor)
                context.setLineWidth(arrow.lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.beginPath()
                context.move(to: arrow.start)
                context.addLine(to: arrow.end)

                let angle = atan2(arrow.end.y - arrow.start.y, arrow.end.x - arrow.start.x)
                let headLength = max(arrow.lineWidth * 4.8, 12)
                let leftPoint = CGPoint(
                    x: arrow.end.x - cos(angle - .pi / 6) * headLength,
                    y: arrow.end.y - sin(angle - .pi / 6) * headLength
                )
                let rightPoint = CGPoint(
                    x: arrow.end.x - cos(angle + .pi / 6) * headLength,
                    y: arrow.end.y - sin(angle + .pi / 6) * headLength
                )
                context.move(to: arrow.end)
                context.addLine(to: leftPoint)
                context.move(to: arrow.end)
                context.addLine(to: rightPoint)
                context.strokePath()

            case let .text(text):
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: text.fontSize, weight: .semibold),
                    .foregroundColor: text.color.nsColor,
                    .paragraphStyle: paragraph,
                ]

                let attributedText = NSAttributedString(string: text.text, attributes: attributes)
                let textRect = CGRect(
                    origin: text.origin,
                    size: CGSize(width: size.width - text.origin.x - 8, height: size.height - text.origin.y - 8)
                )
                attributedText.draw(in: textRect)

            case .mosaic:
                break
            }
        }
    }
}

private enum ScreenshotEditorFileIO {
    static func saveImageToDownloads(_ image: NSImage) throws -> URL {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"

        let baseName = "SnapBoard \(formatter.string(from: Date()))"
        var destinationURL = downloadsURL.appendingPathComponent(baseName).appendingPathExtension("png")
        var attempt = 1
        while FileManager.default.fileExists(atPath: destinationURL.path) {
            destinationURL = downloadsURL
                .appendingPathComponent("\(baseName) \(attempt)")
                .appendingPathExtension("png")
            attempt += 1
        }

        guard let pngData = image.pngRepresentation else {
            throw CocoaError(.fileWriteUnknown)
        }

        try pngData.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    static func copyTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private enum RecognizedTextPresenter {
    @MainActor
    static func present(text: String) {
        let alert = NSAlert()
        alert.messageText = "提取到的文字"
        alert.informativeText = "识别结果已复制到剪贴板。"
        alert.addButton(withTitle: "关闭")
        alert.accessoryView = makeAccessoryView(for: text)
        alert.runModal()
    }

    @MainActor
    private static func makeAccessoryView(for text: String) -> NSView {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 360, height: 180))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }
}

private extension NSImage {
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
