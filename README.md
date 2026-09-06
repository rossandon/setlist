# Setlist

A small macOS app for keeping a list of songs with their lyrics, tempo, and key,
plus a metronome that clicks at each song's BPM.

Built for a single machine. No installer, no signing identity, no Xcode.

## Features

- Song list with search across titles, artists, and lyrics
- Lyrics editor
- Tempo and key per song, with a 24-key picker
- **Drift-free metronome** — beat times are computed as absolute sample
  positions against the audio clock rather than scheduled on a run loop, so the
  click cannot drift relative to what you hear. Measured at 0.000 ppm error
  against target tempo.
- Accented downbeat, time signatures from 2/4 to 7/4
- Tap tempo, and half/double-time buttons for when a detected tempo lands an
  octave off
- Optional tempo and key lookup via [GetSongBPM](https://getsongbpm.com)
- Library stored as plain JSON at
  `~/Library/Application Support/Setlist/library.json`

## Building

Requires the Xcode Command Line Tools. Xcode itself is not needed.

```
./build.sh
open Setlist.app
```

`build.sh` calls `swiftc` directly rather than going through Swift Package
Manager. The app has no third-party dependencies, so nothing is lost by doing
so, and it sidesteps a SwiftPM breakage caused by mismatched Command Line Tools
versions.

## Tempo and key lookup

Lookup is optional and off until you supply an API key.

1. Get a free API key from [GetSongBPM](https://getsongbpm.com/api).
2. Open Settings (<kbd>⌘</kbd><kbd>,</kbd>) and paste it in. The key is stored
   in the login Keychain, not in the library file.
3. Press **Look Up** on any song.

Results are shown as candidates to choose from and are never applied
automatically. Automatic tempo and key detection is wrong often enough — and
wrong in confident-looking ways — that silently overwriting a value you verified
by ear would be the worse failure. Selecting a candidate fills only the fields
it actually carries.

To inspect the raw API response while debugging:

```
./tools/probe-getsongbpm.sh YOUR_API_KEY "Song Title" "Artist Name"
```

## Credits

Tempo and key data provided by **[GetSongBPM](https://getsongbpm.com)**.

## License

MIT
