import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSWindowController {
    private static var shared: HistoryWindowController?

    static func present() {
        if shared == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "截图历史"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: HistoryView())
            shared = HistoryWindowController(window: window)
        }
        shared?.showWindow(nil)
        shared?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct HistoryView: View {
    @ObservedObject private var history = ScreenshotHistory.shared
    @State private var selectedItem: HistoryItem?
    @State private var selectedIDs: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        if history.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("暂无截图历史")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(history.items) { item in
                        ThumbnailCell(
                            item: item,
                            isSelected: selectedIDs.contains(item.id),
                            onSelect: { selectedItem = item },
                            onToggleSelect: { toggleSelect(item) },
                            onDelete: { history.remove(item) }
                        )
                    }
                }
                .padding(16)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("清空历史") { history.clear() }
                        .foregroundStyle(.red)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        pinSelected()
                    } label: {
                        Label("钉住所选", systemImage: "pin")
                    }
                    .disabled(selectedIDs.isEmpty)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        deleteSelected()
                    } label: {
                        Label("删除所选", systemImage: "trash")
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .sheet(item: $selectedItem) { item in
                ImagePreviewView(item: item)
                    .frame(minWidth: 900, minHeight: 650)
            }
        }
    }

    private func toggleSelect(_ item: HistoryItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func pinSelected() {
        let appState = (NSApp.delegate as? AppDelegate)?.appState
        history.items
            .filter { selectedIDs.contains($0.id) }
            .forEach { appState?.pinImage($0.image) }
        selectedIDs.removeAll()
    }

    private func deleteSelected() {
        selectedIDs.forEach { id in
            if let item = history.items.first(where: { $0.id == id }) {
                history.remove(item)
            }
        }
        selectedIDs.removeAll()
    }
}

private struct ThumbnailCell: View {
    let item: HistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Image(nsImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)

                Text(item.date, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .overlay(alignment: .topLeading) {
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ImagePreviewView: View {
    let item: HistoryItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(item.date.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let appState = (NSApp.delegate as? AppDelegate)?.appState
                    appState?.pinImage(item.image)
                    dismiss()
                } label: {
                    Label("钉住", systemImage: "pin")
                }
                .buttonStyle(.bordered)
                Button("关闭") { dismiss() }
            }
            .padding(16)

            ZoomableImageView(image: item.image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MagnifyScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 20
        scrollView.backgroundColor = .windowBackgroundColor

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleNone
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.documentView = imageView

        // fit to window on first layout
        DispatchQueue.main.async {
            let viewSize = scrollView.bounds.size
            guard viewSize.width > 0, viewSize.height > 0, image.size.width > 0, image.size.height > 0 else { return }
            let scale = min(viewSize.width / image.size.width, viewSize.height / image.size.height)
            scrollView.magnification = scale
            // center the document
            let docSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let x = max((viewSize.width - docSize.width) / 2, 0)
            let y = max((viewSize.height - docSize.height) / 2, 0)
            scrollView.documentView?.scroll(CGPoint(x: -x, y: -y))
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

private final class MagnifyScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // pinch gesture — use default
        if event.phase != [] || !event.momentumPhase.isEmpty {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let factor = delta > 0 ? 1.08 : 1 / 1.08
        let newMag = (magnification * factor).clamped(to: minMagnification...maxMagnification)
        setMagnification(newMag, centeredAt: convert(event.locationInWindow, from: nil))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
