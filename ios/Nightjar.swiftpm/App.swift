import SwiftUI
import MediaPlayer
import AVFoundation
import UniformTypeIdentifiers

@main
struct NightjarApp: App {
    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    enum Screen { case deck, lyrics }

    @StateObject private var player = PlayerModel()
    @StateObject private var volume = VolumeController()
    @State private var screen: Screen = .deck
    @State private var askAdd = false
    @State private var showPicker = false
    @State private var showFiles = false

    private static let lyricTypes: [UTType] = [UTType(filenameExtension: "lrc"), UTType.plainText].compactMap { $0 }

    var body: some View {
        ZStack {
            switch screen {
            case .deck:
                NowPlayingView(openLyrics: { go(.lyrics) }, addSongs: { askAdd = true })
                    .transition(.opacity)
            case .lyrics:
                LyricsScreen(close: { go(.deck) }, addSongs: { askAdd = true })
                    .transition(.opacity)
            }
            // The system volume can only be set through an MPVolumeView in the view tree.
            VolumeHost(view: volume.view).frame(width: 1, height: 1).opacity(0.01).allowsHitTesting(false)

            if let text = player.message {
                VStack {
                    Spacer()
                    Text(text)
                        .font(Fonts.mono(13))
                        .foregroundColor(Theme.cream)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 4))
                        .padding(.bottom, 24).padding(.horizontal, 16)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: player.message)
        .environmentObject(player)
        .environmentObject(volume)
        .preferredColorScheme(screen == .deck ? .light : .dark)
        .confirmationDialog("Add songs", isPresented: $askAdd, titleVisibility: .visible) {
            Button("From your music library") {
                Task { if await player.requestLibraryAccess() { showPicker = true } }
            }
            Button("From Files (audio, .lrc lyrics)") { showFiles = true }
        }
        .sheet(isPresented: $showPicker) {
            MediaPicker(isPresented: $showPicker) { player.addLibraryItems($0) }
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFiles,
                      allowedContentTypes: [UTType.audio] + Self.lyricTypes,
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await player.addFiles(urls) }
            case .failure: player.flash("couldn't open those files.")
            }
        }
    }

    private func go(_ s: Screen) {
        withAnimation(.easeInOut(duration: 0.4)) { screen = s }
    }
}

// MARK: - System volume

@MainActor
final class VolumeController: ObservableObject {
    @Published var value: Float = AVAudioSession.sharedInstance().outputVolume
    let view = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 10, height: 10))
    private var observation: NSKeyValueObservation?

    init() {
        value = AVAudioSession.sharedInstance().outputVolume
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let v = session.outputVolume
            Task { @MainActor in self?.value = v }
        }
    }

    func set(_ v: Float) {
        value = v
        (view.subviews.first { $0 is UISlider } as? UISlider)?.value = v
    }
}

struct VolumeHost: UIViewRepresentable {
    let view: MPVolumeView
    func makeUIView(context: Context) -> MPVolumeView { view }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Music library picker

struct MediaPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: ([MPMediaItem]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = true
        picker.showsCloudItems = true
        picker.prompt = "Pick songs for Nightjar"
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: MPMediaPickerController, context: Context) {}

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let parent: MediaPicker
        init(_ parent: MediaPicker) { self.parent = parent }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems collection: MPMediaItemCollection) {
            parent.onPick(collection.items)
            parent.isPresented = false
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            parent.isPresented = false
        }
    }
}
