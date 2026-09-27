# Nightjar for iPhone

A SwiftUI music player with two screens:

- **Now Playing:** a risograph-style turntable. The record spins with the song, and the tonearm drops on and tracks inward. The song name and artist sit below it, then back / play / forward. The fader is the phone's volume, the small knob turns shuffle on and off, and the big knob opens the lyrics.
- **Lyrics:** a red retro phone display with black pixel type. Lines light up word by word, and you can tap a line to jump there. `menu` lists your songs, the middle key plays or pauses, and `clear` goes back to the turntable.

Songs come from your **Music library** (including Apple Music songs you've added) or from **audio files in the Files app**. Lyrics are fetched automatically from [LRCLIB](https://lrclib.net), a free, open database of synced lyrics. You can also import your own `.lrc` file. Give it the same name as the song, or import it on its own while that song is playing.

## Put it on your iPhone

You need a Mac with the Xcode version that supports iOS 27, a USB cable, and an Apple ID.

1. Copy the `Nightjar.swiftpm` folder to your Mac and double-click it. It opens in Xcode.
2. In Xcode, open **Settings → Accounts** and add your Apple ID.
3. Click **Nightjar** at the top of the file list, open **Signing & Capabilities**, and choose your Apple ID under **Team**. If Xcode says the bundle identifier is taken, change `com.zeno29.nightjar` to something unique.
4. Plug in your iPhone and unlock it. On the phone, turn on **Settings → Privacy & Security → Developer Mode** (the phone restarts).
5. Choose your iPhone in Xcode's device menu at the top, then press **Run** (▶).
6. The first time, open **Settings → General → VPN & Device Management** on the phone and trust your developer profile.

With a free Apple ID, the app stops opening after 7 days. Press Run again to reinstall it. A paid Apple Developer account ($99/year) removes that limit and lets you use TestFlight.

## Known gaps

- Songs from Files pause when you lock the phone, because an app package can't turn on the background-audio setting. Music-library songs keep playing. Moving to a full Xcode project fixes this.
- Apple Music songs need an active subscription, and they have to be in your library to show up in the picker.
- LRCLIB doesn't have every song. When it has nothing, the Lyrics screen says so and you can import a `.lrc` file.

## Files

- `App.swift`: app entry, screen switching, volume control, music picker
- `PlayerModel.swift`: playback (music library + files), queue, lock-screen controls
- `Lyrics.swift`: LRC parsing and the LRCLIB lookup
- `NowPlayingView.swift`: the turntable screen
- `LyricsScreen.swift`: the red phone lyrics screen
- `Resources/Fonts`: Young Serif, Spline Sans Mono, Pixelify Sans, Silkscreen (all SIL Open Font License)
