import Foundation

struct LookupCandidate: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let bpm: Double?
    let key: String?           // normalized to "G major" form when recognizable
    let rawKey: String?        // exactly what the service returned
    let timeSignature: String?
    let beatsPerBar: Int?
    let year: String
}

enum LookupError: LocalizedError {
    case missingAPIKey
    case emptyQuery
    case service(String)
    case http(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No GetSongBPM API key set. Add one in Settings (\u{2318},)."
        case .emptyQuery:
            return "Enter a title before looking up."
        case .service(let message):
            return message
        case .http(let code):
            return "GetSongBPM returned HTTP \(code)."
        case .unreadable:
            return "Could not read the response. See the raw JSON below."
        }
    }
}

/// Client for the GetSongBPM API (api.getsong.co).
///
/// The response is walked with JSONSerialization rather than Codable on
/// purpose. Their published schema could not be confirmed against a live key
/// while this was written, so every field is looked up under several plausible
/// names and accepted as either a string or a number. Anything unrecognized
/// leaves the field nil rather than failing the whole parse, and the raw JSON
/// is kept so a schema change is diagnosable instead of just broken.
@MainActor
final class BPMLookup: ObservableObject {
    @Published private(set) var candidates: [LookupCandidate] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?
    @Published private(set) var rawResponse: String = ""

    static let keychainAccount = "getsongbpm-api-key"

    // Read the Keychain once per launch and cache it. SwiftUI re-evaluates a
    // view's body constantly -- once per keystroke in a text field -- and
    // hitting SecItemCopyMatching on each pass produces a storm of
    // authorization prompts.
    private static var cachedKey: String?
    private static var didLoadKey = false

    static func invalidateKeyCache() {
        cachedKey = nil
        didLoadKey = false
    }

    /// The single Keychain read point for the whole app.
    static var storedKey: String? {
        if !didLoadKey {
            cachedKey = Keychain.get(keychainAccount)
            didLoadKey = true
        }
        return cachedKey
    }

    var apiKey: String? { Self.storedKey }
    var hasAPIKey: Bool { apiKey != nil }

    func clear() {
        candidates = []
        errorMessage = nil
        rawResponse = ""
    }

    func search(title: String, artist: String) async {
        clear()

        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { errorMessage = LookupError.emptyQuery.localizedDescription; return }
        guard let key = apiKey else { errorMessage = LookupError.missingAPIKey.localizedDescription; return }

        // The lookup term is the bare title. Field-prefixed forms such as
        // "song:TITLE artist:ARTIST" are accepted by the endpoint but always
        // match nothing, and so does appending the artist to the term, so the
        // artist is applied below as a client-side ranking instead.
        var components = URLComponents(string: "https://api.getsong.co/search/")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "type", value: "song"),
            URLQueryItem(name: "lookup", value: title),
        ]
        guard let url = components.url else { errorMessage = LookupError.unreadable.localizedDescription; return }

        isSearching = true
        defer { isSearching = false }

        do {
            var request = URLRequest(url: url)
            request.setValue("Setlist/1.0 (personal use)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 25

            let (data, response) = try await URLSession.shared.data(for: request)
            rawResponse = String(data: data, encoding: .utf8) ?? "<non-text response>"

            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            // Errors arrive in two shapes: a top-level "error" for an invalid
            // key, and a nested {"search": {"error": ...}} for a miss.
            if let message = root?["error"] as? String {
                errorMessage = LookupError.service(message).localizedDescription
                return
            }
            if let nested = root?["search"] as? [String: Any],
               let message = nested["error"] as? String {
                errorMessage = message.lowercased().contains("no result")
                    ? "No matches for \u{201C}\(title)\u{201D}."
                    : LookupError.service(message).localizedDescription
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                errorMessage = LookupError.http(http.statusCode).localizedDescription
                return
            }
            guard let root else {
                errorMessage = LookupError.unreadable.localizedDescription
                return
            }

            let items = BPMLookup.resultArray(in: root)
            candidates = BPMLookup.ranked(items.compactMap(BPMLookup.candidate(from:)), byArtist: artist)
            if candidates.isEmpty {
                errorMessage = "No matches for \u{201C}\(title)\u{201D}."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Tolerant parsing

    /// The result array has appeared under a few names; take whichever exists.
    static func resultArray(in root: [String: Any]) -> [[String: Any]] {
        for name in ["search", "songs", "song", "result", "results", "data"] {
            if let array = root[name] as? [[String: Any]] { return array }
            // A lone object here is the error envelope, not a result.
            if let single = root[name] as? [String: Any], single["error"] == nil { return [single] }
        }
        return []
    }

    private static func string(_ dict: [String: Any], _ names: [String]) -> String? {
        for name in names {
            if let s = dict[name] as? String, !s.isEmpty { return s }
            if let n = dict[name] as? NSNumber { return n.stringValue }
        }
        return nil
    }

    /// Tempo comes back as a string in some responses and a number in others.
    private static func double(_ dict: [String: Any], _ names: [String]) -> Double? {
        for name in names {
            if let d = dict[name] as? Double { return d }
            if let n = dict[name] as? NSNumber { return n.doubleValue }
            if let s = dict[name] as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)) { return d }
        }
        return nil
    }

    private static func nested(_ dict: [String: Any], _ name: String, _ inner: [String]) -> String? {
        if let sub = dict[name] as? [String: Any] { return string(sub, inner) }
        if let s = dict[name] as? String, !s.isEmpty { return s }
        return nil
    }

    static func candidate(from item: [String: Any]) -> LookupCandidate? {
        let title = string(item, ["title", "song_title", "name"]) ?? ""
        guard !title.isEmpty else { return nil }

        let bpm = double(item, ["tempo", "bpm", "song_tempo"])
        let rawKey = string(item, ["key_of", "key", "song_key"])
        let timeSig = string(item, ["time_sig", "time_signature", "signature"])

        return LookupCandidate(
            id: string(item, ["id", "song_id", "uri"]) ?? UUID().uuidString,
            title: title,
            artist: nested(item, "artist", ["name", "artist_name", "title"]) ?? "",
            album: nested(item, "album", ["title", "name"]) ?? "",
            bpm: bpm.flatMap { $0 > 0 ? $0 : nil },
            key: rawKey.flatMap(normalizedKey(from:)),
            rawKey: rawKey,
            timeSignature: timeSig,
            beatsPerBar: timeSig.flatMap(beatsPerBar(from:)),
            year: nested(item, "album", ["year"]) ?? ""
        )
    }

    /// Search matches on title only, so a common title returns 30 recordings
    /// by different artists. Float the ones matching the artist you typed to
    /// the top rather than filtering, since spellings differ ("The Beatles"
    /// vs "Beatles") and dropping a near-match would hide the right answer.
    static func ranked(_ items: [LookupCandidate], byArtist artist: String) -> [LookupCandidate] {
        let needle = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return items }
        return items.enumerated().sorted { lhs, rhs in
            let l = score(lhs.element.artist, needle), r = score(rhs.element.artist, needle)
            return l == r ? lhs.offset < rhs.offset : l > r
        }.map(\.element)
    }

    private static func score(_ candidateArtist: String, _ needle: String) -> Int {
        let name = candidateArtist.lowercased()
        if name == needle { return 3 }
        if name.contains(needle) || needle.contains(name) { return 2 }
        let words = Set(needle.split(separator: " ")).subtracting(["the", "and", "&"])
        return words.contains(where: name.contains) ? 1 : 0
    }

    /// Map what the service returns ("G", "Gm", "F#", "Bb minor") onto the
    /// app's stored form ("G major", "G minor"). Unrecognized input returns
    /// nil so the raw value is shown and the user can pick by hand.
    static func normalizedKey(from raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var isMinor = false
        for suffix in [" minor", " min", "minor", "min", "m"] where text.lowercased().hasSuffix(suffix) {
            // "m" alone must not swallow the "m" of a note name; notes are 1-2 chars.
            let stripped = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty {
                isMinor = true
                text = stripped
            }
            break
        }
        for suffix in [" major", " maj", "major", "maj"] where text.lowercased().hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        let note = text
            .replacingOccurrences(of: "#", with: "\u{266F}")
            .replacingOccurrences(of: "b", with: "\u{266D}")
            .replacingOccurrences(of: "B\u{266D}\u{266D}", with: "B\u{266D}")  // guard "Bb" -> "B♭"
        let canonical = note.prefix(1).uppercased() + note.dropFirst()

        // Fold enharmonics onto the spellings the picker offers.
        let enharmonic = [
            "D\u{266D}": "C\u{266F}", "D\u{266F}": "E\u{266D}", "G\u{266D}": "F\u{266F}",
            "G\u{266F}": "A\u{266D}", "A\u{266F}": "B\u{266D}", "E\u{266F}": "F",
            "B\u{266F}": "C", "C\u{266D}": "B", "F\u{266D}": "E",
        ]
        let resolved = enharmonic[canonical] ?? canonical

        guard MusicalKey.noteNames.contains(resolved) else { return nil }
        return "\(resolved) \(isMinor ? "minor" : "major")"
    }

    static func beatsPerBar(from timeSignature: String) -> Int? {
        let numerator = timeSignature.split(separator: "/").first.map(String.init) ?? timeSignature
        guard let value = Int(numerator.trimmingCharacters(in: .whitespaces)), (2...7).contains(value) else {
            return nil
        }
        return value
    }
}
