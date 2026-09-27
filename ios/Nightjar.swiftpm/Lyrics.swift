import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: TimeInterval
    let text: String
}

enum LyricsState: Equatable {
    case idle
    case loading
    case synced([LyricLine])
    case plain([String])
    case instrumental
    case notFound
    case failed(String)
}

enum LRC {
    private static let tag = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.:]\d+)?)\]"#)

    /// Parses `[mm:ss.xx] text` lines. Returns an empty array when the text has no timestamps.
    static func parse(_ text: String) -> [LyricLine] {
        var out: [(TimeInterval, String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = tag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            let body = tag.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                out.append((min * 60 + sec, body.isEmpty ? "· · ·" : body))
            }
        }
        return out.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    /// A user-supplied .lrc or .txt file: synced when it has timestamps, plain otherwise.
    static func state(from text: String) -> LyricsState {
        let lines = parse(text)
        if !lines.isEmpty { return .synced(lines) }
        let plain = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return plain.isEmpty ? .notFound : .plain(plain)
    }
}

/// Looks lyrics up on LRCLIB (https://lrclib.net), a free, open database of synced lyrics.
actor LyricsService {
    private struct Record: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private var cache: [String: LyricsState] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 12
        c.httpAdditionalHeaders = ["User-Agent": "Nightjar iOS music player 1.0"]
        return URLSession(configuration: c)
    }()

    func lookup(title: String, artist: String, album: String, duration: TimeInterval) async -> LyricsState {
        let key = "\(artist.lowercased())|\(title.lowercased())|\(Int(duration))"
        if let hit = cache[key] { return hit }
        let cleanTitle = Self.clean(title)
        do {
            if !album.isEmpty, duration > 0,
               let rec = try await get(title: cleanTitle, artist: artist, album: album, duration: duration),
               let s = Self.state(from: rec) {
                cache[key] = s
                return s
            }
            let found = try await search(title: cleanTitle, artist: artist)
            let close = found.filter { duration <= 0 || abs(($0.duration ?? duration) - duration) < 6 }
            let ranked = close.sorted { ($0.syncedLyrics?.isEmpty == false ? 0 : 1) < ($1.syncedLyrics?.isEmpty == false ? 0 : 1) }
            for rec in ranked + found {
                if let s = Self.state(from: rec) {
                    cache[key] = s
                    return s
                }
            }
            cache[key] = .notFound
            return .notFound
        } catch is CancellationError {
            return .idle
        } catch {
            return .failed("couldn't reach lrclib. check your connection, then press menu → search lyrics again.")
        }
    }

    func forget(title: String, artist: String, duration: TimeInterval) {
        cache["\(artist.lowercased())|\(title.lowercased())|\(Int(duration))"] = nil
    }

    private func get(title: String, artist: String, album: String, duration: TimeInterval) async throws -> Record? {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        let (data, resp) = try await session.data(from: c.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private func search(title: String, artist: String) async throws -> [Record] {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty, artist != Track.unknownArtist {
            c.queryItems?.append(URLQueryItem(name: "artist_name", value: artist))
        }
        let (data, resp) = try await session.data(from: c.url!)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    private static func state(from rec: Record) -> LyricsState? {
        if rec.instrumental == true { return .instrumental }
        if let s = rec.syncedLyrics, !s.isEmpty {
            let lines = LRC.parse(s)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let p = rec.plainLyrics, !p.isEmpty {
            return .plain(p.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        }
        return nil
    }

    /// Drops "(feat. …)", "[Remastered 2011]", "- Radio Edit" and similar so the search matches.
    static func clean(_ title: String) -> String {
        var t = title
        let noise = #"(?i)\s*[\(\[][^\)\]]*(feat\.?|ft\.|with |remaster|version|edit|mono|stereo|live|explicit|bonus)[^\)\]]*[\)\]]"#
        t = t.replacingOccurrences(of: noise, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?i)\s+-\s+.*(remaster|version|edit|live|mono|stereo).*$"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }
}
