import AppKit
import CoreGraphics

struct ScreenshotEditorCropInfo {
    let fullScreenImage: NSImage
    let selectionRect: CGRect
    let displayID: CGDirectDisplayID
    let scaleFactor: CGFloat
}