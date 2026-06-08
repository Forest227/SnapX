import AppKit
import SwiftUI

@MainActor
final class ScreenshotEditorViewModel: ObservableObject {
    @Published var image: NSImage
    @Published var pixelatedPreviewImage: NSImage?

    let cropInfo: ScreenshotEditorCropInfo?

    @Published var activeTool: ScreenshotEditorTool = .rectangle
    @Published var selectedColor: ScreenshotAnnotationColor = .red
    @Published var textFontSize: CGFloat = 24
    @Published var textIsBold: Bool = false
    @Published var textIsItalic: Bool = false
    @Published var textIsUnderline: Bool = false
    @Published var annotations: [ScreenshotEditorAnnotation] = []
    @Published var isExtractingText = false
    @Published var toastMessage: String?
    @Published var hasActiveTextDraft = false
    @Published var textDraftDiscardRequest = false

    private var toastDismissTask: Task<Void, Never>?

    init(image: NSImage, cropInfo: ScreenshotEditorCropInfo? = nil) {
        self.image = image
        self.cropInfo = cropInfo
        pixelatedPreviewImage = nil
        let capturedImage = image
        Task.detached(priority: .userInitiated) {
            let pixelated = ScreenshotEditorRenderer.makePixelatedPreviewImage(for: capturedImage)
            await MainActor.run { [weak self] in
                self?.pixelatedPreviewImage = pixelated
            }
        }
    }

    var canUndo: Bool {
        !annotations.isEmpty
    }

    var canAdjustCrop: Bool {
        cropInfo != nil
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

    func recrop(newRect: CGRect) {
        guard let cropInfo else { return }
        let sf = cropInfo.scaleFactor
        let pixelRect = CGRect(
            x: newRect.minX * sf,
            y: newRect.minY * sf,
            width: newRect.width * sf,
            height: newRect.height * sf
        ).integral

        guard let fullCG = cropInfo.fullScreenImage.cgImageRepresentation,
              let croppedCG = fullCG.cropping(to: pixelRect) else { return }

        let newImage = NSImage(cgImage: croppedCG, size: newRect.size)
        image = newImage
        pixelatedPreviewImage = nil
        annotations.removeAll()
        let capturedNewImage = newImage
        Task.detached(priority: .userInitiated) {
            let pixelated = ScreenshotEditorRenderer.makePixelatedPreviewImage(for: capturedNewImage)
            await MainActor.run { [weak self] in
                self?.pixelatedPreviewImage = pixelated
            }
        }
    }

    func showToast(_ message: String) {
        toastDismissTask?.cancel()
        toastMessage = message

        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.toastMessage = nil
            }
        }
    }
}
