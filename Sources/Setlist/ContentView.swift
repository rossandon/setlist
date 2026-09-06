import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var metronome: Metronome

    @State private var selection: Song.ID?
    @State private var search = ""

    private var visibleSongs: [Song] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return library.songs }
        return library.songs.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
                || $0.lyrics.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let index = library.index(of: selection) {
                SongDetailView(song: $library.songs[index])
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
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(visibleSongs) { song in
                SongRow(song: song)
                    .tag(song.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            library.delete(ids: [song.id])
                            if selection == song.id { selection = nil }
                        }
                    }
            }
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

    private func newSong() {
        search = ""
        let song = library.addSong()
        selection = song.id
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
