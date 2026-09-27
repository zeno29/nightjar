# Nightjar

A music player with two screens:

- **Now Playing:** a risograph-style turntable. The record spins with the song, and the tonearm drops on and tracks inward. The song name and artist sit below it, then back / play / forward.
- **Lyrics:** a red retro phone display with black pixel type. Lines light up word by word, and you can tap a line to jump there.

## Install it on your iPhone

1. Open the GitHub Pages address for this repository in **Safari**.
2. Tap **Share → Add to Home Screen**.
3. Open Nightjar from your Home Screen. It runs full-screen like an app.

To connect Spotify, open the menu on the Lyrics screen and choose **connect spotify**. Nightjar then follows whatever the Spotify app is playing. Playback controls need Spotify Premium.

Tap **+ ADD** to pick songs from the Files app. The songs are saved on your phone, so they're still there next time. Nightjar reads each song's title, artist, album and cover from its tags, or from a file name like `Artist - Title.mp3`. It then fetches lyrics automatically from [LRCLIB](https://lrclib.net), a free, open lyrics database. You can also import a `.lrc` file with the same name as the song.

Three demo songs (original music, synthesized in the browser) are included, so you can try it right away.

## What's where

- `index.html`: the whole app
- `sw.js`, `manifest.webmanifest`, `icons/`: what makes it installable and usable offline
- `ios/`: a native SwiftUI version, which needs a Mac with Xcode to build
