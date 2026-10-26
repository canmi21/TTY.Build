@testable import TTYBuild
import GhosttyTerminal
import UIKit
import XCTest

/// Query replies around a replay snapshot. Replayed history re-asks queries
/// that were answered long ago, so those replies must stay off the PTY; but a
/// shell can still be blocked on a query at the end of the snapshot (fish 4.x
/// waits for its startup Primary Device Attributes reply), and that one must
/// be answered or the session never reaches a prompt.
@MainActor
final class TerminalReplayQueryTests: XCTestCase {
    /// fish 4.9 startup output up to the point where it blocks on DA1, as
    /// captured from a real PTY (with a config.fish line printing first).
    private static let fishStartup = Data(
        ("CapLockDelayOverride:0\r\n\u{1b}[?u\u{1b}[>0q\u{1b}]11;?\u{1b}\\"
            + "\u{1b}[?1049h\u{1b}P+q696e646e\u{1b}\\"
            + "\u{1b}P+q71756572792d6f732d6e616d65\u{1b}\\"
            + "\u{1b}[?1049l\u{1b}[0c").utf8
    )

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// Control: the attached emulator answers DA1 at all, so a missing reply
    /// in the tests below is the host's filtering, not the harness.
    func testLiveQueryWithoutReplayIsAnswered() {
        let (host, inputs) = makeAttachedHost()

        host.feed(Data("\u{1b}[0c".utf8))

        XCTAssertTrue(waitUntil { inputs.containsDeviceAttributesReply })
    }

    func testReplayEndingInUnansweredQueryIsAnswered() {
        let (host, inputs) = makeAttachedHost()

        host.feedReplay(Self.fishStartup)

        XCTAssertTrue(
            waitUntil { inputs.containsDeviceAttributesReply },
            "fish stays blocked forever without a DA1 reply"
        )
    }

    func testLiveQueryRightAfterReplayIsAnswered() {
        let (host, inputs) = makeAttachedHost()

        host.feedReplay(Data("prompt> ".utf8))
        host.feed(Data("\u{1b}[0c".utf8))

        XCTAssertTrue(waitUntil { inputs.containsDeviceAttributesReply })
    }

    func testQueryAnsweredEarlierInHistoryIsNotReanswered() {
        let (host, inputs) = makeAttachedHost()

        host.feedReplay(Data("\u{1b}[0cWelcome\r\nprompt> ".utf8))

        XCTAssertFalse(waitUntil(timeout: 1) { inputs.containsDeviceAttributesReply })
    }

    // MARK: - Helpers

    private final class Inputs {
        var chunks: [Data] = []

        var containsDeviceAttributesReply: Bool {
            chunks.contains { chunk in
                chunk.starts(with: Data("\u{1b}[?".utf8)) && chunk.last == UInt8(ascii: "c")
            }
        }
    }

    /// A host whose Ghostty surface is attached, so received bytes are parsed
    /// (and answered) instead of queued until a view joins a window.
    private func makeAttachedHost() -> (TerminalHost, Inputs) {
        let host = TerminalHost(controller: TerminalController())
        let inputs = Inputs()
        host.onInput = { inputs.chunks.append($0) }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        window.rootViewController = root
        host.view.frame = root.view.bounds
        root.view.addSubview(host.view)
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        self.window = window

        // Let the surface attach and the initial size report settle.
        _ = waitUntil(timeout: 0.5) { false }
        inputs.chunks.removeAll()
        return (host, inputs)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }
}
