import SwiftUI

/// Presents lookup results as candidates to choose from rather than filling
/// values in automatically. Automatic tempo and key detection is wrong often
/// enough -- and wrong in confident-looking ways -- that silently overwriting
/// a value you already verified by ear would be the worse failure.
struct LookupSheet: View {
    @Binding var song: Song
    @Environment(\.dismiss) private var dismiss
    @StateObject private var lookup = BPMLookup()

    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var showRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            queryBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 620, height: 460)
        .onAppear {
            title = song.title
            artist = song.artist
            if lookup.hasAPIKey { Task { await runSearch() } }
        }
    }

    private var queryBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Look Up Tempo & Key").font(.headline)
            HStack(spacing: 8) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Artist", text: $artist)
                    .textFieldStyle(.roundedBorder)
                Button("Search") { Task { await runSearch() } }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(lookup.isSearching || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if !lookup.hasAPIKey {
            missingKeyNotice
        } else if lookup.isSearching {
            centered { ProgressView("Searching\u{2026}") }
        } else if !lookup.candidates.isEmpty {
            resultList
        } else if let message = lookup.errorMessage {
            centered {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 420)
                    if !lookup.rawResponse.isEmpty {
                        DisclosureGroup("Raw response", isExpanded: $showRaw) {
                            ScrollView {
                                Text(lookup.rawResponse)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 130)
                        }
                        .frame(maxWidth: 460)
                    }
                }
            }
        } else {
            centered {
                Text("Search to see matches.").foregroundStyle(.secondary)
            }
        }
    }

    private var missingKeyNotice: some View {
        centered {
            VStack(spacing: 12) {
                Image(systemName: "key").font(.largeTitle).foregroundStyle(.secondary)
                Text("No API key set").font(.headline)
                Text("Get a free key from getsongbpm.com, then paste it into Settings (\u{2318},).")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
    }

    private var resultList: some View {
        List(lookup.candidates) { candidate in
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title).fontWeight(.medium)
                    Text([candidate.artist, candidate.album, candidate.year]
                        .filter { !$0.isEmpty }
                        .joined(separator: " \u{2014} "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(candidate.bpm.map { "\(Int($0.rounded())) BPM" } ?? "no BPM")
                        .monospacedDigit()
                    Text(candidate.key ?? candidate.rawKey ?? "no key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Use") { apply(candidate) }
            }
            .padding(.vertical, 3)
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            // In-app attribution to the data source, per their terms.
            Link("Data from GetSongBPM", destination: URL(string: "https://getsongbpm.com")!)
                .font(.caption)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
    }

    private func runSearch() async {
        await lookup.search(title: title, artist: artist)
    }

    /// Only fills fields the result actually carries, so a partial match can't
    /// blank out something you already set.
    private func apply(_ candidate: LookupCandidate) {
        if let bpm = candidate.bpm { song.bpm = min(max(bpm, 20), 400) }
        if let key = candidate.key { song.key = key }
        if let beats = candidate.beatsPerBar { song.beatsPerBar = beats }
        if song.artist.isEmpty && !candidate.artist.isEmpty { song.artist = candidate.artist }
        dismiss()
    }
}

struct SettingsView: View {
    // Not a @State default: SwiftUI re-runs those on every struct init, which
    // would mean another Keychain hit each time the window redraws.
    @State private var apiKey: String = ""
    @State private var loaded = false
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                TextField("API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") {
                        Keychain.set(apiKey, for: BPMLookup.keychainAccount)
                        BPMLookup.invalidateKeyCache()
                        saved = true
                    }
                    if saved {
                        Text("Saved to Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("GetSongBPM")
            } footer: {
                Text("A free key from getsongbpm.com enables tempo and key lookup. Stored in your login Keychain, not in the library file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(.vertical, 8)
        .onAppear {
            guard !loaded else { return }
            apiKey = BPMLookup.storedKey ?? ""
            loaded = true
        }
        .onChange(of: apiKey) { _, _ in saved = false }
    }
}
