import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var metronome: Metronome

    @State private var selection: Song.ID?
    @State private var search = ""

    @State private var showingNewSong = false
    @State private var newTitle = ""
    @State private var newArtist = ""
    @State private var newConfirmed = false

    /// Set after a song is created so its detail view opens the lookup sheet
    /// once it appears.
    @State private var autoLookupID: Song.ID?

    @StateObject private var typeSelect = TypeSelect()

    private var visibleSongs: [Song] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let matches = query.isEmpty ? library.songs : library.songs.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
                || $0.lyrics.localizedCaseInsensitiveContains(query)
        }
        return matches.sorted(by: Song.alphabetically)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let index = library.index(of: selection) {
                SongDetailView(song: $library.songs[index], autoLookupID: $autoLookupID)
                    .id(library.songs[index].id)
            } else {
                ContentUnavailableView(
                    library.songs.isEmpty ? "No Songs Yet" : "No Song Selected",
                    systemImage: "music.note.list",
                    description: Text(
                        library.songs.isEmpty
                            ? "Press \u{2318}N to add your first song."
                            : "Pick a song from the list."))
            }
        }
        .onChange(of: selection) { _, _ in adoptSelectedTempo() }
        .onReceive(NotificationCenter.default.publisher(for: .newSongRequested)) { _ in
            newSong()
        }
        // Creating the song happens on dismissal rather than inside the sheet,
        // so the lookup sheet is never asked to open while another is closing.
        .sheet(isPresented: $showingNewSong, onDismiss: finishNewSong) {
            NewSongSheet(title: $newTitle, artist: $newArtist, confirmed: $newConfirmed)
        }
    }

    private var sidebar: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(visibleSongs) { song in
                    SongRow(song: song)
                        .tag(song.id)
                        .id(song.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                library.delete(ids: [song.id])
                                if selection == song.id { selection = nil }
                            }
                        }
                }
            }
            .onKeyPress(phases: .down) { press in
                handleTypeSelect(press, scrollingWith: proxy)
            }
            .overlay(alignment: .bottom) { typeSelectIndicator }
            .animation(.easeOut(duration: 0.12), value: typeSelect.buffer)
        }
        .searchable(text: $search, prompt: "Search titles, artists, lyrics")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        .onDeleteCommand(perform: deleteSelection)
        .toolbar {
            ToolbarItem {
                Button(action: newSong) { Label("New Song", systemImage: "plus") }
                    .help("New song (\u{2318}N)")
            }
        }
    }

    /// Type-ahead selection. Printable keys accumulate into a buffer and jump
    /// the selection; everything else is passed through so shortcuts, arrow
    /// navigation and Delete keep working.
    private func handleTypeSelect(_ press: KeyPress, scrollingWith proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !press.modifiers.contains(.command),
              !press.modifiers.contains(.control),
              !press.modifiers.contains(.option)
        else { return .ignored }

        switch press.key {
        case .escape:
            typeSelect.clear()
            return .handled
        case .delete:
            // Backspace narrows the buffer, but only while one exists --
            // otherwise it belongs to the list's own delete handling.
            guard !typeSelect.buffer.isEmpty else { return .ignored }
            typeSelect.backspace()
            applyTypeSelect(proxy)
            return .handled
        case .upArrow, .downArrow, .leftArrow, .rightArrow,
             .return, .tab, .deleteForward, .pageUp, .pageDown, .home, .end:
            return .ignored
        default:
            break
        }

        let characters = press.characters
        guard !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return .ignored }

        // A leading space matches everything, so let the list have it.
        if characters == " " && typeSelect.buffer.isEmpty { return .ignored }

        typeSelect.append(characters)
        applyTypeSelect(proxy)
        return .handled
    }

    private func applyTypeSelect(_ proxy: ScrollViewProxy) {
        guard let song = TypeSelect.match(visibleSongs, query: typeSelect.buffer) else { return }
        selection = song.id
        proxy.scrollTo(song.id, anchor: .center)
    }

    /// Shows what has been typed, so a multi-character match is visible rather
    /// than the selection appearing to jump for no reason.
    @ViewBuilder
    private var typeSelectIndicator: some View {
        if !typeSelect.buffer.isEmpty {
            Text(typeSelect.buffer)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 1))
                .padding(.bottom, 14)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func newSong() {
        newTitle = ""
        newArtist = ""
        newConfirmed = false
        showingNewSong = true
    }

    private func finishNewSong() {
        guard newConfirmed else { return }
        newConfirmed = false

        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        // Clear any filter, or the song just created may not be visible.
        search = ""
        let song = library.addSong(
            title: title,
            artist: newArtist.trimmingCharacters(in: .whitespacesAndNewlines))
        selection = song.id

        // Only jump into lookup when it can actually do something; without a
        // key the sheet would only be able to say so.
        if BPMLookup.storedKey != nil {
            autoLookupID = song.id
        }
    }

    private func deleteSelection() {
        guard let selection else { return }
        library.delete(ids: [selection])
        self.selection = nil
    }

    /// Selecting a song loads its tempo into the metronome, so hitting play
    /// always clicks at the tempo of whatever you're looking at.
    private func adoptSelectedTempo() {
        guard let index = library.index(of: selection) else { return }
        // Browsing to another song while something is counting should not cut
        // the click off; the sidebar play buttons switch songs deliberately.
        guard !metronome.isRunning else { return }
        let song = library.songs[index]
        metronome.bpm = song.bpm
        metronome.beatsPerBar = song.beatsPerBar
    }
}

private struct SongRow: View {
    let song: Song
    @EnvironmentObject private var metronome: Metronome

    private var isPlaying: Bool { metronome.isPlaying(song) }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                metronome.toggle(song)
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 11))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isPlaying ? Color.accentColor : Color.secondary)
            .help(isPlaying ? "Stop metronome" : "Play metronome at \(Int(song.bpm.rounded())) BPM")

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title.isEmpty ? "Untitled" : song.title)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(song.artist.isEmpty ? "\u{2014}" : song.artist)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if !song.key.isEmpty {
                        Text(MusicalKey.short(song.key))
                        Text("\u{00B7}")
                    }
                    Text("\(Int(song.bpm.rounded()))")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
