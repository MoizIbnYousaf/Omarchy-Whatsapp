import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// Tapping a poll option votes through the helper's poll-vote command.
TestCase {
  id: testCase
  name: "ServicePollVote"

  Component { id: serviceComponent; Oma.Service {} }

  readonly property var target: ({ account: "work", jid: "team@g.us" })

  function createService() {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.ready = true
    service.statusReady = true
    service.statusAccount = "work"
    service.offlineMode = false
    return service
  }

  function test_a_vote_runs_poll_vote_with_the_exact_options() {
    var service = createService()
    verify(service.votePoll(target, { id: "poll1" }, ["Tuesday"], "app"))
    compare(service.activeWriteKind, "poll-vote")
    var process = findChild(service, "writeProcess")
    compare(process.command[1], "poll-vote")
    var request = JSON.parse(process.payload)
    compare(request.id, "poll1")
    compare(request.options, ["Tuesday"])
    compare(request.jid, "team@g.us")
  }

  function test_a_vote_needs_a_poll_and_a_choice() {
    var service = createService()
    verify(!service.votePoll(target, null, ["Tuesday"], "app"))
    verify(!service.votePoll(target, { id: "poll1" }, [], "app"))
    compare(service.activeWriteKind, "")
  }

  function test_export_and_contact_edits_run_offline_and_downloads_do_not() {
    var service = createService()
    service.offlineMode = true
    verify(service.exportChat(target, "/home/me/Documents/chat.txt", "app"), "an export is local")
    compare(service.activeWriteKind, "export-chat")
    compare(JSON.parse(findChild(service, "writeProcess").payload).destination, "/home/me/Documents/chat.txt")
    compare(JSON.parse(findChild(service, "writeProcess").payload).replace, true,
      "the save dialog already asked before replacing a file")
    findChild(service, "writeProcess").running = false
    service.writing = false
    verify(service.setContactTag(target, "1@s.whatsapp.net", "clients", false, "app"), "tags are local")
    compare(JSON.parse(findChild(service, "writeProcess").payload).person, "1@s.whatsapp.net")
    findChild(service, "writeProcess").running = false
    service.writing = false
    verify(!service.downloadPending(target, "app"), "downloads need WhatsApp")
    verify(!service.loadContactProfile(target, "1@s.whatsapp.net"))
    verify(service.contactProfile.error.indexOf("Offline") === 0)
    service.offlineMode = false
    verify(service.loadContactProfile(target, "1@s.whatsapp.net"))
    var profile = JSON.parse(findChild(service, "contactProfileProcess").payload)
    compare(profile.authorization, "remote-read")
  }
}
