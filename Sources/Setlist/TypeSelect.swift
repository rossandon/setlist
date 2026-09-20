import Foundation

/// Type-ahead selection for the song list: start typing and the matching song
/// is selected, the way Finder and the old iTunes behaved.
///
/// The buffer accumulates until you pause, so several characters narrow the
/// match rather than each keystroke starting over.
@MainActor
final class TypeSelect: ObservableObject {
    /// What has been typed so far. Empty when idle.
    @Published private(set) var buffer = ""

    /// How long a pause ends the current entry. Matches the macOS convention
    /// closely enough that muscle memory carries over.
    private static let resetAfter: TimeInterval = 1.0

    private var lastKeystroke = Date.distantPast
    private var clearTask: Task<Void, Never>?

    /// Appends typed characters, first discarding a buffer that has gone stale.
    func append(_ characters: String) {
        let now = Date()
        if now.timeIntervalSince(lastKeystroke) > Self.resetAfter {
            buffer = ""
        }
        lastKeystroke = now
        buffer += characters
        scheduleClear()
    }

    func backspace() {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
        lastKeystroke = Date()
        scheduleClear()
    }

    func clear() {
        clearTask?.cancel()
        clearTask = nil
        buffer = ""
        lastKeystroke = .distantPast
    }

    /// Drops the buffer after the pause, so the indicator does not linger and
    /// the next burst of typing starts clean.
    private func scheduleClear() {
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.resetAfter * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.buffer = ""
        }
    }

    /// Finds the song to select for what has been typed.
    ///
    /// Title prefix first, which is the platform convention and what typing a
    /// couple of letters usually means. Falling back to anywhere in the title
    /// and then to the artist keeps a reasonable guess on screen instead of
    /// appearing to do nothing.
    static func match(_ songs: [Song], query: String) -> Song? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }

        let loose: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        if let hit = songs.first(where: {
            $0.displayTitle.range(of: query, options: loose.union(.anchored)) != nil
        }) { return hit }

        if let hit = songs.first(where: {
            $0.displayTitle.range(of: query, options: loose) != nil
        }) { return hit }

        return songs.first { !$0.artist.isEmpty && $0.artist.range(of: query, options: loose) != nil }
    }
}
