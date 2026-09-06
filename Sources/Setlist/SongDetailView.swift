import SwiftUI

struct SongDetailView: View {
    @Binding var song: Song
    @EnvironmentObject private var metronome: Metronome

    @State private var showingLookup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            TransportBar(song: $song)
            Divider()
            lyricsEditor
        }
        .navigationTitle(song.title.isEmpty ? "Untitled" : song.title)
        .sheet(isPresented: $showingLookup) {
            LookupSheet(song: $song)
        }
        .onChange(of: song.bpm) { _, new in
            song.updatedAt = Date()
            metronome.bpm = new
        }
        .onChange(of: song.beatsPerBar) { _, new in
            song.updatedAt = Date()
            metronome.beatsPerBar = new
        }
        .onChange(of: song.key) { _, _ in song.updatedAt = Date() }
        .onChange(of: song.lyrics) { _, _ in song.updatedAt = Date() }
        .onChange(of: song.title) { _, _ in song.updatedAt = Date() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                TextField("Title", text: $song.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold))
                TextField("Artist", text: $song.artist)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Button {
                showingLookup = true
            } label: {
                Label("Look Up", systemImage: "magnifyingglass")
            }
            .help("Look up tempo and key on GetSongBPM")
            .disabled(song.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var lyricsEditor: some View {
        TextEditor(text: $song.lyrics)
            .font(.system(size: 14))
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .topLeading) {
                if song.lyrics.isEmpty {
                    Text("Lyrics\u{2026}")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 19)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Transport

private struct TransportBar: View {
    @Binding var song: Song
    @EnvironmentObject private var metronome: Metronome

    @State private var taps: [Date] = []

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            playButton
            tempoControls
            Divider().frame(height: 34)
            barControls
            Divider().frame(height: 34)
            keyControl
            Spacer(minLength: 0)
            beatIndicator
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var playButton: some View {
        Button(action: { metronome.toggle() }) {
            Image(systemName: metronome.isRunning ? "stop.fill" : "play.fill")
                .font(.system(size: 17))
                .frame(width: 40, height: 32)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("m", modifiers: .command)
        .help(metronome.isRunning ? "Stop metronome (\u{2318}M)" : "Start metronome (\u{2318}M)")
    }

    private var tempoControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("BPM", value: $song.bpm, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 62)
                    .monospacedDigit()
                Text("BPM").foregroundStyle(.secondary)
                Stepper("Tempo", value: $song.bpm, in: 20...400, step: 1)
                    .labelsHidden()
                // Halve/double: any automatic tempo detection, ours or a
                // lookup service's, routinely lands an octave off.
                Button("\u{00D7}\u{00BD}") { song.bpm = max(20, (song.bpm / 2).rounded()) }
                    .help("Half time")
                Button("\u{00D7}2") { song.bpm = min(400, (song.bpm * 2).rounded()) }
                    .help("Double time")
                Button("Tap", action: registerTap)
                    .help("Tap four or more times to set the tempo")
            }
            Slider(value: $song.bpm, in: 40...240)
                .frame(width: 220)
        }
    }

    private var barControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Beats per bar", selection: $song.beatsPerBar) {
                ForEach([2, 3, 4, 5, 6, 7], id: \.self) { Text("\($0)/4").tag($0) }
            }
            .labelsHidden()
            .frame(width: 78)
            Toggle("Accent 1", isOn: $metronome.accentFirstBeat)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
    }

    private var keyControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker("Key", selection: $song.key) {
                Text("\u{2014}").tag("")
                Divider()
                ForEach(MusicalKey.all, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 104)
            Text("Key")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var beatIndicator: some View {
        HStack(spacing: 7) {
            ForEach(0..<max(1, song.beatsPerBar), id: \.self) { beat in
                Circle()
                    .fill(color(for: beat))
                    .frame(width: beat == 0 ? 13 : 10, height: beat == 0 ? 13 : 10)
                    .animation(.easeOut(duration: 0.06), value: metronome.displayBeat)
            }
        }
        .frame(minWidth: 90, alignment: .trailing)
    }

    private func color(for beat: Int) -> Color {
        guard metronome.isRunning, metronome.displayBeat == beat else {
            return Color.secondary.opacity(0.22)
        }
        return beat == 0 ? .accentColor : Color.secondary.opacity(0.75)
    }

    /// Tap tempo: average the gaps between recent taps, discarding any pause
    /// longer than two seconds as the start of a fresh attempt.
    private func registerTap() {
        let now = Date()
        if let last = taps.last, now.timeIntervalSince(last) > 2.0 {
            taps.removeAll()
        }
        taps.append(now)
        if taps.count > 6 { taps.removeFirst(taps.count - 6) }
        guard taps.count >= 3 else { return }

        var intervals: [TimeInterval] = []
        for i in 1..<taps.count {
            intervals.append(taps[i].timeIntervalSince(taps[i - 1]))
        }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0 else { return }
        song.bpm = min(max((60.0 / average).rounded(), 20), 400)
    }
}
