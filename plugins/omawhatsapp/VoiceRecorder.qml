import QtQuick
import QtMultimedia
import Quickshell.Io
import "AccountModel.js" as AccountModel
import "VoiceRecorderModel.js" as VoiceModel

// One resident recorder is shared by the full client and compact dropdown.
// It records only after an explicit action, releases the microphone before
// review, and never sends until requestSend() is explicitly invoked.
Item {
  id: root
  visible: false
  width: 0
  height: 0

  property string helper: ""
  property string state: "idle"
  property string chatAccount: ""
  property string chatJid: ""
  property string chatName: ""
  property string replyId: ""
  property string draftPath: ""
  property string errorText: ""
  property int durationMs: 0
  property bool cancelAfterCreate: false
  property bool stopRequested: false
  property bool discardRequested: false
  property bool createBusy: createProcess.running
  property bool finalizeBusy: finalizeProcess.running
  property bool discardBusy: discardProcess.running

  readonly property bool active: VoiceModel.hasDraft(state)
  readonly property bool capturing: VoiceModel.isCapturing(state)
  readonly property bool reviewing: VoiceModel.canReview(state)
  readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
  readonly property int playbackPosition: Number(player.position || 0)
  readonly property bool formatSupported: recorder.mediaFormat.isSupported(MediaFormat.Encode)

  readonly property string chatKey: AccountModel.chatKey(chatAccount, chatJid)

  signal sendRequested(string account, string jid, string path, string replyId)
  signal notice(string message)

  function parseJson(raw) {
    try { return JSON.parse(String(raw || "{}")) } catch (error) { return null }
  }

  function fileUrl(path) {
    return "file://" + String(path || "").split("/")
      .map(function(part) { return encodeURIComponent(part) }).join("/")
  }

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") !== 0) return ""
    try { return decodeURIComponent(value.slice(7)) } catch (error) { return value.slice(7) }
  }

  function start(account, jid, name, reply) {
    var target = String(jid || "")
    if (target === "") {
      notice("Choose a chat before recording a voice note.")
      return false
    }
    if (state !== "idle") {
      notice(chatName !== ""
        ? "Finish or discard the voice draft for " + chatName + " first."
        : "Finish or discard the current voice draft first.")
      return false
    }
    if (!formatSupported) {
      state = "error"
      errorText = "This system cannot record WhatsApp-compatible OGG/Opus audio."
      notice(errorText)
      return false
    }
    chatAccount = String(account || "")
    chatJid = target
    chatName = String(name || "WhatsApp chat")
    replyId = String(reply || "")
    draftPath = ""
    durationMs = 0
    errorText = ""
    cancelAfterCreate = false
    stopRequested = false
    discardRequested = false
    state = "preparing"
    createProcess.payload = JSON.stringify({ action: "create" })
    createProcess.stdinEnabled = true
    createProcess.running = true
    return true
  }

  function toggle(account, jid, name, reply) {
    if (state === "recording") return stopToReview()
    if (state === "idle") return start(account, jid, name, reply)
    if (state === "preparing") {
      cancelAfterCreate = true
      state = "discarding"
      return true
    }
    notice(state === "review" ? "Review the draft, then send or discard it."
      : "The current voice-note action is still finishing.")
    return false
  }

  function stopToReview() {
    if (state === "preparing") {
      cancelAfterCreate = true
      state = "discarding"
      return true
    }
    if (state !== "recording") return false
    durationMs = Math.max(durationMs, Number(recorder.duration || 0))
    stopRequested = true
    discardRequested = false
    state = "finalizing"
    recorder.stop()
    return true
  }

  function stopForSurfaceClose() {
    if (state === "recording" || state === "preparing") stopToReview()
  }

  function stopForChatChange(nextAccount, nextJid) {
    if (AccountModel.chatKey(nextAccount, nextJid) !== chatKey
        && (state === "recording" || state === "preparing")) stopToReview()
  }

  function discard() {
    if (state === "idle" || state === "discarding") return false
    player.stop()
    errorText = ""
    if (state === "preparing") {
      cancelAfterCreate = true
      state = "discarding"
      return true
    }
    if (recorder.recorderState !== MediaRecorder.StoppedState
        || state === "recording" || state === "finalizing") {
      discardRequested = true
      stopRequested = false
      state = "discarding"
      if (recorder.recorderState !== MediaRecorder.StoppedState) recorder.stop()
      else discardDraftFile()
      return true
    }
    state = "discarding"
    discardDraftFile()
    return true
  }

  function discardDraftFile() {
    if (draftPath === "") {
      reset()
      return
    }
    discardProcess.payload = JSON.stringify({ action: "discard", path: draftPath })
    discardProcess.stdinEnabled = true
    discardProcess.running = true
  }

  function requestSend() {
    if (state !== "review" || draftPath === "") return false
    player.stop()
    sendRequested(chatAccount, chatJid, draftPath, replyId)
    return true
  }

  function markSending(account, jid) {
    if (AccountModel.chatKey(account, jid) !== chatKey || state !== "review") return
    state = "sending"
    errorText = ""
  }

  function markSendFailed(message, account, jid) {
    if (AccountModel.chatKey(account, jid) !== chatKey || state !== "sending") return
    state = "review"
    errorText = String(message || "Voice note could not be sent.")
  }

  function markSent(account, jid) {
    if (AccountModel.chatKey(account, jid) !== chatKey) return
    reset()
  }

  function playPause() {
    if (state !== "review" || draftPath === "") return false
    if (playing) player.pause()
    else {
      if (player.source.toString() !== fileUrl(draftPath)) player.source = fileUrl(draftPath)
      player.play()
    }
    return true
  }

  function reset() {
    player.stop()
    state = "idle"
    chatAccount = ""
    chatJid = ""
    chatName = ""
    replyId = ""
    draftPath = ""
    durationMs = 0
    errorText = ""
    cancelAfterCreate = false
    stopRequested = false
    discardRequested = false
  }

  AudioInput { id: microphone; muted: false }

  MediaRecorder {
    id: recorder
    mediaFormat.fileFormat: MediaFormat.Ogg
    mediaFormat.audioCodec: MediaFormat.AudioCodec.Opus
    quality: MediaRecorder.NormalQuality
    encodingMode: MediaRecorder.ConstantBitRateEncoding
    audioBitRate: 32000
    audioChannelCount: 1
    audioSampleRate: 48000
    onDurationChanged: function(value) {
      root.durationMs = Math.max(root.durationMs, Number(value || 0))
      if (Number(value || 0) >= 30 * 60 * 1000 && root.state === "recording")
        root.stopToReview()
    }
    onRecorderStateChanged: function(nextState) {
      if (nextState === MediaRecorder.RecordingState && root.state === "preparing")
        root.state = "recording"
      if (nextState !== MediaRecorder.StoppedState) return
      if (root.discardRequested || root.state === "discarding") {
        root.discardDraftFile()
        return
      }
      if (!root.stopRequested) return
      root.stopRequested = false
      var actual = root.localPath(recorder.actualLocation)
      if (actual !== "") root.draftPath = actual
      finalizeProcess.payload = JSON.stringify({
        action: "finalize",
        path: root.draftPath
      })
      finalizeProcess.stdinEnabled = true
      finalizeProcess.running = true
    }
    onErrorOccurred: function(_error, message) {
      root.errorText = String(message || "The microphone could not record this voice note.")
      root.notice(root.errorText)
      root.discard()
    }
  }

  CaptureSession {
    audioInput: microphone
    recorder: recorder
  }

  AudioOutput { id: previewOutput }
  MediaPlayer {
    id: player
    audioOutput: previewOutput
    onErrorOccurred: function(_error, message) {
      root.errorText = String(message || "The voice-note preview could not play.")
      root.notice(root.errorText)
    }
  }

  Process {
    id: createProcess
    property string payload: ""
    command: [root.helper, "voice-draft"]
    stdinEnabled: true
    stdout: StdioCollector { id: createOutput }
    stderr: StdioCollector { id: createError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      var result = root.parseJson(createOutput.text)
      if (exitCode !== 0 || !result || result.ok !== true) {
        root.errorText = (result && result.error)
          || String(createError.text || "A private voice draft could not be created.").trim()
        root.state = "error"
        root.notice(root.errorText)
        return
      }
      root.draftPath = String(result.path || "")
      if (root.cancelAfterCreate || root.state === "discarding") {
        root.discardDraftFile()
        return
      }
      recorder.outputLocation = root.fileUrl(root.draftPath)
      recorder.record()
    }
  }

  Process {
    id: finalizeProcess
    property string payload: ""
    command: [root.helper, "voice-draft"]
    stdinEnabled: true
    stdout: StdioCollector { id: finalizeOutput }
    stderr: StdioCollector { id: finalizeError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      var result = root.parseJson(finalizeOutput.text)
      if (exitCode !== 0 || !result || result.ok !== true) {
        root.errorText = (result && result.error)
          || String(finalizeError.text || "The voice draft could not be prepared.").trim()
        root.state = "error"
        root.notice(root.errorText)
        return
      }
      root.draftPath = String(result.path || root.draftPath)
      root.state = "review"
      player.source = root.fileUrl(root.draftPath)
    }
  }

  Process {
    id: discardProcess
    property string payload: ""
    command: [root.helper, "voice-draft"]
    stdinEnabled: true
    stdout: StdioCollector { id: discardOutput }
    stderr: StdioCollector { id: discardError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      var result = root.parseJson(discardOutput.text)
      if (exitCode !== 0 || !result || result.ok !== true) {
        root.errorText = (result && result.error)
          || String(discardError.text || "The private voice draft could not be discarded.").trim()
        root.state = "error"
        root.notice(root.errorText)
        return
      }
      root.reset()
    }
  }
}
