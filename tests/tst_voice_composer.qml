import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "VoiceComposer"

  QtObject {
    id: serviceMock
    property string voiceState: "review"
    property string voiceDraftAccount: "work"
    property string voiceDraftJid: "demo-chat"
    property int voiceDurationMs: 42000
    property int voicePlaybackPosition: 13000
    property bool voicePlaying: false
    property string requestedOwner: ""
    function sendVoiceDraft(owner) { requestedOwner = String(owner || ""); return true }
  }

  Component {
    id: composerComponent
    Oma.VoiceComposer {
      width: 480
      service: serviceMock
      owner: "app"
      account: "work"
      jid: "demo-chat"
      foreground: "#eeeeee"
      background: "#111111"
      accent: "#66ccaa"
      urgent: "#ee6666"
      muted: "#999999"
      fontFamily: "monospace"
    }
  }

  function test_review_is_visible_only_for_the_bound_chat() {
    var composer = createTemporaryObject(composerComponent, testCase)
    verify(composer !== null)
    compare(composer.forThisChat, true)
    verify(composer.implicitHeight > 0)
    composer.jid = "another-chat"
    compare(composer.forThisChat, false)
    composer.jid = "demo-chat"
    composer.account = "personal"
    compare(composer.forThisChat, false)
  }

  function test_demo_review_needs_no_transport_or_recorder() {
    var component = Qt.createComponent("../plugins/omawhatsapp/VoiceComposer.qml")
    compare(component.status, Component.Ready, component.errorString())
    var composer = createTemporaryObject(component, testCase, {
      width: 320,
      service: null,
      account: "work",
      jid: "demo-chat",
      demoAccount: "work",
      demoJid: "demo-chat",
      demoState: "review",
      demoDurationMs: 42000,
      demoPositionMs: 13000
    })
    verify(composer !== null)
    compare(composer.forThisChat, true)
    compare(composer.state, "review")
  }

  function test_offline_review_stays_visible() {
    var composer = createTemporaryObject(composerComponent, testCase, { offline: true })
    verify(composer !== null)
    compare(composer.forThisChat, true)
    compare(composer.offline, true)
  }

  function test_send_attributes_the_shared_draft_to_the_clicking_surface() {
    serviceMock.requestedOwner = ""
    var composer = createTemporaryObject(composerComponent, testCase)
    verify(composer !== null)
    var send = findChild(composer, "voiceSendAction")
    verify(send !== null)
    send.activated()
    compare(serviceMock.requestedOwner, "app")
  }
}
