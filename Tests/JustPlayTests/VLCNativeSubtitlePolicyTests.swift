import XCTest
@testable import JustPlay

final class VLCNativeSubtitlePolicyTests: XCTestCase {
  func testReconcileWhileDisabledSuppressesUnexpectedNativeTrackSelection() {
    var policy = VLCNativeSubtitlePolicy()

    let disableCommands = policy.setNativeRenderingEnabled(false, currentTrackIndex: 3)
    XCTAssertEqual(disableCommands, [.setTrack(-1)])

    XCTAssertEqual(policy.reconcile(currentTrackIndex: -1), [])

    let replayCommands = policy.reconcile(currentTrackIndex: 3)
    XCTAssertEqual(replayCommands, [.setTrack(-1)])
  }

  func testEnablingNativeRenderingRestoresCachedTrack() {
    var policy = VLCNativeSubtitlePolicy()

    _ = policy.setNativeRenderingEnabled(false, currentTrackIndex: 4)

    let restoreCommands = policy.setNativeRenderingEnabled(true, currentTrackIndex: -1)
    XCTAssertEqual(restoreCommands, [.setTrack(4)])
  }

  func testEnablingNativeRenderingDoesNotRewriteWhenTrackAlreadyRestored() {
    var policy = VLCNativeSubtitlePolicy()

    _ = policy.setNativeRenderingEnabled(false, currentTrackIndex: 6)

    let restoreCommands = policy.setNativeRenderingEnabled(true, currentTrackIndex: 6)
    XCTAssertEqual(restoreCommands, [])
  }

  func testMediaDidLoadDropsStaleCachedTrack() {
    var policy = VLCNativeSubtitlePolicy()

    _ = policy.setNativeRenderingEnabled(false, currentTrackIndex: 2)
    policy.mediaDidLoad()

    let restoreCommands = policy.setNativeRenderingEnabled(true, currentTrackIndex: -1)
    XCTAssertEqual(restoreCommands, [])
  }
}
