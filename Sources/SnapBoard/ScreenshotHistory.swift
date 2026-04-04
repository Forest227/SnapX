import AppKit
import Foundation

struct HistoryItem: Identifiable {
    let id = UUID()
    let image: NSImage
    let date: Date
}

@MainActor
final class ScreenshotHistory: ObservableObject {
    static let shared = ScreenshotHistory()

    @Published private(set) var items: [HistoryItem] = []

    private let maxCount = 100

    private init() {}

    func add(_ image: NSImage) {
        items.insert(HistoryItem(image: image, date: Date()), at: 0)
        if items.count > maxCount {
            items.removeLast()
        }
    }

    func remove(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }
}
