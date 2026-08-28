import QtQuick
import QtTest
import "../plugins/omawhatsapp/VoiceRecorderModel.js" as VoiceModel

TestCase {
  name: "VoiceRecorderModel"

  function test_states_are_fail_closed() {
    compare(VoiceModel.normalizeState(" recording "), "recording")
    compare(VoiceModel.normalizeState("future-state"), "idle")
    verify(VoiceModel.hasDraft("review"))
    verify(VoiceModel.hasDraft("error"))
    verify(!VoiceModel.hasDraft("idle"))
    verify(VoiceModel.isCapturing("preparing"))
    verify(VoiceModel.isCapturing("recording"))
    verify(!VoiceModel.isCapturing("review"))
    verify(VoiceModel.canReview("review"))
  }

  function test_labels_describe_draft_first_flow() {
    compare(VoiceModel.stateLabel("recording", false), "Recording voice note")
    compare(VoiceModel.stateLabel("review", false), "Voice draft ready")
    compare(VoiceModel.stateLabel("review", true), "Voice draft · offline")
    compare(VoiceModel.stateLabel("sending", false), "Sending voice note…")
  }

  function test_time_and_progress_are_bounded() {
    compare(VoiceModel.elapsedLabel(0), "00:00")
    compare(VoiceModel.elapsedLabel(65999), "01:05")
    compare(VoiceModel.elapsedLabel(99999999), "59:59")
    compare(VoiceModel.progress(50, 100), 0.5)
    compare(VoiceModel.progress(150, 100), 1)
    compare(VoiceModel.progress(-5, 100), 0)
    compare(VoiceModel.progress(5, 0), 0)
  }

}
