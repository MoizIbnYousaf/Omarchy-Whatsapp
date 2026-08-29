import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "VoiceRecorder"

  Component {
    id: recorderComponent
    Oma.VoiceRecorder {
      chatAccount: "work"
      chatJid: "shared@s.whatsapp.net"
      state: "review"
    }
  }

  function test_send_state_is_bound_to_the_exact_account_and_chat() {
    var recorder = createTemporaryObject(recorderComponent, testCase)
    verify(recorder !== null)

    recorder.markSending("personal", "shared@s.whatsapp.net")
    compare(recorder.state, "review")
    recorder.markSending("work", "other@s.whatsapp.net")
    compare(recorder.state, "review")

    recorder.markSending("work", "shared@s.whatsapp.net")
    compare(recorder.state, "sending")
    recorder.markSendFailed("retry", "personal", "shared@s.whatsapp.net")
    compare(recorder.state, "sending")
    recorder.markSendFailed("retry", "work", "shared@s.whatsapp.net")
    compare(recorder.state, "review")
  }

  function test_chat_switch_compares_both_identity_halves() {
    var recorder = createTemporaryObject(recorderComponent, testCase, {
      state: "error"
    })
    verify(recorder !== null)
    compare(recorder.chatKey, "work\nshared@s.whatsapp.net")
  }
}
