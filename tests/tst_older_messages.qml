import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// Scrolling up past the newest page loads the one before it, and the refresh
// of the newest page on every mirror change keeps the older pages.
TestCase {
  id: testCase
  name: "OlderMessages"

  Component { id: serviceComponent; Oma.Service {} }

  function createService() {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.selectedChatAccount = "work"
    service.selectedChatJid = "synthetic@s.whatsapp.net"
    service.messages = [{ id: "n2", timestamp: 30 }, { id: "n1", timestamp: 20 }]
    return service
  }

  function finish(service, payload) {
    var process = findChild(service, "olderProcess")
    process.stdout.text = JSON.stringify(payload)
    process.running = false
    process.exited(0)
  }

  function test_the_page_before_the_oldest_loaded_message_is_requested() {
    var service = createService()
    verify(service.loadOlderMessages())
    var request = JSON.parse(findChild(service, "olderProcess").payload)
    compare(request.before, { ts: 20, id: "n1" })
    verify(!service.loadOlderMessages(), "one page at a time")
    finish(service, { ok: true, has_more: true, messages: [{ id: "o2", timestamp: 15 }, { id: "o1", timestamp: 10 }] })
    compare(service.selectedMessages.map(function(m) { return m.id }), ["n2", "n1", "o2", "o1"])
    verify(service.loadOlderMessages())
    compare(JSON.parse(findChild(service, "olderProcess").payload).before, { ts: 10, id: "o1" })
    finish(service, { ok: true, has_more: false, messages: [{ id: "o0", timestamp: 5 }] })
    verify(!service.hasOlderMessages)
    verify(!service.loadOlderMessages(), "the start of the history ends the loading")
  }

  function test_refreshing_the_newest_page_keeps_older_pages() {
    var service = createService()
    service.loadOlderMessages()
    finish(service, { ok: true, has_more: true, messages: [{ id: "o1", timestamp: 10 }] })
    service.messages = [{ id: "n3", timestamp: 40 }, { id: "n2", timestamp: 30 }, { id: "n1", timestamp: 20 }]
    compare(service.selectedMessages.map(function(m) { return m.id }), ["n3", "n2", "n1", "o1"])
  }

  function test_a_search_shows_only_its_results_and_a_new_chat_starts_over() {
    var service = createService()
    service.loadOlderMessages()
    finish(service, { ok: true, has_more: true, messages: [{ id: "o1", timestamp: 10 }] })
    service.query = "needle"
    compare(service.selectedMessages.map(function(m) { return m.id }), ["n2", "n1"])
    verify(!service.loadOlderMessages())
    service.query = ""
    service.selectChat({ account: "work", jid: "other@s.whatsapp.net", name: "Other", kind: "dm" })
    compare(service.olderMessages.length, 0)
    verify(service.hasOlderMessages)
  }
}
