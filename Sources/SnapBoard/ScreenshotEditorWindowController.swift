import AppKit
import Carbon.HIToolbox
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
    private var keyMonitor: Any?

    init(
        image: NSImage,
        sourceRect: CGRect?,
        existingWindow: NSWindow? = nil,
        onPin: @escaping (NSImage) -> Void,
        onCopy: @escaping (NSImage) -> Void,
        onClose: @escaping () -> Void
    ) {
        viewModel = ScreenshotEditorViewModel(image: image)
        self.onPin = onPin
        self.onCopy = onCopy
        self.onClose = onClose
        layout = Self.makeLayout(for: image.size, sourceRect: sourceRect)

        let window = existingWindow ?? ScreenshotEditorWindow(
            contentRect: layout.screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        super.init(window: window)
        configureWindow(window)
        installKeyMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        onClose()
    }

    private func configureWindow(_ window: NSWindow) {
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.setFrame(layout.screenFrame, display: true)

        // Apply theme
        ThemeManager.shared.applyTheme(to: window)

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
        .preferredColorScheme(ThemeManager.shared.currentTheme.colorScheme)

        window.contentView = NSHostingView(rootView: rootView)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                self.close()
                return nil
            }

            if event.keyCode == UInt16(kVK_Return) {
                self.completeEditing()
                return nil
            }

            let commandFlags: NSEvent.ModifierFlags = [.command]
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == commandFlags,
               event.charactersIgnoringModifiers?.lowercased() == "z" {
                self.viewModel.undoLastAnnotation()
                return nil
            }

            // Tool switching shortcuts (1-7)
            if let character = event.charactersIgnoringModifiers?.first {
                switch character {
                case "1":
                    self.viewModel.activeTool = .rectangle
                    return nil
                case "2":
                    self.viewModel.activeTool = .highlight
                    return nil
                case "3":
                    self.viewModel.activeTool = .text
                    return nil
                case "4":
                    self.viewModel.activeTool = .arrow
                    return nil
                case "5":
                    self.viewModel.activeTool = .line
                    return nil
                case "6":
                    self.viewModel.activeTool = .pen
                    return nil
                case "7":
                    self.viewModel.activeTool = .mosaic
                    return nil
                default:
                    break
                }
            }

            return event
        }
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
        guard !viewModel.isExtractingText else { return }

        let image = viewModel.renderedImage()
        guard let cgImage = image.cgImageRepresentation else {
            NSSound.beep()
            viewModel.showToast("无法提取文字")
            return
        }

        viewModel.isExtractingText = true
        viewModel.showToast("正在提取文字…")

        Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            do {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                try handler.perform([request])
                let text = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                await MainActor.run {
                    self.viewModel.isExtractingText = false
                    guard !text.isEmpty else {
                        NSSound.beep()
                        self.viewModel.showToast("未识别到文字")
                        return
                    }

                    ScreenshotEditorFileIO.copyTextToPasteboard(text)
                    self.viewModel.showToast("文字已复制到剪贴板")
                    RecognizedTextPresenter.present(text: text, parentWindow: self.window)
                }
            } catch {
                await MainActor.run {
                    self.viewModel.isExtractingText = false
                    NSSound.beep()
                    self.viewModel.showToast("提取失败")
                }
            }
        }
    }

    private static func makeLayout(for imageSize: CGSize, sourceRect: CGRect?) -> ScreenshotEditorLayout {
        let targetScreen = NSScreen.screens.first { screen in
            guard let sourceRect else { return false }
            return screen.frame.intersects(sourceRect)
        } ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]

        let screenFrame = targetScreen.frame
        let visibleFrame = targetScreen.visibleFrame
        let outerMargin: CGFloat = 8
        let toolbarWidth: CGFloat = min(max(544, imageSize.width * 0.52), visibleFrame.width - 24)
        let toolbarHeight: CGFloat = 56
        let toolbarSpacing: CGFloat = 14

        let imageGlobalRect: CGRect
        let displayScale: CGFloat

        if let sourceRect {
            let clampedSourceRect = sourceRect.intersection(screenFrame)
            imageGlobalRect = (clampedSourceRect.isNull || clampedSourceRect.isEmpty ? sourceRect : clampedSourceRect).integral
            displayScale = imageGlobalRect.width / max(imageSize.width, 1)
        } else {
            let maxImageWidth = max(screenFrame.width - 32, 200)
            let maxImageHeight = max(screenFrame.height - 110, 140)
            let widthScale = maxImageWidth / max(imageSize.width, 1)
            let heightScale = maxImageHeight / max(imageSize.height, 1)
            let scale = min(1, widthScale, heightScale)

            let displayImageSize = CGSize(
                width: max(imageSize.width * scale, 80),
                height: max(imageSize.height * scale, 60)
            )

            imageGlobalRect = resolvedImageGlobalRect(
                sourceRect: nil,
                displayImageSize: displayImageSize,
                screenFrame: screenFrame,
                margin: outerMargin
            )
            displayScale = displayImageSize.width / max(imageSize.width, 1)
        }

        let toolbarGlobalRect = resolvedToolbarGlobalRect(
            imageRect: imageGlobalRect,
            visibleFrame: visibleFrame,
            toolbarWidth: toolbarWidth,
            toolbarHeight: toolbarHeight,
            spacing: toolbarSpacing,
            margin: outerMargin
        )

        return ScreenshotEditorLayout(
            screenFrame: screenFrame,
            screenSize: screenFrame.size,
            imageRect: localRect(fromGlobalRect: imageGlobalRect, in: screenFrame),
            toolbarRect: localRect(fromGlobalRect: toolbarGlobalRect, in: screenFrame),
            displayScale: max(displayScale, 0.01)
        )
    }

    private static func resolvedImageGlobalRect(
        sourceRect: CGRect?,
        displayImageSize: CGSize,
        screenFrame: CGRect,
        margin: CGFloat
    ) -> CGRect {
        let origin: CGPoint
        if let sourceRect {
            origin = CGPoint(
                x: sourceRect.minX,
                y: sourceRect.maxY - displayImageSize.height
            )
        } else {
            origin = CGPoint(
                x: screenFrame.midX - (displayImageSize.width / 2),
                y: screenFrame.midY - (displayImageSize.height / 2)
            )
        }

        return CGRect(
            x: clampedAxis(origin.x, minBound: screenFrame.minX + margin, maxBound: screenFrame.maxX - displayImageSize.width - margin),
            y: clampedAxis(origin.y, minBound: screenFrame.minY + margin, maxBound: screenFrame.maxY - displayImageSize.height - margin),
            width: displayImageSize.width,
            height: displayImageSize.height
        ).integral
    }

    private static func resolvedToolbarGlobalRect(
        imageRect: CGRect,
        visibleFrame: CGRect,
        toolbarWidth: CGFloat,
        toolbarHeight: CGFloat,
        spacing: CGFloat,
        margin: CGFloat
    ) -> CGRect {
        let x = clampedAxis(
            imageRect.midX - (toolbarWidth / 2),
            minBound: visibleFrame.minX + margin,
            maxBound: visibleFrame.maxX - toolbarWidth - margin
        )

        let belowY = imageRect.minY - toolbarHeight - spacing
        if belowY >= visibleFrame.minY + margin {
            return CGRect(x: x, y: belowY, width: toolbarWidth, height: toolbarHeight).integral
        }

        let aboveY = imageRect.maxY + spacing
        if aboveY + toolbarHeight <= visibleFrame.maxY - margin {
            return CGRect(x: x, y: aboveY, width: toolbarWidth, height: toolbarHeight).integral
        }

        let fallbackY = clampedAxis(
            visibleFrame.minY + margin,
            minBound: visibleFrame.minY + margin,
            maxBound: visibleFrame.maxY - toolbarHeight - margin
        )
        return CGRect(x: x, y: fallbackY, width: toolbarWidth, height: toolbarHeight).integral
    }

    private static func localRect(fromGlobalRect rect: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func clampedAxis(_ value: CGFloat, minBound: CGFloat, maxBound: CGFloat) -> CGFloat {
        let resolvedMaxBound = max(minBound, maxBound)
        return min(max(value, minBound), resolvedMaxBound)
    }
}

private final class ScreenshotEditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct ScreenshotEditorLayout {
    let screenFrame: CGRect
    let screenSize: CGSize
    let imageRect: CGRect
    let toolbarRect: CGRect
    let displayScale: CGFloat
}

@MainActor
private final class ScreenshotEditorViewModel: ObservableObject {
    let image: NSImage
    let pixelatedPreviewImage: NSImage?

    @Published var activeTool: ScreenshotEditorTool = .rectangle
    @Published var selectedColor: ScreenshotAnnotationColor = .red
    @Published var selectedLineStyle: RectangleLineStyle = .solid
    @Published var textFontSize: CGFloat = 24
    @Published var textIsBold: Bool = false
    @Published var textIsItalic: Bool = false
    @Published var textIsUnderline: Bool = false
    @Published var annotations: [ScreenshotEditorAnnotation] = []
    @Published var isExtractingText = false
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

private enum ScreenshotAnnotationColor: String, CaseIterable, Identifiable {
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

private enum RectangleLineStyle {
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

private struct RectangleAnnotation {
    let id = UUID()
    let rect: CGRect
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
    let lineStyle: RectangleLineStyle
}

private struct HighlightAnnotation {
    let id = UUID()
    let rect: CGRect
    let color: ScreenshotAnnotationColor
    let opacity: CGFloat
}

private struct ArrowAnnotation {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
}

private struct LineAnnotation {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
}

private struct PenAnnotation {
    let id = UUID()
    let points: [CGPoint]
    let color: ScreenshotAnnotationColor
    let lineWidth: CGFloat
}

private struct TextAnnotation {
    let id = UUID()
    let origin: CGPoint
    let text: String
    let color: ScreenshotAnnotationColor
    let fontSize: CGFloat
    let isBold: Bool
    let isItalic: Bool
    let isUnderline: Bool
}

private struct MosaicAnnotation {
    let id = UUID()
    let points: [CGPoint]
    let brushSize: CGFloat
}

private enum ScreenshotEditorAnnotation: Identifiable {
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

private struct DraftArrow {
    let start: CGPoint
    let end: CGPoint
}

private struct DraftLine {
    let start: CGPoint
    let end: CGPoint
}

private struct ScreenshotEditorRootView: View {
    private static let selectionFrameColor = Color(red: 0.2, green: 0.86, blue: 0.56)

    @ObservedObject var viewModel: ScreenshotEditorViewModel
    let layout: ScreenshotEditorLayout
    let onClose: () -> Void
    let onDone: () -> Void
    let onPin: () -> Void
    let onSave: () -> Void
    let onExtractText: () -> Void

    @State private var draftRectangle: CGRect?
    @State private var draftHighlight: CGRect?
    @State private var draftArrow: DraftArrow?
    @State private var draftLine: DraftLine?
    @State private var draftPenPoints: [CGPoint] = []
    @State private var draftMosaicPoints: [CGPoint] = []
    @State private var draftTextOrigin: CGPoint?
    @State private var draftText = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var showToolShortcuts: Bool = false

    private let rectangleLineWidth: CGFloat = 4
    private let arrowLineWidth: CGFloat = 4
    private let lineLineWidth: CGFloat = 4
    private let penLineWidth: CGFloat = 4
    private let mosaicBrushSize: CGFloat = 28
    private let highlightOpacity: CGFloat = 0.35

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScreenshotEditorBackdropView(
                screenSize: layout.screenSize,
                imageRect: layout.imageRect
            )

            imageStage
                .frame(width: layout.imageRect.width, height: layout.imageRect.height)
                .offset(x: layout.imageRect.minX, y: layout.imageRect.minY)

            toolbar
                .fixedSize()
                .frame(width: layout.toolbarRect.width, height: layout.toolbarRect.height)
                .offset(x: layout.toolbarRect.minX, y: layout.toolbarRect.minY)

            if let toastMessage = viewModel.toastMessage {
                ToastView(message: toastMessage)
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).animation(.spring(response: 0.35, dampingFraction: 0.75)),
                        removal: .move(edge: .top).combined(with: .opacity).animation(.smooth(duration: 0.2))
                    ))
            }

            if showToolShortcuts {
                ToolShortcutsOverlay()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.75)),
                        removal: .scale(scale: 0.95).combined(with: .opacity).animation(.smooth(duration: 0.2))
                    ))
            }
        }
        .frame(width: layout.screenSize.width, height: layout.screenSize.height)
        .background(Color.clear)
        .onChange(of: viewModel.activeTool) { _ in
            commitTextDraftIfNeeded()
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.25).delay(0.05)) {
                showToolShortcuts = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.smooth(duration: 0.25)) {
                    showToolShortcuts = false
                }
            }
        }
    }

    private var imageStage: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: layout.imageRect.width, height: layout.imageRect.height)

            if let pixelatedPreviewImage = viewModel.pixelatedPreviewImage,
               hasVisibleMosaicContent {
                Image(nsImage: pixelatedPreviewImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: layout.imageRect.width, height: layout.imageRect.height)
                    .mask(
                        MosaicMaskView(
                            annotations: viewModel.annotations,
                            draftPoints: draftMosaicPoints,
                            imageSize: viewModel.image.size,
                            displaySize: layout.imageRect.size
                        )
                    )
            }

            annotationOverlay

            if let draftTextOrigin {
                draftTextEditor(at: draftTextOrigin)
            }
        }
        .overlay(selectionChrome)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(tapGesture)
        .onTapGesture(count: 2) {
            onDone()
        }
    }

    private var selectionChrome: some View {
        SelectionFrameChromeView(
            size: layout.imageRect.size,
            borderColor: Self.selectionFrameColor
        )
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

            if let draftHighlight {
                let path = Path(roundedRect: draftHighlight, cornerRadius: 4)
                context.fill(
                    path,
                    with: .color(viewModel.selectedColor.swiftUIColor.opacity(highlightOpacity))
                )
                context.stroke(
                    path,
                    with: .color(viewModel.selectedColor.swiftUIColor),
                    style: StrokeStyle(lineWidth: 1)
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

            if let draftLine {
                var path = Path()
                path.move(to: draftLine.start)
                path.addLine(to: draftLine.end)
                context.stroke(
                    path,
                    with: .color(viewModel.selectedColor.swiftUIColor),
                    style: StrokeStyle(
                        lineWidth: displayStrokeWidth(for: lineLineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            if !draftPenPoints.isEmpty {
                var path = Path()
                if let first = draftPenPoints.first {
                    path.move(to: first)
                    for point in draftPenPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                context.stroke(
                    path,
                    with: .color(viewModel.selectedColor.swiftUIColor),
                    style: StrokeStyle(
                        lineWidth: displayStrokeWidth(for: penLineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .frame(width: layout.imageRect.width, height: layout.imageRect.height)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(ScreenshotEditorTool.allCases) { tool in
                    if tool == .text {
                        toolbarTextButton(
                            title: "文字",
                            isSelected: viewModel.activeTool == tool
                        ) {
                            switchTool(to: tool)
                        }
                    } else {
                        toolbarButton(
                            icon: tool.symbolName,
                            title: tool.title,
                            isSelected: viewModel.activeTool == tool
                        ) {
                            switchTool(to: tool)
                        }
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
                                        .stroke(viewModel.selectedColor == color ? Color.white : Color.clear, lineWidth: 2)
                                )
                                .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if viewModel.activeTool == .text {
                toolbarDivider

                HStack(spacing: 6) {
                    // Font size control
                    Button {
                        viewModel.textFontSize = max(12, viewModel.textFontSize - 4)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help("减小字号")

                    Text("\(Int(viewModel.textFontSize))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .frame(width: 24)

                    Button {
                        viewModel.textFontSize = min(72, viewModel.textFontSize + 4)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help("增大字号")

                    toolbarDivider

                    // Bold
                    Button {
                        viewModel.textIsBold.toggle()
                    } label: {
                        Image(systemName: "bold")
                            .font(.system(size: 13, weight: viewModel.textIsBold ? .bold : .semibold))
                            .foregroundStyle(viewModel.textIsBold ? Color.accentColor : Color.white.opacity(0.9))
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(viewModel.textIsBold ? Color.white.opacity(0.9) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("加粗")

                    // Italic
                    Button {
                        viewModel.textIsItalic.toggle()
                    } label: {
                        Image(systemName: "italic")
                            .font(.system(size: 13, weight: viewModel.textIsItalic ? .bold : .semibold))
                            .foregroundStyle(viewModel.textIsItalic ? Color.accentColor : Color.white.opacity(0.9))
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(viewModel.textIsItalic ? Color.white.opacity(0.9) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("斜体")

                    // Underline
                    Button {
                        viewModel.textIsUnderline.toggle()
                    } label: {
                        Image(systemName: "underline")
                            .font(.system(size: 13, weight: viewModel.textIsUnderline ? .bold : .semibold))
                            .foregroundStyle(viewModel.textIsUnderline ? Color.accentColor : Color.white.opacity(0.9))
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(viewModel.textIsUnderline ? Color.white.opacity(0.9) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("下划线")
                }
            }

            toolbarDivider

            toolbarButton(icon: "arrow.uturn.backward", title: "撤销", isSelected: false, isDisabled: !viewModel.canUndo) {
                triggerEditingAction {
                    viewModel.undoLastAnnotation()
                }
            }

            toolbarButton(icon: "text.viewfinder", title: "提取文字", isSelected: false, isDisabled: viewModel.isExtractingText) {
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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1, height: 24)
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

    private func toolbarTextButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.9))
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(buttonBackground(isSelected: isSelected, accent: false, isDisabled: false))
                )
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func buttonForeground(isSelected: Bool, accent: Bool, isDisabled: Bool) -> Color {
        if isDisabled {
            return Color.white.opacity(0.32)
        }

        if accent || isSelected {
            return .white
        }

        return Color(nsColor: .labelColor).opacity(0.92)
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

                case .highlight:
                    draftHighlight = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(current.x - start.x),
                        height: abs(current.y - start.y)
                    ).integral

                case .arrow:
                    draftArrow = DraftArrow(start: start, end: current)

                case .line:
                    draftLine = DraftLine(start: start, end: current)

                case .pen:
                    if draftPenPoints.isEmpty {
                        draftPenPoints = [start]
                    }
                    if let last = draftPenPoints.last,
                       hypot(last.x - current.x, last.y - current.y) >= 2 {
                        draftPenPoints.append(current)
                    }

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
                                lineWidth: rectangleLineWidth,
                                lineStyle: .solid
                            )
                        )
                    )

                case .highlight:
                    defer { draftHighlight = nil }
                    guard let draftHighlight, draftHighlight.width >= 8, draftHighlight.height >= 8 else { return }
                    viewModel.addAnnotation(
                        .highlight(
                            HighlightAnnotation(
                                rect: displayRectToImageRect(draftHighlight),
                                color: viewModel.selectedColor,
                                opacity: highlightOpacity
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

                case .line:
                    defer { draftLine = nil }
                    guard hypot(end.x - start.x, end.y - start.y) >= 10 else { return }
                    viewModel.addAnnotation(
                        .line(
                            LineAnnotation(
                                start: displayPointToImagePoint(start),
                                end: displayPointToImagePoint(end),
                                color: viewModel.selectedColor,
                                lineWidth: lineLineWidth
                            )
                        )
                    )

                case .pen:
                    defer { draftPenPoints = [] }
                    guard draftPenPoints.count >= 2 else { return }
                    viewModel.addAnnotation(
                        .pen(
                            PenAnnotation(
                                points: draftPenPoints.map(displayPointToImagePoint),
                                color: viewModel.selectedColor,
                                lineWidth: penLineWidth
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

            case let .highlight(highlight):
                let rect = imageRectToDisplayRect(highlight.rect)
                let path = Path(roundedRect: rect, cornerRadius: 4)
                context.fill(
                    path,
                    with: .color(highlight.color.swiftUIColor.opacity(highlight.opacity))
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

            case let .line(line):
                var path = Path()
                path.move(to: imagePointToDisplayPoint(line.start))
                path.addLine(to: imagePointToDisplayPoint(line.end))
                context.stroke(
                    path,
                    with: .color(line.color.swiftUIColor),
                    style: StrokeStyle(
                        lineWidth: displayStrokeWidth(for: line.lineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            case let .pen(pen):
                var path = Path()
                let displayPoints = pen.points.map(imagePointToDisplayPoint)
                if let first = displayPoints.first {
                    path.move(to: first)
                    for point in displayPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                context.stroke(
                    path,
                    with: .color(pen.color.swiftUIColor),
                    style: StrokeStyle(
                        lineWidth: displayStrokeWidth(for: pen.lineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            case let .text(text):
                let fontSize = max(text.fontSize * layout.displayScale, 14)
                let weight: Font.Weight = text.isBold ? .bold : .semibold

                var textView = Text(text.text)
                    .font(Font.system(size: fontSize, weight: weight))

                if text.isItalic {
                    textView = textView.italic()
                }

                if text.isUnderline {
                    textView = textView.underline()
                }

                var resolvedText = context.resolve(textView)
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
            .font(textFont)
            .foregroundStyle(viewModel.selectedColor.swiftUIColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: min(240, layout.imageRect.width - 24), alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.76))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .position(
                x: min(origin.x + 120, layout.imageRect.width - 120),
                y: min(origin.y + 18, layout.imageRect.height - 18)
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

    private var textFont: Font {
        let weight: Font.Weight = viewModel.textIsBold ? .bold : .semibold
        let design: Font.Design = .default

        if viewModel.textIsItalic {
            return Font.system(
                size: max(viewModel.textFontSize * layout.displayScale, 14),
                weight: weight,
                design: design
            ).italic()
        }

        return Font.system(
            size: max(viewModel.textFontSize * layout.displayScale, 14),
            weight: weight,
            design: design
        )
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
                    fontSize: viewModel.textFontSize,
                    isBold: viewModel.textIsBold,
                    isItalic: viewModel.textIsItalic,
                    isUnderline: viewModel.textIsUnderline
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
            x: min(max(point.x, 0), layout.imageRect.width),
            y: min(max(point.y, 0), layout.imageRect.height)
        )
    }

    private func clampedTextOrigin(for point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 12), max(layout.imageRect.width - 228, 12)),
            y: min(max(point.y, 12), max(layout.imageRect.height - 40, 12))
        )
    }

    private func imagePointToDisplayPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * layout.displayScale,
            y: point.y * layout.displayScale
        )
    }

    private func displayPointToImagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x / layout.displayScale,
            y: point.y / layout.displayScale
        )
    }

    private func imageRectToDisplayRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * layout.displayScale,
            y: rect.origin.y * layout.displayScale,
            width: rect.width * layout.displayScale,
            height: rect.height * layout.displayScale
        )
    }

    private func displayRectToImageRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x / layout.displayScale,
            y: rect.origin.y / layout.displayScale,
            width: rect.width / layout.displayScale,
            height: rect.height / layout.displayScale
        )
    }

    private func displayStrokeWidth(for imageStrokeWidth: CGFloat) -> CGFloat {
        max(imageStrokeWidth * layout.displayScale, 2)
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

private struct ScreenshotEditorBackdropView: View {
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

private struct SelectionFrameChromeView: View {
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

private enum ScreenshotEditorRenderer {
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
    private static var windowController: RecognizedTextWindowController?

    @MainActor
    static func present(text: String, parentWindow: NSWindow?) {
        windowController?.close()

        let controller = RecognizedTextWindowController(text: text) {
            windowController = nil
        }
        windowController = controller
        controller.show(relativeTo: parentWindow)
    }
}

@MainActor
private final class RecognizedTextWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(text: String, onClose: @escaping () -> Void) {
        self.onClose = onClose

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)
        configureWindow(panel, text: text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        if let parent = window?.parent {
            parent.removeChildWindow(window!)
        }
        onClose()
    }

    func show(relativeTo parentWindow: NSWindow?) {
        guard let window else { return }

        if let parentWindow {
            parentWindow.addChildWindow(window, ordered: .above)
            let origin = CGPoint(
                x: parentWindow.frame.midX - (window.frame.width / 2),
                y: parentWindow.frame.midY - (window.frame.height / 2)
            )
            window.setFrameOrigin(origin)
            parentWindow.makeKey()
        } else {
            window.center()
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func configureWindow(_ window: NSPanel, text: String) {
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.title = "提取到的文字"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let container = NSView(frame: CGRect(x: 0, y: 0, width: 420, height: 280))
        container.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "识别结果已复制到剪贴板。")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.string = text
        textView.textContainerInset = CGSize(width: 2, height: 6)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        container.addSubview(subtitle)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            subtitle.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            subtitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            subtitle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            scrollView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
        ])

        window.contentView = container
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

// MARK: - Toast View

private struct ToastView: View {
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

private struct ToolShortcutsOverlay: View {
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
