import SwiftUI

// MARK: - Turntable

/// Drawn in a 430×430 design space (the same one as the web prototype), scaled to fit.
private let design: CGFloat = 430
private let pad: CGFloat = 6
private let center = CGPoint(x: 188, y: 214)
private let armPivot = CGPoint(x: 362, y: 50)

private func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

private struct Groove {
    let r: CGFloat, width: CGFloat, opacity: Double, dash: [CGFloat], phase: CGFloat

    static let all: [Groove] = {
        var seed: UInt64 = 7
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double(seed >> 11) / Double(1 << 53))
        }
        var out: [Groove] = []
        var r: CGFloat = 70
        while r < 164 {
            let c = 2 * .pi * r, a = c * (0.08 + rnd() * 0.3), b = c * (0.03 + rnd() * 0.12)
            out.append(Groove(r: r, width: 0.6 + rnd() * 1.1, opacity: 0.25 + Double(rnd()) * 0.5,
                              dash: [a, b, a * 0.4, b * 2], phase: rnd() * c))
            r += 2.6 + rnd() * 1.6
        }
        return out
    }()
}

struct TurntableView: View {
    @EnvironmentObject var player: PlayerModel
    let inks: Inks

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / design
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !player.isPlaying)) { _ in
                    // 33⅓ rpm is 200° per second, tied to the song position so seeking turns the record.
                    let angle = player.liveTime() * 200
                    Canvas { ctx, _ in drawRecord(&ctx, k: k, angle: angle) }
                }
                Canvas { ctx, _ in drawArm(&ctx, k: k) }
                    .rotationEffect(.degrees(armAngle),
                                    anchor: UnitPoint(x: (armPivot.x + pad) / design, y: (armPivot.y + pad) / design))
                    .animation(.easeInOut(duration: 1.1), value: armAngle)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Record player")
    }

    /// Rests off the record when stopped; drops on and tracks inward as the song plays.
    private var armAngle: Double {
        (player.isPlaying || player.time > 0.3) ? 14 + 15 * player.progress : 0
    }

    private func drawRecord(_ ctx: inout GraphicsContext, k: CGFloat, angle: Double) {
        var c = ctx
        c.scaleBy(x: k, y: k)
        c.translateBy(x: pad, y: pad)
        // Misregistered second ink under the disc.
        c.fill(circle(176, 228, 166), with: .color(inks.label.opacity(0.92)))

        var d = c
        d.translateBy(x: center.x, y: center.y)
        d.rotate(by: .degrees(angle))
        d.translateBy(x: -center.x, y: -center.y)
        d.fill(circle(center.x, center.y, 166), with: .color(inks.disc))
        for g in Groove.all {
            d.stroke(circle(center.x, center.y, g.r), with: .color(Theme.cream.opacity(g.opacity)),
                     style: StrokeStyle(lineWidth: g.width, dash: g.dash, dashPhase: g.phase))
        }
        d.fill(circle(center.x, center.y, 62), with: .color(inks.label))
        if let art = player.artwork {
            var l = d
            l.clip(to: circle(center.x, center.y, 58))
            l.opacity = 0.9
            l.draw(Image(uiImage: art), in: CGRect(x: center.x - 58, y: center.y - 58, width: 116, height: 116))
        } else {
            d.draw(Text("NIGHTJAR").font(Fonts.mono(8)).tracking(2).foregroundColor(Theme.cream.opacity(0.85)),
                   at: CGPoint(x: center.x, y: center.y + 36))
        }
        d.stroke(circle(center.x, center.y, 62), with: .color(Color(hex: 0xF3E2B8, opacity: 0.6)), lineWidth: 1.2)
        var shine = Path()
        shine.addArc(center: center, radius: 42, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
        d.stroke(shine, with: .color(Theme.cream.opacity(0.55)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        d.fill(circle(center.x, center.y, 5), with: .color(Theme.cream))

        // Printed grain stays still while the record turns.
        var g = c
        g.clip(to: circle(center.x, center.y, 166))
        g.opacity = 0.35
        g.draw(Image(uiImage: Grain.light).resizable(resizingMode: .tile),
               in: CGRect(x: center.x - 166, y: center.y - 166, width: 332, height: 332))
    }

    private func drawArm(_ ctx: inout GraphicsContext, k: CGFloat) {
        var c = ctx
        c.scaleBy(x: k, y: k)
        c.translateBy(x: pad, y: pad)
        c.fill(circle(374, 74, 32), with: .color(inks.label))
        var stem = Path()
        stem.move(to: CGPoint(x: 362, y: 50))
        stem.addLine(to: CGPoint(x: 362, y: 286))
        stem.addLine(to: CGPoint(x: 344, y: 320))
        var shadow = c
        shadow.translateBy(x: -3, y: 3)
        shadow.stroke(stem, with: .color(inks.deep), style: StrokeStyle(lineWidth: 11, lineJoin: .round))
        c.stroke(stem, with: .color(Theme.cream), style: StrokeStyle(lineWidth: 9, lineJoin: .round))
        c.fill(circle(362, 30, 20), with: .color(Theme.brown))
        c.fill(circle(362, 52, 19), with: .color(Theme.brown))
        c.fill(circle(362, 52, 7), with: .color(Theme.cream))
        var h = c
        h.translateBy(x: 338, y: 330)
        h.rotate(by: .degrees(28))
        h.translateBy(x: -338, y: -330)
        let shell = Path(roundedRect: CGRect(x: 322, y: 316, width: 34, height: 26), cornerRadius: 2)
        h.fill(shell, with: .color(inks.label))
        h.stroke(shell, with: .color(inks.deep), lineWidth: 1.5)
        h.fill(circle(333, 329, 3), with: .color(Theme.cream))
        h.fill(circle(343, 327, 3), with: .color(Theme.cream))
        var lift = Path()
        lift.move(to: CGPoint(x: 350, y: 332))
        lift.addLine(to: CGPoint(x: 372, y: 342))
        c.stroke(lift, with: .color(Theme.cream), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}

// MARK: - Now Playing screen

struct NowPlayingView: View {
    @EnvironmentObject var player: PlayerModel
    @EnvironmentObject var volume: VolumeController
    var openLyrics: () -> Void
    var addSongs: () -> Void

    var body: some View {
        let inks = Inks.forTrack(player.current)
        ZStack {
            Theme.paper.ignoresSafeArea()
            Image(uiImage: Grain.dark).resizable(resizingMode: .tile)
                .blendMode(.multiply).opacity(0.5)
                .ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 12) {
                header
                TurntableView(inks: inks)
                    .frame(maxWidth: 440)
                    .layoutPriority(-1)
                titleBlock(inks)
                HStack(alignment: .bottom, spacing: 12) {
                    FaderView(value: Binding(get: { Double(volume.value) }, set: { volume.set(Float($0)) }), inks: inks)
                    VStack(spacing: 16) {
                        SeekBar(inks: inks)
                        HStack(spacing: 22) {
                            RisoButton(symbol: "backward.end.fill", size: 52, fill: inks.disc, shadow: inks.label, label: "Previous song") { player.previous() }
                            RisoButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 72, fill: inks.label, shadow: inks.disc,
                                       label: player.isPlaying ? "Pause" : "Play") {
                                if player.current == nil { addSongs() } else { player.toggle() }
                            }
                            RisoButton(symbol: "forward.end.fill", size: 52, fill: inks.disc, shadow: inks.label, label: "Next song") { player.next() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 14) {
                        KnobView(size: 34, label: "Shuf", inks: inks, turned: player.shuffle) {
                            player.shuffle.toggle()
                            player.flash(player.shuffle ? "shuffle on" : "shuffle off")
                        }
                        KnobView(size: 46, label: "Lyrics", inks: inks, turned: false, action: openLyrics)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundColor(Theme.ink)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                BrandMark().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NIGHTJAR").font(Fonts.serif(16)).tracking(2.2)
                    Text("RECORDS").font(Fonts.mono(9)).tracking(3).foregroundColor(Theme.inkSoft)
                }
            }
            Spacer()
            if !player.queue.isEmpty {
                Text("Side A · \(player.index + 1) of \(player.queue.count)".uppercased())
                    .font(Fonts.mono(10)).tracking(1.6).foregroundColor(Theme.inkSoft)
            }
            Button(action: addSongs) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .foregroundColor(Theme.ink)
            }
            .accessibilityLabel("Add songs")
        }
    }

    private func titleBlock(_ inks: Inks) -> some View {
        VStack(spacing: 4) {
            Text(player.current?.title ?? "Put a record on")
                .font(Fonts.serif(30))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text((player.current?.artist ?? "tap + to add songs").uppercased())
                .font(Fonts.mono(12)).tracking(2.2)
                .foregroundColor(inks.deep)
                .lineLimit(1)
        }
    }
}

// MARK: - Pieces

struct BrandMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 40
            ctx.scaleBy(x: s, y: s)
            ctx.fill(Path(ellipseIn: CGRect(x: 1, y: 1, width: 38, height: 38)), with: .color(Theme.inkSoft))
            var m = Path()
            m.move(to: CGPoint(x: 4, y: 26)); m.addLine(to: CGPoint(x: 14, y: 15)); m.addLine(to: CGPoint(x: 19, y: 20))
            m.addLine(to: CGPoint(x: 25, y: 12)); m.addLine(to: CGPoint(x: 36, y: 26)); m.closeSubpath()
            ctx.fill(m, with: .color(Theme.paper))
            for (y, x0, x1) in [(29.0, 5.0, 35.0), (32.0, 7.0, 33.0), (35.0, 10.0, 30.0)] {
                var l = Path(); l.move(to: CGPoint(x: x0, y: y)); l.addLine(to: CGPoint(x: x1, y: y))
                ctx.stroke(l, with: .color(Theme.paper), lineWidth: 1.2)
            }
        }
        .accessibilityHidden(true)
    }
}

struct RisoButton: View {
    let symbol: String
    let size: CGFloat
    let fill: Color
    let shadow: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundColor(Theme.cream)
        }
        .buttonStyle(RisoStyle(size: size, fill: fill, shadow: shadow))
        .accessibilityLabel(label)
    }
}

/// A flat print-style circle with an offset second-ink shadow; pressing it closes the gap.
struct RisoStyle: ButtonStyle {
    let size: CGFloat
    let fill: Color
    let shadow: Color

    func makeBody(configuration: Configuration) -> some View {
        let off: CGFloat = size > 60 ? 5 : 4
        let shift: CGFloat = configuration.isPressed ? off - 1 : 0
        return ZStack {
            Circle().fill(shadow).offset(x: -off, y: off)
            ZStack {
                Circle().fill(fill)
                configuration.label
            }
            .offset(x: -shift, y: shift)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct KnobView: View {
    let size: CGFloat
    let label: String
    let inks: Inks
    let turned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(inks.label).offset(x: -3, y: 3)
                    Circle().fill(inks.disc)
                    Capsule()
                        .fill(inks.label)
                        .overlay(Capsule().stroke(Theme.cream, lineWidth: 1.5))
                        .frame(width: 4, height: size * 0.32)
                        .offset(y: -size * 0.2)
                }
                .frame(width: size, height: size)
                .rotationEffect(.degrees(turned ? 120 : 0))
                .animation(.spring(response: 0.35, dampingFraction: 0.55), value: turned)
                Text(label.uppercased()).font(Fonts.mono(9)).tracking(1.8).foregroundColor(Theme.inkSoft)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label == "Shuf" ? "Shuffle" : label)
        .accessibilityValue(label == "Shuf" ? (turned ? "On" : "Off") : "")
    }
}

struct FaderView: View {
    @Binding var value: Double
    let inks: Inks
    private let height: CGFloat = 124

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 5).fill(inks.label).offset(x: -4, y: 4)
                RoundedRectangle(cornerRadius: 5).fill(inks.disc)
                Capsule().fill(Theme.brown).frame(width: 4).padding(.vertical, 14)
                RoundedRectangle(cornerRadius: 3)
                    .fill(inks.label)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.cream, lineWidth: 2))
                    .frame(width: 20, height: 14)
                    .offset(y: 14 + CGFloat(1 - value) * (height - 28) - 7)
            }
            .frame(width: 34, height: height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = Double(min(1, max(0, 1 - (g.location.y - 14) / (height - 28))))
            })
            Text("VOL").font(Fonts.mono(9)).tracking(1.8).foregroundColor(Theme.inkSoft)
        }
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(1, value + 0.0625)
            case .decrement: value = max(0, value - 0.0625)
            @unknown default: break
            }
        }
    }
}

struct SeekBar: View {
    @EnvironmentObject var player: PlayerModel
    let inks: Inks
    @State private var drag: Double?

    var body: some View {
        let p = drag ?? player.progress
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(inks.disc.opacity(0.4)).frame(height: 4)
                    Capsule().fill(inks.label).frame(width: max(4, geo.size.width * CGFloat(p)), height: 4)
                    ZStack {
                        Circle().fill(inks.label).offset(x: -2, y: 2)
                        Circle().fill(inks.disc)
                    }
                    .frame(width: 14, height: 14)
                    .offset(x: geo.size.width * CGFloat(p) - 7)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in drag = Double(min(1, max(0, g.location.x / geo.size.width))) }
                    .onEnded { _ in
                        if let d = drag { player.seek(to: d * player.duration) }
                        drag = nil
                    })
            }
            .frame(height: 20)
            HStack {
                Text(fmt(p * player.duration))
                Spacer()
                Text(fmt(player.duration))
            }
            .font(Fonts.mono(11))
            .monospacedDigit()
            .foregroundColor(Theme.inkSoft)
        }
        .accessibilityElement()
        .accessibilityLabel("Song position")
        .accessibilityValue("\(fmt(player.time)) of \(fmt(player.duration))")
        .accessibilityAdjustableAction { dir in
            player.seek(to: player.time + (dir == .increment ? 10 : -10))
        }
    }
}
