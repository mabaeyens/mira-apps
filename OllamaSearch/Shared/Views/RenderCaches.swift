import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Memoised message parsing, read on the main thread during `body`.
///
/// `parseMessageSegments` runs a fenced-code regex plus a line-by-line table scan.
/// `MessageContentView` called it from a computed property, so it re-ran on every
/// body evaluation and every LazyVStack re-materialisation while scrolling. A
/// message's content is stable once its turn is no longer streaming (streaming
/// uses a plain-Text path, not this one), so the parse is cached by content.
/// Bounded LRU.
@MainActor
final class SegmentCache {
    static let shared = SegmentCache()

    private var store: [String: [MessageSegment]] = [:]
    private var order: [String] = []
    private let limit = 512

    func segments(for content: String) -> [MessageSegment] {
        if let hit = store[content] { return hit }
        let parsed = parseMessageSegments(content)
        store[content] = parsed
        order.append(content)
        while order.count > limit { store[order.removeFirst()] = nil }
        return parsed
    }
}

/// Decoded attachment thumbnails, so scrolling past an image message does not
/// re-decode its data on every appearance. Bounded LRU.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var order: [Data] = []
    private let limit = 48

    #if os(macOS)
    private var store: [Data: NSImage] = [:]
    func image(for data: Data) -> NSImage? {
        if let hit = store[data] { return hit }
        guard let img = NSImage(data: data) else { return nil }
        insert(img, for: data)
        return img
    }
    private func insert(_ img: NSImage, for data: Data) {
        store[data] = img
        order.append(data)
        while order.count > limit { store[order.removeFirst()] = nil }
    }
    #else
    private var store: [Data: UIImage] = [:]
    func image(for data: Data) -> UIImage? {
        if let hit = store[data] { return hit }
        guard let img = UIImage(data: data) else { return nil }
        insert(img, for: data)
        return img
    }
    private func insert(_ img: UIImage, for data: Data) {
        store[data] = img
        order.append(data)
        while order.count > limit { store[order.removeFirst()] = nil }
    }
    #endif
}
