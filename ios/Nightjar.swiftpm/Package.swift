// swift-tools-version: 5.9

// Swift Playgrounds / Xcode app package. Double-click this folder on a Mac to open it in Xcode.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Nightjar",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Nightjar",
            targets: ["AppModule"],
            bundleIdentifier: "com.zeno29.nightjar",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait
            ],
            capabilities: [
                .appleMusic(purposeString: "Nightjar plays songs from your music library.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            resources: [
                .copy("Resources/Fonts")
            ]
        )
    ]
)
