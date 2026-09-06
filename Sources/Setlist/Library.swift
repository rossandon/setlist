import AppKit
import Combine
import Foundation

struct Song: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = "Untitled"
    var artist: String = ""
    var bpm: Double = 120
    var beatsPerBar: Int = 4
    var key: String = ""
    var lyrics: String = ""
    var updatedAt: Date = Date()

    init() {}

    /// Decoded field by field with defaults rather than relying on the
    /// synthesized initializer, which fails outright on a missing key. This way
    /// a library written by an older build still loads after fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        bpm = try c.decodeIfPresent(Double.self, forKey: .bpm) ?? 120
        beatsPerBar = try c.decodeIfPresent(Int.self, forKey: .beatsPerBar) ?? 4
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        lyrics = try c.decodeIfPresent(String.self, forKey: .lyrics) ?? ""
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

enum MusicalKey {
    static let noteNames = ["C", "C\u{266F}", "D", "E\u{266D}", "E", "F",
                            "F\u{266F}", "G", "A\u{266D}", "A", "B\u{266D}", "B"]

    /// Every key, as stored: "G major", "E minor". Empty string means unset.
    static let all: [String] = noteNames.flatMap { ["\($0) major", "\($0) minor"] }

    /// Compact form for the sidebar: "G", "Em".
    static func short(_ key: String) -> String {
        guard !key.isEmpty else { return "" }
        if key.hasSuffix(" minor") { return String(key.dropLast(6)) + "m" }
        return String(key.dropLast(6))
    }
}

/// The song list, persisted as a single JSON file.
///
/// Plain JSON rather than SwiftData or SQLite: a few hundred songs is nothing,
/// the file stays greppable and diffable, and backing it up is a copy.
@MainActor
final class Library: ObservableObject {
    @Published var songs: [Song] = []

    private var cancellables = Set<AnyCancellable>()

    static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Setlist", isDirectory: true)
            .appendingPathComponent("library.json")
    }()

    init() {
        load()

        // Coalesce edits so typing lyrics doesn't hit the disk on every keystroke.
        $songs
            .dropFirst()
            .debounce(for: .seconds(0.75), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.save() }
            }
            .store(in: &cancellables)
    }

    func index(of id: Song.ID?) -> Int? {
        guard let id else { return nil }
        return songs.firstIndex { $0.id == id }
    }

    @discardableResult
    func addSong(title: String = "Untitled", artist: String = "") -> Song {
        var song = Song()
        song.title = title
        song.artist = artist
        songs.insert(song, at: 0)
        return song
    }

    func delete(ids: Set<Song.ID>) {
        guard !ids.isEmpty else { return }
        songs.removeAll { ids.contains($0.id) }
    }

    func load() {
        let url = Library.fileURL
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            songs = try decoder.decode([Song].self, from: data)
        } catch {
            NSLog("Could not read \(url.path): \(error.localizedDescription)")
        }
    }

    func save() {
        let url = Library.fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(songs)
            // Atomic so a crash mid-write can't truncate the library.
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Could not write \(url.path): \(error.localizedDescription)")
        }
    }
}
