import Foundation
import AVFoundation
import MediaPlayer
import UIKit

enum TrackSource: Codable, Hashable {
    /// A file copied into the app's Documents/Music folder, stored by file name.
    case file(String)
    /// A song from the Music app library (including Apple Music songs added to it).
    case library(UInt64)
}

struct Track: Identifiable, Codable, Hashable {
    static let unknownArtist = "Unknown artist"

    var id = UUID()
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var source: TrackSource
    /// Lyrics the user imported from a .lrc or .txt file. These win over the LRCLIB lookup.
    var localLyrics: String?
}

@MainActor
final class PlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var queue: [Track] = [] { didSet { save() } }
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var time: TimeInterval = 0
    @Published private(set) var lyrics: LyricsState = .idle
    @Published private(set) var artwork: UIImage?
    @Published var shuffle = false
    @Published var message: String?

    private var filePlayer: AVAudioPlayer?
    private let music = MPMusicPlayerController.applicationQueuePlayer
    private var timer: Timer?
    private var lastTime: TimeInterval = 0
    private var lyricsTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private let lyricsService = LyricsService()

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var duration: TimeInterval { current?.duration ?? 0 }
    var progress: Double { duration > 0 ? min(1, max(0, time / duration)) : 0 }

    static var musicFolder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        if let data = UserDefaults.standard.data(forKey: "queue"),
           let saved = try? JSONDecoder().decode([Track].self, from: data) {
            queue = saved
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        setupRemoteCommands()
        if !queue.isEmpty { load(0, autoplay: false) }
    }

    // MARK: Playback

    /// Current position, read straight from the player; used for smooth animation.
    func liveTime() -> TimeInterval {
        guard let t = current else { return 0 }
        switch t.source {
        case .file: return filePlayer?.currentTime ?? 0
        case .library:
            let v = music.currentPlaybackTime
            return v.isFinite ? max(0, v) : 0
        }
    }

    func load(_ i: Int, autoplay: Bool) {
        guard !queue.isEmpty else { return }
        filePlayer?.stop()
        filePlayer = nil
        if case .library = current?.source { music.pause() }
        index = (i % queue.count + queue.count) % queue.count
        time = 0
        lastTime = 0
        artwork = nil
        guard let t = current else { return }

        switch t.source {
        case .file(let name):
            let url = Self.musicFolder.appendingPathComponent(name)
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.delegate = self
                p.prepareToPlay()
                filePlayer = p
                if t.duration <= 0 { queue[index].duration = p.duration }
            } catch {
                flash("couldn't open \(t.title). it may have been deleted.")
            }
            let id = t.id
            Task {
                let art = await Self.fileArtwork(url)
                if self.current?.id == id { self.artwork = art }
            }
        case .library(let pid):
            if let item = Self.libraryItem(pid) {
                music.setQueue(with: MPMediaItemCollection(items: [item]))
                music.prepareToPlay()
                artwork = item.artwork?.image(at: CGSize(width: 400, height: 400))
            } else {
                flash("\(t.title) is no longer in your library.")
            }
        }
        fetchLyrics()
        if autoplay { play() } else { updateNowPlaying() }
    }

    func play() {
        guard let t = current else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        switch t.source {
        case .file: filePlayer?.play()
        case .library: music.play()
        }
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        filePlayer?.pause()
        if case .library = current?.source { music.pause() }
        isPlaying = false
        updateNowPlaying()
    }

    func toggle() { isPlaying ? pause() : play() }

    func seek(to s: TimeInterval) {
        guard let t = current else { return }
        let v = min(max(0, s), max(0, duration - 0.25))
        switch t.source {
        case .file: filePlayer?.currentTime = v
        case .library: music.currentPlaybackTime = v
        }
        time = v
        lastTime = v
        updateNowPlaying()
    }

    func next(auto: Bool = false) {
        guard !queue.isEmpty else { return }
        if shuffle, queue.count > 1 {
            var j = index
            while j == index { j = Int.random(in: 0..<queue.count) }
            load(j, autoplay: true)
        } else if auto, index == queue.count - 1 {
            load(0, autoplay: false)
        } else {
            load(index + 1, autoplay: true)
        }
    }

    func previous() {
        if liveTime() > 3 { seek(to: 0) } else { load(index - 1, autoplay: true) }
    }

    private func tick() {
        guard let t = current else { return }
        let now = liveTime()
        time = now
        if case .library = t.source {
            let playing = music.playbackState == .playing
            // A one-song queue ends by stopping; treat that as the song finishing.
            if isPlaying, !playing, lastTime > duration - 2, duration > 0 {
                lastTime = 0
                next(auto: true)
                return
            }
            if playing != isPlaying { isPlaying = playing }
        } else if let p = filePlayer, p.isPlaying != isPlaying {
            isPlaying = p.isPlaying
        }
        lastTime = now
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.next(auto: true) }
    }

    // MARK: Lyrics

    func fetchLyrics(force: Bool = false) {
        lyricsTask?.cancel()
        guard let t = current else { lyrics = .idle; return }
        if let local = t.localLyrics {
            lyrics = LRC.state(from: local)
            return
        }
        lyrics = .loading
        let id = t.id
        lyricsTask = Task {
            if force { await lyricsService.forget(title: t.title, artist: t.artist, duration: t.duration) }
            let result = await lyricsService.lookup(title: t.title, artist: t.artist, album: t.album, duration: t.duration)
            guard !Task.isCancelled, self.current?.id == id else { return }
            self.lyrics = result
        }
    }

    // MARK: Adding songs

    func requestLibraryAccess() async -> Bool {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            let status = await withCheckedContinuation { (c: CheckedContinuation<MPMediaLibraryAuthorizationStatus, Never>) in
                MPMediaLibrary.requestAuthorization { c.resume(returning: $0) }
            }
            return status == .authorized
        default:
            flash("allow Nightjar to use your music library in Settings → Nightjar.")
            return false
        }
    }

    func addLibraryItems(_ items: [MPMediaItem]) {
        let new = items.map {
            Track(title: $0.title ?? "Untitled",
                  artist: $0.artist ?? Track.unknownArtist,
                  album: $0.albumTitle ?? "",
                  duration: $0.playbackDuration,
                  source: .library($0.persistentID))
        }
        append(new)
    }

    func addFiles(_ urls: [URL]) async {
        var new: [Track] = []
        var lyricFiles: [(String, String)] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            let base = url.deletingPathExtension().lastPathComponent
            if ext == "lrc" || ext == "txt" {
                if let text = try? String(contentsOf: url, encoding: .utf8) { lyricFiles.append((base.lowercased(), text)) }
                continue
            }
            let name = UUID().uuidString.prefix(8) + "-" + url.lastPathComponent
            let dest = Self.musicFolder.appendingPathComponent(String(name))
            do { try FileManager.default.copyItem(at: url, to: dest) } catch {
                flash("couldn't import \(url.lastPathComponent).")
                continue
            }
            var track = await Self.fileTrack(dest, fallbackName: base)
            track.source = .file(String(name))
            new.append(track)
        }

        var matched = 0
        for (key, text) in lyricFiles {
            if let i = new.firstIndex(where: { Self.matches(key, $0) }) {
                new[i].localLyrics = text; matched += 1
            } else if let i = queue.firstIndex(where: { Self.matches(key, $0) }) {
                queue[i].localLyrics = text; matched += 1
            } else if new.isEmpty, lyricFiles.count == 1, current != nil {
                queue[index].localLyrics = text; matched += 1
            }
        }
        if !new.isEmpty {
            append(new)
        } else if matched > 0 {
            fetchLyrics()
        }
        var bits: [String] = []
        if !new.isEmpty { bits.append("added \(new.count) song\(new.count == 1 ? "" : "s")") }
        if matched > 0 { bits.append("lyrics for \(matched)") }
        if lyricFiles.count > matched { bits.append("\(lyricFiles.count - matched) lyric file(s) matched no song name") }
        if !bits.isEmpty { flash(bits.joined(separator: ", ")) }
    }

    func remove(at i: Int) {
        guard queue.indices.contains(i) else { return }
        let wasCurrent = i == index
        if case .file(let name) = queue[i].source {
            if wasCurrent { filePlayer?.stop(); filePlayer = nil }
            try? FileManager.default.removeItem(at: Self.musicFolder.appendingPathComponent(name))
        }
        queue.remove(at: i)
        if queue.isEmpty {
            index = 0; isPlaying = false; lyrics = .idle; artwork = nil; music.stop()
        } else if wasCurrent {
            load(min(i, queue.count - 1), autoplay: false)
        } else if i < index {
            index -= 1
        }
    }

    private func append(_ new: [Track]) {
        guard !new.isEmpty else { return }
        let first = queue.count
        queue.append(contentsOf: new)
        load(first, autoplay: true)
    }

    private static func matches(_ key: String, _ t: Track) -> Bool {
        let title = t.title.lowercased()
        return key == title || key == "\(t.artist.lowercased()) - \(title)" || key.hasSuffix(title) && title.count > 3
    }

    private static func fileTrack(_ url: URL, fallbackName: String) async -> Track {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        let meta = (try? await asset.load(.commonMetadata)) ?? []
        func string(_ id: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: id).first else { return nil }
            return try? await item.load(.stringValue)
        }
        let parts = fallbackName.components(separatedBy: " - ")
        let title = await string(.commonIdentifierTitle) ?? (parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : fallbackName)
        let artist = await string(.commonIdentifierArtist) ?? (parts.count > 1 ? parts[0] : Track.unknownArtist)
        let album = await string(.commonIdentifierAlbumName) ?? ""
        return Track(title: title, artist: artist, album: album, duration: duration.isFinite ? duration : 0, source: .file(url.lastPathComponent))
    }

    private static func fileArtwork(_ url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        guard let meta = try? await asset.load(.commonMetadata),
              let item = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .commonIdentifierArtwork).first,
              let data = try? await item.load(.dataValue) else { return nil }
        return UIImage(data: data)
    }

    private static func libraryItem(_ pid: UInt64) -> MPMediaItem? {
        let q = MPMediaQuery.songs()
        q.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: pid), forProperty: MPMediaItemPropertyPersistentID))
        return q.items?.first
    }

    // MARK: Misc

    func flash(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { self.message = nil }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(queue) { UserDefaults.standard.set(data, forKey: "queue") }
    }

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.play() }; return .success }
        cc.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        cc.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        cc.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
    }

    /// Lock-screen info for songs from Files. Music-library songs report their own.
    private func updateNowPlaying() {
        guard let t = current, case .file = t.source else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyPlaybackDuration: t.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: liveTime(),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }
}
