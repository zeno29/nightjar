import SwiftUI
import UIKit
import CoreText

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    static let paper = Color(hex: 0xECE5D6)
    static let ink = Color(hex: 0x2C2A33)
    static let inkSoft = Color(hex: 0x6B6470)
    static let cream = Color(hex: 0xF3EAD6)
    static let brown = Color(hex: 0x5B3F3D)
    static let lcd = Color(hex: 0xF3160F)
    static let lcdInk = Color(hex: 0x0B0B0B)
    static let night = Color(hex: 0x050505)
}

/// Two-ink risograph palettes; each song gets one, picked from its name.
struct Inks {
    let disc: Color
    let deep: Color
    let label: Color

    static let all: [Inks] = [
        Inks(disc: Color(hex: 0x5A85B3), deep: Color(hex: 0x3F6897), label: Color(hex: 0xE0552B)),
        Inks(disc: Color(hex: 0x3F8F86), deep: Color(hex: 0x2C6B64), label: Color(hex: 0xE8657A)),
        Inks(disc: Color(hex: 0xC9973A), deep: Color(hex: 0x9A6F24), label: Color(hex: 0x3D5F9A)),
        Inks(disc: Color(hex: 0x8A6BB0), deep: Color(hex: 0x644A88), label: Color(hex: 0xE7A03A)),
    ]

    static func forTrack(_ track: Track?) -> Inks {
        guard let track else { return all[0] }
        var h: UInt64 = 5381
        for b in (track.title + track.artist).utf8 { h = h &* 33 &+ UInt64(b) }
        return all[Int(h % UInt64(all.count))]
    }
}

enum Fonts {
    static func register() {
        var urls = Set<URL>()
        for bundle in [Bundle.module, Bundle.main] {
            for ext in ["ttf", "otf"] {
                bundle.urls(forResourcesWithExtension: ext, subdirectory: "Fonts")?.forEach { urls.insert($0) }
                bundle.urls(forResourcesWithExtension: ext, subdirectory: nil)?.forEach { urls.insert($0) }
            }
        }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // PostScript names of the bundled fonts (all SIL Open Font License).
    static func serif(_ size: CGFloat) -> Font { .custom("YoungSerif-Regular", size: size) }
    static func mono(_ size: CGFloat) -> Font { .custom("SplineSansMono-Regular", size: size) }
    static func pixel(_ size: CGFloat) -> Font { .custom("PixelifySans-Regular", size: size) }
    static func keys(_ size: CGFloat) -> Font { .custom("Silkscreen-Bold", size: size) }
}

/// Speckle textures for the printed-paper look.
enum Grain {
    static let dark: UIImage = make(color: UIColor(red: 0.35, green: 0.3, blue: 0.25, alpha: 1), density: 0.10)
    static let light: UIImage = make(color: UIColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 1), density: 0.07)

    private static func make(color: UIColor, density: Double) -> UIImage {
        let size = 192
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(1 << 53)
            }
            for y in 0..<size {
                for x in 0..<size where rnd() < density {
                    color.withAlphaComponent(0.25 + rnd() * 0.6).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }
}

func fmt(_ s: TimeInterval) -> String {
    let v = max(0, s.isFinite ? s : 0)
    return "\(Int(v) / 60):" + String(format: "%02d", Int(v) % 60)
}
