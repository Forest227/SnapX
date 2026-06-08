import AppKit
import Carbon.HIToolbox
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
        cropInfo: ScreenshotEditorCropInfo? = nil,
        existingWindow: NSWindow? = nil,
        onPin: @escaping (NSImage) -> Void,
        onCopy: @escaping (NSImage) -> Void,
        onClose: @escaping () -> Void
    ) {
        viewModel = ScreenshotEditorViewModel(image: image, cropInfo: cropInfo)
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
                if self.viewModel.hasActiveTextDraft {
                    self.viewModel.textDraftDiscardRequest = true
                    return nil
                }
                self.close()
                return nil
            }

            if event.keyCode == UInt16(kVK_Return) {
                if self.viewModel.hasActiveTextDraft {
                    return event
                }
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
            if let character = event.charactersIgnoringModifiers,
               let tool = ScreenshotEditorTool.allCases.first(where: { $0.shortcutKey == character }) {
                self.viewModel.activeTool = tool
                return nil
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

final class ScreenshotEditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct ScreenshotEditorLayout {
    let screenFrame: CGRect
    let screenSize: CGSize
    let imageRect: CGRect
    let toolbarRect: CGRect
    let displayScale: CGFloat
}

