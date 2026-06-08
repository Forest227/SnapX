import AppKit
import SwiftUI

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct ScreenshotEditorRootView: View {
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

    @State private var currentImageRect: CGRect
    @State private var cropAdjustRect: CGRect?
    @State private var isCropDragging = false
    @State private var cropDragEdge: CropEdge?
    @State private var cropDragStart: CGPoint?
    @State private var cropOriginalRect: CGRect?
    @State private var draggingTextIndex: Int?

    init(
        viewModel: ScreenshotEditorViewModel,
        layout: ScreenshotEditorLayout,
        onClose: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onPin: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onExtractText: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.layout = layout
        self.onClose = onClose
        self.onDone = onDone
        self.onPin = onPin
        self.onSave = onSave
        self.onExtractText = onExtractText
        _currentImageRect = State(initialValue: layout.imageRect)
    }

    private let rectangleLineWidth: CGFloat = 4
    private let arrowLineWidth: CGFloat = 4
    private let lineLineWidth: CGFloat = 4
    private let penLineWidth: CGFloat = 4
    private let mosaicBrushSize: CGFloat = 28
    private let highlightOpacity: CGFloat = 0.35
    private let cropHandleSize: CGFloat = 8
    private let cropHandleHitTolerance: CGFloat = 10

    private var currentDisplayScale: CGFloat {
        max(currentImageRect.width / max(viewModel.image.size.width, 1), 0.01)
    }

    private var displayImageRect: CGRect {
        isCropDragging ? (cropAdjustRect ?? currentImageRect) : currentImageRect
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScreenshotEditorBackdropView(
                screenSize: layout.screenSize,
                imageRect: displayImageRect
            )

            imageStage
                .frame(width: currentImageRect.width, height: currentImageRect.height)
                .offset(x: currentImageRect.minX, y: currentImageRect.minY)
                .opacity(isCropDragging ? 0.3 : 1)

            if isCropDragging, let adjustRect = cropAdjustRect, let fullImg = viewModel.cropInfo?.fullScreenImage {
                Image(nsImage: fullImg)
                    .resizable()
                    .frame(width: layout.screenSize.width, height: layout.screenSize.height)
                    .mask(
                        Rectangle()
                            .frame(width: adjustRect.width, height: adjustRect.height)
                            .offset(x: adjustRect.midX - layout.screenSize.width / 2,
                                    y: adjustRect.midY - layout.screenSize.height / 2)
                    )

                SelectionFrameChromeView(
                    size: adjustRect.size,
                    borderColor: Self.selectionFrameColor
                )
                .offset(x: adjustRect.minX, y: adjustRect.minY)
            }

            if viewModel.canAdjustCrop {
                cropHandleOverlay
            }

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
        .onChange(of: viewModel.textDraftDiscardRequest) { shouldDiscard in
            if shouldDiscard {
                discardDraftText()
                viewModel.textDraftDiscardRequest = false
            }
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.25).delay(0.05)) {
                showToolShortcuts = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.smooth(duration: 0.25)) {
                    showToolShortcuts = false
                }
            }
        }
    }

    // MARK: - Image Stage

    private var imageStage: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: currentImageRect.width, height: currentImageRect.height)

            if let pixelatedPreviewImage = viewModel.pixelatedPreviewImage,
               hasVisibleMosaicContent {
                Image(nsImage: pixelatedPreviewImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: currentImageRect.width, height: currentImageRect.height)
                    .mask(
                        MosaicMaskView(
                            annotations: viewModel.annotations,
                            draftPoints: draftMosaicPoints,
                            imageSize: viewModel.image.size,
                            displaySize: currentImageRect.size
                        )
                    )
            }

            annotationOverlay

            if let draftTextOrigin {
                draftTextEditor(at: draftTextOrigin)
            }
        }
        .overlay(isCropDragging ? nil : selectionChrome)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(tapGesture)
        .onTapGesture(count: 2) {
            if viewModel.activeTool == .text && draftTextOrigin != nil {
                commitTextDraftIfNeeded()
            } else {
                onDone()
            }
        }
    }

    private var selectionChrome: some View {
        SelectionFrameChromeView(
            size: currentImageRect.size,
            borderColor: Self.selectionFrameColor
        )
    }

    // MARK: - Annotation Overlay

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
        .frame(width: currentImageRect.width, height: currentImageRect.height)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
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

                    textFormatToggle(icon: "bold", title: "加粗", isOn: viewModel.textIsBold) {
                        viewModel.textIsBold.toggle()
                    }

                    textFormatToggle(icon: "italic", title: "斜体", isOn: viewModel.textIsItalic) {
                        viewModel.textIsItalic.toggle()
                    }

                    textFormatToggle(icon: "underline", title: "下划线", isOn: viewModel.textIsUnderline) {
                        viewModel.textIsUnderline.toggle()
                    }
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

    private func textFormatToggle(icon: String, title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: isOn ? .bold : .semibold))
                .foregroundStyle(isOn ? Color.accentColor : Color.white.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Color.white.opacity(0.9) : Color.clear)
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

    // MARK: - Drag Gesture

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
                    if draftTextOrigin == nil, draggingTextIndex == nil {
                        let tapPoint = displayPointToImagePoint(start)
                        let hitRadius: CGFloat = 20 / currentDisplayScale
                        if let (index, _) = findTextAnnotation(near: tapPoint, radius: hitRadius) {
                            draggingTextIndex = index
                        }
                    }
                    if let dragIndex = draggingTextIndex,
                       case let .text(textAnnotation) = viewModel.annotations[safe: dragIndex] {
                        let dx = displayPointToImagePoint(CGPoint(x: current.x - start.x, y: current.y - start.y))
                        let newOrigin = CGPoint(x: textAnnotation.origin.x + dx.x, y: textAnnotation.origin.y + dx.y)
                        viewModel.annotations[dragIndex] = .text(TextAnnotation(
                            origin: newOrigin,
                            text: textAnnotation.text,
                            color: textAnnotation.color,
                            fontSize: textAnnotation.fontSize,
                            isBold: textAnnotation.isBold,
                            isItalic: textAnnotation.isItalic,
                            isUnderline: textAnnotation.isUnderline
                        ))
                    }
                }
            }
            .onEnded { value in
                if draggingTextIndex != nil {
                    draggingTextIndex = nil
                    return
                }

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

    // MARK: - Tap Gesture

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard viewModel.activeTool == .text else { return }

                commitTextDraftIfNeeded()

                // Check if tapping on an existing text annotation to re-edit
                let tapPoint = displayPointToImagePoint(value.location)
                let hitRadius: CGFloat = 20 / currentDisplayScale
                if let (index, textAnnotation) = findTextAnnotation(near: tapPoint, radius: hitRadius) {
                    viewModel.annotations.remove(at: index)
                    viewModel.selectedColor = textAnnotation.color
                    viewModel.textFontSize = textAnnotation.fontSize
                    viewModel.textIsBold = textAnnotation.isBold
                    viewModel.textIsItalic = textAnnotation.isItalic
                    viewModel.textIsUnderline = textAnnotation.isUnderline
                    draftTextOrigin = imagePointToDisplayPoint(textAnnotation.origin)
                    draftText = textAnnotation.text
                    viewModel.hasActiveTextDraft = true
                    DispatchQueue.main.async {
                        isTextFieldFocused = true
                    }
                    return
                }

                let origin = clampedTextOrigin(for: value.location)
                draftTextOrigin = origin
                draftText = ""
                viewModel.hasActiveTextDraft = true
                DispatchQueue.main.async {
                    isTextFieldFocused = true
                }
            }
    }

    private func findTextAnnotation(near point: CGPoint, radius: CGFloat) -> (Int, TextAnnotation)? {
        for (index, annotation) in viewModel.annotations.enumerated().reversed() {
            guard case let .text(textAnnotation) = annotation else { continue }
            let origin = textAnnotation.origin
            // Simple bounding box hit test
            let textWidth = CGFloat(textAnnotation.text.count) * textAnnotation.fontSize * 0.6
            let textHeight = textAnnotation.fontSize * 1.4
            let rect = CGRect(x: origin.x, y: origin.y, width: textWidth, height: textHeight)
            let expandedRect = rect.insetBy(dx: -radius, dy: -radius)
            if expandedRect.contains(point) {
                return (index, textAnnotation)
            }
        }
        return nil
    }

    // MARK: - Annotation Drawing

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
                let fontSize = max(text.fontSize * currentDisplayScale, 14)
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
        let headLength = max(lineWidth * 4.8, 12)
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

    // MARK: - Text Editor

    private func draftTextEditor(at origin: CGPoint) -> some View {
        let fontSize = max(viewModel.textFontSize * currentDisplayScale, 14)
        let lineHeight = fontSize * 1.35
        let lineCount = max(draftText.components(separatedBy: "\n").count, 1)
        let editorHeight = CGFloat(lineCount) * lineHeight + 4
        let maxEditorWidth = currentImageRect.width - origin.x - 12

        return InlineTextEditor(
            text: $draftText,
            fontSize: fontSize,
            fontWeight: viewModel.textIsBold ? .bold : .regular,
            isItalic: viewModel.textIsItalic,
            isUnderline: viewModel.textIsUnderline,
            textColor: NSColor(viewModel.selectedColor.swiftUIColor),
            focused: isTextFieldFocused,
            onCommit: { commitTextDraftIfNeeded() },
            onEscape: { discardDraftText() }
        )
        .frame(
            minWidth: 40,
            idealWidth: min(300, maxEditorWidth),
            maxWidth: maxEditorWidth,
            minHeight: lineHeight,
            idealHeight: editorHeight,
            maxHeight: min(editorHeight, currentImageRect.height - origin.y - 12)
        )
        .position(
            x: min(origin.x + min(150, maxEditorWidth / 2), currentImageRect.width - min(150, maxEditorWidth / 2) - 12),
            y: min(origin.y + editorHeight / 2, currentImageRect.height - editorHeight / 2 - 12)
        )
    }

    // MARK: - Text Draft Management

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
            viewModel.hasActiveTextDraft = false
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
        viewModel.hasActiveTextDraft = false
    }

    // MARK: - Crop Adjustment

    private var cropHandleOverlay: some View {
        CropHandleHitView(
            rect: isCropDragging ? (cropAdjustRect ?? currentImageRect) : currentImageRect,
            tolerance: cropHandleHitTolerance
        )
        .gesture(cropDragGesture)
        .frame(width: layout.screenSize.width, height: layout.screenSize.height)
        .allowsHitTesting(viewModel.canAdjustCrop)
    }

    private var cropDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                let point = value.startLocation
                if cropDragEdge == nil {
                    let targetRect = isCropDragging ? (cropAdjustRect ?? currentImageRect) : currentImageRect
                    cropDragEdge = cropEdge(at: point, in: targetRect)
                    cropDragStart = point
                    cropOriginalRect = targetRect
                    isCropDragging = true
                }

                guard let edge = cropDragEdge,
                      let originalRect = cropOriginalRect else { return }

                let dx = value.location.x - (cropDragStart?.x ?? value.location.x)
                let dy = value.location.y - (cropDragStart?.y ?? value.location.y)

                cropAdjustRect = adjustedCropRect(originalRect, edge: edge, dx: dx, dy: dy)
            }
            .onEnded { _ in
                if let finalRect = cropAdjustRect {
                    applyCropAdjustment(finalRect)
                    currentImageRect = finalRect
                }
                cropDragEdge = nil
                cropDragStart = nil
                cropOriginalRect = nil
                isCropDragging = false
                cropAdjustRect = nil
            }
    }

    private func cropEdge(at point: CGPoint, in rect: CGRect) -> CropEdge? {
        let ht = cropHandleHitTolerance + cropHandleSize / 2
        let corners: [(CropEdge, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
        ]
        for (edge, center) in corners {
            if hypot(point.x - center.x, point.y - center.y) <= ht { return edge }
        }

        let midpoints: [(CropEdge, CGPoint)] = [
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
        ]
        for (edge, center) in midpoints {
            if hypot(point.x - center.x, point.y - center.y) <= ht { return edge }
        }

        let et = cropHandleHitTolerance
        if abs(point.y - rect.minY) <= et, point.x >= rect.minX, point.x <= rect.maxX { return .top }
        if abs(point.y - rect.maxY) <= et, point.x >= rect.minX, point.x <= rect.maxX { return .bottom }
        if abs(point.x - rect.minX) <= et, point.y >= rect.minY, point.y <= rect.maxY { return .left }
        if abs(point.x - rect.maxX) <= et, point.y >= rect.minY, point.y <= rect.maxY { return .right }

        return .move
    }

    private func adjustedCropRect(_ original: CGRect, edge: CropEdge, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = original.minX
        var minY = original.minY
        var maxX = original.maxX
        var maxY = original.maxY
        let minSize: CGFloat = 40
        let screenW = layout.screenSize.width
        let screenH = layout.screenSize.height

        switch edge {
        case .topLeft:     minX += dx; minY += dy
        case .top:         minY += dy
        case .topRight:    maxX += dx; minY += dy
        case .left:        minX += dx
        case .right:       maxX += dx
        case .bottomLeft:  minX += dx; maxY += dy
        case .bottom:      maxY += dy
        case .bottomRight: maxX += dx; maxY += dy
        case .move:
            var newOriginX = original.minX + dx
            var newOriginY = original.minY + dy
            newOriginX = max(0, min(newOriginX, screenW - original.width))
            newOriginY = max(0, min(newOriginY, screenH - original.height))
            return CGRect(x: newOriginX, y: newOriginY, width: original.width, height: original.height).integral
        }

        if maxX - minX < minSize {
            switch edge {
            case .topLeft, .left, .bottomLeft: minX = maxX - minSize
            default: maxX = minX + minSize
            }
        }
        if maxY - minY < minSize {
            switch edge {
            case .topLeft, .top, .topRight: minY = maxY - minSize
            default: maxY = minY + minSize
            }
        }

        minX = max(0, minX)
        minY = max(0, minY)
        maxX = min(screenW, maxX)
        maxY = min(screenH, maxY)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }

    private func applyCropAdjustment(_ screenRect: CGRect) {
        guard viewModel.cropInfo != nil else { return }

        let newSelectionRect = CGRect(
            x: screenRect.minX,
            y: screenRect.minY,
            width: screenRect.width,
            height: screenRect.height
        )

        guard newSelectionRect.width >= 8, newSelectionRect.height >= 8 else { return }

        viewModel.recrop(newRect: newSelectionRect)
    }

    // MARK: - Coordinate Conversion

    private func clampedDisplayPoint(for point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), currentImageRect.width),
            y: min(max(point.y, 0), currentImageRect.height)
        )
    }

    private func clampedTextOrigin(for point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 12), max(currentImageRect.width - 228, 12)),
            y: min(max(point.y, 12), max(currentImageRect.height - 40, 12))
        )
    }

    private func imagePointToDisplayPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * currentDisplayScale,
            y: point.y * currentDisplayScale
        )
    }

    private func displayPointToImagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x / currentDisplayScale,
            y: point.y / currentDisplayScale
        )
    }

    private func imageRectToDisplayRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * currentDisplayScale,
            y: rect.origin.y * currentDisplayScale,
            width: rect.width * currentDisplayScale,
            height: rect.height * currentDisplayScale
        )
    }

    private func displayRectToImageRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x / currentDisplayScale,
            y: rect.origin.y / currentDisplayScale,
            width: rect.width / currentDisplayScale,
            height: rect.height / currentDisplayScale
        )
    }

    private func displayStrokeWidth(for imageStrokeWidth: CGFloat) -> CGFloat {
        max(imageStrokeWidth * currentDisplayScale, 2)
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

// MARK: - Inline Text Editor (WeChat-style)

private struct InlineTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var fontWeight: NSFont.Weight
    var isItalic: Bool
    var isUnderline: Bool
    var textColor: NSColor
    var focused: Bool
    var onCommit: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = InlineTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let font = makeFont()
        textView.font = font
        textView.textColor = textColor

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * 0.35
        textView.defaultParagraphStyle = paragraphStyle

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
        textView.typingAttributes = attrs

        if textView.string != text {
            textView.string = text
        }

        if focused && textView.window?.firstResponder != textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        context.coordinator.updateTextSize()
        context.coordinator.applyUnderlineIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func makeFont() -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if isItalic { traits.insert(.italic) }

        let descriptor = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
            .fontDescriptor
            .withSymbolicTraits(traits)

        return NSFont(descriptor: descriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineTextEditor
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(_ parent: InlineTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            updateTextSize()
            applyUnderlineIfNeeded()
        }

        func textDidBeginEditing(_ notification: Notification) {
            // Notify that the text view has focus
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onCommit()
        }

        func textShouldEndEditing(_ textView: NSTextView) -> Bool {
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    return false // Shift+Enter = new line
                }
                parent.onCommit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }

        func updateTextSize() {
            guard let textView, let scrollView else { return }
            textView.sizeToFit()

            let maxWidth = scrollView.frame.width > 0 ? scrollView.frame.width : 600
            let textWidth = textView.frame.width
            if textWidth > maxWidth {
                textView.textContainer?.containerSize = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)
                textView.textContainer?.widthTracksTextView = true
            }
        }

        func applyUnderlineIfNeeded() {
            guard let textView, let textStorage = textView.textStorage else { return }
            if parent.isUnderline {
                let range = NSRange(location: 0, length: textStorage.length)
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
    }
}

private final class InlineTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // Show cursor at end
            if let end = textStorage?.length {
                setSelectedRange(NSRange(location: end, length: 0))
            }
        }
        return result
    }
}
