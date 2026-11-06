import CoreGraphics
import Foundation
import Testing
@testable import Actions

// 1440x900 primary with a 25 pt menu bar; a 1920x1080 display to its right.
let primary = CGRect(x: 0, y: 25, width: 1440, height: 875)
let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

@Suite struct WindowLayoutTests {
    let window = CGRect(x: 100, y: 100, width: 800, height: 600)

    @Test func halves() {
        #expect(WindowLayout.frame(for: .leftHalf, window: window, screens: [primary]) == CGRect(x: 0, y: 25, width: 720, height: 875))
        #expect(WindowLayout.frame(for: .rightHalf, window: window, screens: [primary]) == CGRect(x: 720, y: 25, width: 720, height: 875))
        #expect(WindowLayout.frame(for: .topHalf, window: window, screens: [primary]) == CGRect(x: 0, y: 25, width: 1440, height: 438))
        #expect(WindowLayout.frame(for: .bottomHalf, window: window, screens: [primary])?.maxY == 900)
    }

    @Test func maximizeFillsTheUsableArea() {
        #expect(WindowLayout.frame(for: .maximize, window: window, screens: [primary]) == primary)
    }

    @Test func centerKeepsSize() {
        let r = WindowLayout.frame(for: .center, window: window, screens: [primary])
        #expect(r?.size == window.size)
        #expect(r?.midX == primary.midX)
    }

    @Test func oddSizedScreenHalvesStayWhole() {
        let odd = CGRect(x: 0, y: 0, width: 1441, height: 901)
        let r = WindowLayout.frame(for: .leftHalf, window: window, screens: [odd])!
        #expect(r.width == r.width.rounded() && r.height == 901)
        let right = WindowLayout.frame(for: .rightHalf, window: window, screens: [odd])!
        #expect(r.maxX == right.minX && right.maxX == 1441)   // tiles exactly, no gap or overlap
    }

    @Test func centerShrinksAnOversizedWindow() {
        let big = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        #expect(WindowLayout.frame(for: .center, window: big, screens: [primary]) == primary)
    }

    @Test func usesTheScreenHoldingMostOfTheWindow() {
        let onExternal = CGRect(x: 1500, y: 100, width: 800, height: 600)
        #expect(WindowLayout.frame(for: .leftHalf, window: onExternal, screens: [primary, external]) == CGRect(x: 1440, y: 0, width: 960, height: 1080))
    }

    @Test func nextDisplayKeepsRelativePlacementAndWraps() {
        let moved = WindowLayout.frame(for: .nextDisplay, window: window, screens: [primary, external])!
        #expect(external.contains(moved))
        let back = WindowLayout.frame(for: .nextDisplay, window: moved, screens: [primary, external])!
        #expect(primary.contains(back))
    }

    @Test func nextDisplayWithOneScreenDoesNothing() {
        #expect(WindowLayout.frame(for: .nextDisplay, window: window, screens: [primary]) == nil)
    }

    @Test func offScreenWindowUsesNearestScreen() {
        let lost = CGRect(x: 5000, y: 100, width: 400, height: 300)
        #expect(WindowLayout.frame(for: .maximize, window: lost, screens: [primary, external]) == external)
    }

    @Test func appKitToAXFlipsY() {
        // AppKit: menu-bar-excluded primary area is y 0...875 from the bottom.
        let appKit = CGRect(x: 0, y: 0, width: 1440, height: 875)
        #expect(WindowLayout.axRect(fromAppKit: appKit, primaryHeight: 900) == primary)
    }
}

@Suite struct ActionModelTests {
    @Test func mediaKeyEventData() {
        // NX_KEYTYPE_PLAY = 16; key down = 0xA, key up = 0xB in bits 8-15.
        #expect(MediaKey.playPause.eventData(down: true) == (16 << 16) | (0xA << 8))
        #expect(MediaKey.playPause.eventData(down: false) == (16 << 16) | (0xB << 8))
        #expect(MediaKey.volumeUp.eventData(down: true) == 0xA << 8)
    }

    @Test func modifierFlags() {
        let f = ActionRunner.flags([.command, .shift])
        #expect(f.contains(.maskCommand) && f.contains(.maskShift) && !f.contains(.maskControl))
    }

    @Test func arrowKeysCarryHardwareFlags() {
        // ⌃↑ (Mission Control) only works with the numeric-pad and fn flags real arrows send.
        let f = ActionRunner.flags(KeyCombo.missionControl.modifiers, keyCode: KeyCombo.missionControl.keyCode)
        #expect(f.contains(.maskControl) && f.contains(.maskNumericPad) && f.contains(.maskSecondaryFn))
        let letter = ActionRunner.flags([.command], keyCode: 0)
        #expect(!letter.contains(.maskNumericPad) && !letter.contains(.maskSecondaryFn))
    }

    @Test func keyComboDescription() {
        #expect(KeyCombo.screenshot.description == "⇧⌘4")
        #expect(KeyCombo.missionControl.description == "⌃↑")
    }

    @Test(arguments: [
        Action.openApp(bundleID: "com.apple.calculator"),
        .keystroke(.spotlight),
        .window(.leftHalf),
        .media(.playPause),
    ])
    func codableRoundTrip(action: Action) throws {
        let data = try JSONEncoder().encode(action)
        #expect(try JSONDecoder().decode(Action.self, from: data) == action)
    }
}
