import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "PlaybackCoordinator"

  Component {
    id: coordinatorComponent
    Oma.PlaybackCoordinator {}
  }

  function test_one_lease_arbitrates_app_dropdown_and_viewer() {
    var coordinator = createTemporaryObject(coordinatorComponent, testCase)
    verify(coordinator !== null)
    var work = { account: "work", jid: "shared@example" }
    var home = { account: "home", jid: "shared@example" }

    verify(coordinator.acquire("app-timeline", work, "video-one"))
    verify(coordinator.owns("app-timeline", work, "video-one"))
    compare(coordinator.messageFor("app-timeline", work), "video-one")

    // The same synthetic JID in another account is a distinct playback owner.
    verify(coordinator.acquire("dropdown", home, "audio-two"))
    verify(!coordinator.owns("app-timeline", work, "video-one"))
    verify(coordinator.owns("dropdown", home, "audio-two"))
    compare(coordinator.messageFor("dropdown", work), "")

    // Opening viewer playback atomically revokes the dropdown's lease.
    verify(coordinator.acquire("app-viewer", work, "video-one"))
    verify(!coordinator.owns("dropdown", home, "audio-two"))
    verify(coordinator.owns("app-viewer", work, "video-one"))
    verify(coordinator.releaseSurface("app-viewer"))
    compare(coordinator.lease.messageId, "")
  }

  function test_invalid_requests_never_displace_the_current_player() {
    var coordinator = createTemporaryObject(coordinatorComponent, testCase)
    verify(coordinator.acquire("dropdown",
      { account: "work", jid: "chat@example" }, "audio-one"))
    verify(!coordinator.acquire("app-viewer",
      { account: "work", jid: "" }, "video-two"))
    verify(coordinator.owns("dropdown",
      { account: "work", jid: "chat@example" }, "audio-one"))
    verify(!coordinator.releaseSurface("another-surface"))
  }
}
