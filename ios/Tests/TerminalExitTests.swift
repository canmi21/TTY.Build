@testable import TTYBuild
import XCTest

@MainActor
final class TerminalExitTests: XCTestCase {
    private var terminal: AttachedTerminalHost?

    override func tearDown() {
        terminal?.tearDown()
        terminal = nil
        super.tearDown()
    }

    func testOnlyCleanExitClosesTab() {
        XCTAssertTrue(TerminalExitPolicy.closesTab(exitCode: 0))
        XCTAssertFalse(TerminalExitPolicy.closesTab(exitCode: 1))
        XCTAssertFalse(TerminalExitPolicy.closesTab(exitCode: 143))
    }

    /// Ghostty treats a short-lived non-zero exit as a failed launch. A
    /// session that ran for a minute must read as an ordinary exit.
    func testLongRunningFailureIsNotReportedAsFailedLaunch() {
        let terminal = makeTerminal()

        terminal.host.markExited(code: 1, runtime: 60)

        XCTAssertTrue(AttachedTerminalHost.waitUntil {
            terminal.host.viewportText?.contains("Process exited") == true
        }, terminal.host.viewportText ?? "no viewport text")
        XCTAssertFalse(terminal.host.viewportText?.contains("failed to launch") == true)
    }

    private func makeTerminal() -> AttachedTerminalHost {
        let terminal = AttachedTerminalHost()
        self.terminal = terminal
        return terminal
    }
}
