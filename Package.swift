// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TapDeck",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TouchInput", targets: ["TouchInput"]),
        .library(name: "Recognizer", targets: ["Recognizer"]),
        .library(name: "Actions", targets: ["Actions"]),
        .library(name: "Config", targets: ["Config"]),
        .executable(name: "tapdeck-spike", targets: ["tapdeck-spike"]),
    ],
    targets: [
        // C declarations for Apple's private MultitouchSupport.framework.
        // Types only: the symbols are resolved at runtime with dlopen/dlsym.
        .target(name: "CMultitouch"),
        .target(name: "TouchInput", dependencies: ["CMultitouch"]),
        // Pure gesture state machine: no OS calls, fully unit-testable.
        .target(name: "Recognizer", dependencies: ["TouchInput"]),
        // What gestures trigger: apps, keystrokes, windows, media keys.
        .target(name: "Actions"),
        .executableTarget(name: "tapdeck-spike", dependencies: ["TouchInput", "Recognizer", "Actions"]),
        .testTarget(name: "RecognizerTests", dependencies: ["Recognizer"]),
        .testTarget(name: "ActionsTests", dependencies: ["Actions"]),
        // Saved bindings and settings (JSON in Application Support).
        .target(name: "Config", dependencies: ["Actions", "Recognizer"]),
        .testTarget(name: "ConfigTests", dependencies: ["Config"]),
        // Runtime pipeline: trackpad + clicks -> recognizer -> actions.
        .target(name: "Engine", dependencies: ["TouchInput", "Recognizer", "Actions", "Config"]),
    ]
)
