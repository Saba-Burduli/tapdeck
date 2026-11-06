// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TapDeck",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TouchInput", targets: ["TouchInput"]),
        .library(name: "Recognizer", targets: ["Recognizer"]),
        .executable(name: "tapdeck-spike", targets: ["tapdeck-spike"]),
    ],
    targets: [
        // C declarations for Apple's private MultitouchSupport.framework.
        // Types only: the symbols are resolved at runtime with dlopen/dlsym.
        .target(name: "CMultitouch"),
        .target(name: "TouchInput", dependencies: ["CMultitouch"]),
        // Pure gesture state machine: no OS calls, fully unit-testable.
        .target(name: "Recognizer", dependencies: ["TouchInput"]),
        .executableTarget(name: "tapdeck-spike", dependencies: ["TouchInput", "Recognizer"]),
        .testTarget(name: "RecognizerTests", dependencies: ["Recognizer"]),
    ]
)
