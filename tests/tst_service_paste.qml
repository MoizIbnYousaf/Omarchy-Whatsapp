import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// Ctrl+V only reads the clipboard, so it runs beside a send or a read mark
// instead of waiting in their queue (the owner could not paste while one ran).
TestCase {
  id: testCase
  name: "ServicePaste"

  Component { id: serviceComponent; Oma.Service {} }
  Component { id: spyComponent; SignalSpy {} }

  readonly property var target: ({ account: "work", jid: "synthetic@s.whatsapp.net" })

  function createService() {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.ready = true
    service.statusReady = true
    service.statusAccount = "work"
    return service
  }

  function finish(process, answer, code) {
    process.stdout.text = JSON.stringify(answer)
    process.running = false
    process.exited(code === undefined ? 0 : code)
  }

  function test_paste_runs_beside_a_write_in_flight() {
    var service = createService()
    service.writing = true
    verify(service.pasteClipboard(target, "app"))
    var paste = findChild(service, "pasteProcess")
    verify(paste.running)
    compare(JSON.parse(paste.payload), { account: "work", jid: target.jid })
    verify(!service.pasteClipboard(target, "app"), "one paste at a time")
    compare(service.activeWriteKind, "", "the write queue is untouched")
    var spy = createTemporaryObject(spyComponent, testCase, { target: service, signalName: "textPasted" })
    finish(paste, { ok: true, kind: "text", text: "hello" })
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "hello")
    compare(spy.signalArguments[0][1].jid, target.jid)
    compare(spy.signalArguments[0][2], "app")
  }

  function test_images_become_attachments_and_failures_are_reported() {
    var service = createService()
    var paste = findChild(service, "pasteProcess")
    var images = createTemporaryObject(spyComponent, testCase, { target: service, signalName: "attachmentPasted" })
    var failures = createTemporaryObject(spyComponent, testCase, { target: service, signalName: "pasteFailed" })
    verify(service.pasteClipboard(target, "dropdown"))
    finish(paste, { ok: true, kind: "image", path: "/run/user/0/omawhatsapp/clip.png" })
    compare(images.count, 1)
    compare(images.signalArguments[0][2], "dropdown")
    verify(service.pasteClipboard(target, "dropdown"))
    finish(paste, { ok: false, error: "wl-paste is missing" }, 1)
    compare(failures.count, 1)
    compare(failures.signalArguments[0][0], "wl-paste is missing")
  }

  function test_offline_mode_still_pastes() {
    var service = createService()
    service.offlineMode = true
    verify(service.pasteClipboard(target, "app"))
  }

  function test_no_chat_no_paste() {
    var service = createService()
    verify(!service.pasteClipboard({ account: "work", jid: "" }, "app"))
  }
}
