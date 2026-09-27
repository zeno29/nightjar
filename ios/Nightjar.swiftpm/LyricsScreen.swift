import SwiftUI

/// The red phone display: pixel lyrics that light up word by word, with menu / play / clear soft keys.
struct LyricsScreen: View {
    @EnvironmentObject var player: PlayerModel
    var close: () -> Void
    var addSongs: () -> Void
    @State private var showMenu = false

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            VStack(spacing: 0) {
                StatusIcons()
                    .frame(height: 24)
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                HStack {
                    Text((player.current?.title ?? "no song").lowercased())
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(fmt(player.time)).monospacedDigit()
                }
                .font(Fonts.keys(14))
                .padding(.horizontal, 22)
                .padding(.top, 12)

                Group {
                    if showMenu { menu } else { lyricsBody }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .clipped()

                HStack(alignment: .bottom, spacing: 14) {
                    Segments()
                    Headphones()
                        .frame(width: 64, height: 50)
                        .offset(y: bob)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)

                Rectangle().fill(Theme.lcdInk.opacity(0.75)).frame(height: 2)
                softKeys
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .foregroundColor(Theme.lcdInk)
            .background(Theme.lcd)
            .overlay(Scanlines().allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.black.opacity(0.35), lineWidth: 3))
            .shadow(color: Theme.lcd.opacity(0.25), radius: 30)
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
        }
    }

    // MARK: Lyrics

    @ViewBuilder private var lyricsBody: some View {
        switch player.lyrics {
        case _ where player.current == nil:
            note("no song loaded.\npress menu to add songs.")
        case .idle, .loading:
            note("searching lrclib…")
        case .notFound:
            note("no lyrics found for this song.\npress menu to import a .lrc file.")
        case .failed(let why):
            note(why)
        case .instrumental:
            note("· instrumental ·")
        case .plain(let lines):
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("unsynced lyrics").font(Fonts.keys(11)).opacity(0.6)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        Text(l).font(Fonts.pixel(24))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 40)
            }
        case .synced(let lines):
            SyncedLyrics(lines: lines)
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(Fonts.pixel(21)).lineSpacing(4)
    }

    // MARK: Menu

    private var menu: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { i, t in
                    Button {
                        player.load(i, autoplay: true)
                        showMenu = false
                    } label: {
                        menuRow(String(format: "%02d", i + 1), t.title.lowercased(), fmt(t.duration), selected: i == player.index)
                    }
                    .contextMenu {
                        Button(role: .destructive) { player.remove(at: i) } label: { Label("Remove from Nightjar", systemImage: "trash") }
                    }
                }
                Button(action: addSongs) { menuRow("+", "add songs…", "", selected: false) }
                if player.current != nil {
                    Button {
                        player.fetchLyrics(force: true)
                        showMenu = false
                    } label: { menuRow("↻", "search lyrics again", "", selected: false) }
                }
            }
            .buttonStyle(MenuRowStyle())
        }
    }

    private func menuRow(_ n: String, _ title: String, _ right: String, selected: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(n).font(Fonts.keys(12)).frame(width: 26, alignment: .leading)
            Text(title).font(Fonts.pixel(21)).lineLimit(1)
            Spacer(minLength: 8)
            Text(right).font(Fonts.pixel(15)).monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundColor(selected ? Theme.lcd : Theme.lcdInk)
        .background(selected ? Theme.lcdInk : Color.clear)
    }

    // MARK: Soft keys

    private var softKeys: some View {
        HStack {
            Button("menu") { showMenu.toggle() }
            Spacer()
            Button(showMenu ? "lyrics" : (player.isPlaying ? "pause" : "play")) {
                if showMenu { showMenu = false } else if player.current == nil { addSongs() } else { player.toggle() }
            }
            Spacer()
            Button("clear", action: close)
        }
        .font(Fonts.keys(30))
        .buttonStyle(SoftKeyStyle())
    }

    private var bob: CGFloat {
        guard player.isPlaying else { return 0 }
        return Int(player.time * 3).isMultiple(of: 2) ? -3 : 0
    }
}

// MARK: - Synced lines

private struct SyncedLyrics: View {
    @EnvironmentObject var player: PlayerModel
    let lines: [LyricLine]

    var body: some View {
        let active = lines.lastIndex { $0.time <= player.time + 0.05 } ?? -1
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lines) { line in
                        Text(attributed(line, active: active))
                            .font(Fonts.pixel(27))
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.seek(to: line.time)
                                if !player.isPlaying { player.play() }
                            }
                            .id(line.id)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 260)
            }
            .onChange(of: active) { _, new in
                guard new >= 0 else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(lines[new].id, anchor: UnitPoint(x: 0, y: 0.25)) }
            }
            .onAppear {
                if active >= 0 { proxy.scrollTo(lines[active].id, anchor: UnitPoint(x: 0, y: 0.25)) }
            }
        }
    }

    /// Past lines dim, upcoming lines faint, and the current line fills in word by word.
    private func attributed(_ line: LyricLine, active: Int) -> AttributedString {
        let words = line.text.split(separator: " ").map(String.init)
        let i = line.id
        var lit = 0
        if i == active {
            let end = i + 1 < lines.count ? lines[i + 1].time : line.time + 5
            let p = (player.time - line.time) / max(0.5, (end - line.time) * 0.85)
            let total = Double(words.reduce(0) { $0 + $1.count + 1 })
            var run = 0.0
            for w in words {
                run += Double(w.count + 1)
                if run / total - 0.5 / Double(max(1, words.count)) <= p { lit += 1 }
            }
        }
        var out = AttributedString()
        for (k, w) in words.enumerated() {
            var piece = AttributedString(k < words.count - 1 ? w + " " : w)
            let alpha: Double
            if i < active { alpha = 0.55 }
            else if i == active { alpha = k < lit ? 1 : 0.38 }
            else { alpha = 0.3 }
            piece.foregroundColor = Theme.lcdInk.opacity(alpha)
            out += piece
        }
        return out
    }
}

// MARK: - Pixel pieces

private struct Segments: View {
    @EnvironmentObject var player: PlayerModel

    var body: some View {
        let on = Int((player.progress * 24).rounded())
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { i in
                    Rectangle()
                        .fill(i < on ? Theme.lcdInk : Color.clear)
                        .overlay(Rectangle().stroke(Theme.lcdInk, lineWidth: 2))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { loc in
                player.seek(to: Double(loc.x / geo.size.width) * player.duration)
            }
        }
        .frame(height: 12)
        .padding(.bottom, 6)
        .accessibilityElement()
        .accessibilityLabel("Song position")
        .accessibilityValue("\(fmt(player.time)) of \(fmt(player.duration))")
    }
}

private struct StatusIcons: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.height / 24
            ctx.scaleBy(x: s, y: s)
            let ink = GraphicsContext.Shading.color(Theme.lcdInk)
            // Antenna and signal bars
            for r in [CGRect(x: 0, y: 0, width: 12, height: 3), CGRect(x: 4, y: 3, width: 4, height: 3), CGRect(x: 5, y: 6, width: 2, height: 18),
                      CGRect(x: 11, y: 17, width: 3, height: 7), CGRect(x: 17, y: 12, width: 3, height: 12),
                      CGRect(x: 23, y: 7, width: 3, height: 17), CGRect(x: 29, y: 1, width: 3, height: 23)] {
                ctx.fill(Path(r), with: ink)
            }
            // Envelope
            ctx.stroke(Path(CGRect(x: 42.5, y: 3.5, width: 31, height: 18)), with: ink, lineWidth: 2.4)
            var flap = Path()
            flap.move(to: CGPoint(x: 43, y: 4)); flap.addLine(to: CGPoint(x: 58, y: 15)); flap.addLine(to: CGPoint(x: 73, y: 4))
            ctx.stroke(flap, with: ink, lineWidth: 2.4)
            // Battery, right aligned
            let bx = size.width / s - 52
            ctx.stroke(Path(CGRect(x: bx + 5.5, y: 2.5, width: 45, height: 19)), with: ink, lineWidth: 2.4)
            ctx.fill(Path(CGRect(x: bx, y: 8, width: 5, height: 8)), with: ink)
            for x in [10.0, 21.0, 32.0] { ctx.fill(Path(CGRect(x: bx + x, y: 6, width: 8, height: 12)), with: ink) }
            ctx.fill(Path(CGRect(x: bx + 43, y: 6, width: 5, height: 12)), with: ink)
        }
        .accessibilityHidden(true)
    }
}

private struct Headphones: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 80, y: size.height / 64)
            var band = Path()
            band.move(to: CGPoint(x: 12, y: 40))
            band.addCurve(to: CGPoint(x: 68, y: 40), control1: CGPoint(x: 8, y: 12), control2: CGPoint(x: 72, y: 12))
            ctx.stroke(band, with: .color(Theme.lcdInk), lineWidth: 5)
            for x in [15.0, 65.0] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 9, y: 35, width: 18, height: 26)), with: .color(Theme.lcdInk))
            }
            for x in [18.0, 62.0] {
                ctx.stroke(Path(ellipseIn: CGRect(x: x - 4, y: 40, width: 8, height: 16)), with: .color(Theme.lcd), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.07)))
                y += 3
            }
        }
        .drawingGroup()
    }
}

private struct SoftKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(configuration.isPressed ? Theme.lcd : Theme.lcdInk)
            .background(configuration.isPressed ? Theme.lcdInk : Color.clear)
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
