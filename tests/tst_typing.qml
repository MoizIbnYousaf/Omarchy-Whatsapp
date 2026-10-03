import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// The owner's report: the person on the other side saw them online but never
// "typing…". The app now says so as keys are typed, stops when the box
// empties or after a pause, says "recording audio…" for a voice note, and
// keeps quiet when "Show me online" is off.
TestCase {
  id: testCase
  name: "Typing"

  Component { id: serviceComponent; Oma.Service {} }
  readonly property var chatA: ({ account: "work", jid: "a@s.whatsapp.net" })
  readonly property var chatB: ({ account: "work", jid: "b@s.whatsapp.net" })

  function createService() {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.ready = true
    service.syncActive = true
    service.offlineMode = false
    service.showOnline = true
    return service
  }

  function sent(process) { return JSON.parse(process.payload) }
  function finish(process) { process.running = false; process.exited(0) }

  function test_typing_starts_once_and_stops_when_the_box_empties() {
    var service = createService()
    var process = findChild(service, "chatPresenceProcess")
    verify(service.composerActivity(chatA, "h"))
    verify(process.running)
    compare(sent(process).state, "typing")
    compare(sent(process).jid, chatA.jid)
    finish(process)
    process.payload = ""
    verify(service.composerActivity(chatA, "he"))
    compare(process.payload, "", "not again within 10 seconds")
    verify(service.composerActivity(chatA, ""))
    compare(sent(process).state, "paused", "sent or deleted: stopped")
    compare(service.typingState, "")
  }

  function test_leaving_a_chat_mid_word_stops_it_there() {
    var service = createService()
    var process = findChild(service, "chatPresenceProcess")
    service.composerActivity(chatA, "hel")
    verify(process.running)
    service.composerActivity(chatB, "o")
    compare(service.pendingChatPresence.map(function(item) { return item.jid + ":" + item.state }),
      ["a@s.whatsapp.net:paused", "b@s.whatsapp.net:typing"])
    finish(process)
    compare(sent(process).state, "paused")
    compare(sent(process).jid, chatA.jid)
    finish(process)
    compare(sent(process).jid, chatB.jid)
  }

  function test_a_pause_stops_typing_by_itself() {
    var service = createService()
    var process = findChild(service, "chatPresenceProcess")
    service.composerActivity(chatA, "x")
    finish(process)
    tryCompare(service, "typingState", "", 7000, "5 seconds without a key")
    compare(sent(process).state, "paused")
  }

  function test_nothing_is_said_with_show_online_off_or_without_sync() {
    var service = createService()
    var process = findChild(service, "chatPresenceProcess")
    service.showOnline = false
    verify(!service.composerActivity(chatA, "x"))
    verify(!process.running)
    service.showOnline = true
    service.syncActive = false
    verify(!service.composerActivity(chatA, "x"), "no sync: never a second session")
    verify(!process.running)
  }
}
