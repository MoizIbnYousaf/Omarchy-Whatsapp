import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// The service half of a new chat: a number check never runs offline or for a
// malformed number, and the first message only targets a phone-number JID.
TestCase {
  id: testCase
  name: "ServiceNewChat"

  Component { id: serviceComponent; Oma.Service {} }

  function createService() {
    var service = createTemporaryObject(serviceComponent, testCase)
    verify(service !== null)
    service.ready = true
    service.statusReady = true
    service.statusAccount = "work"
    service.offlineMode = false
    return service
  }

  function test_offline_mode_never_asks_whatsapp() {
    var service = createService()
    service.offlineMode = true
    verify(!service.checkNumber("+55 11 91234-5678"))
    var process = findChild(service, "checkNumberProcess")
    verify(!process.running)
    verify(service.numberCheck.error.indexOf("Offline mode") === 0)
  }

  function test_a_malformed_number_is_refused_before_the_helper() {
    var service = createService()
    verify(!service.checkNumber("12345"))
    verify(!findChild(service, "checkNumberProcess").running)
    verify(service.numberCheck.error.indexOf("country code") > 0)
  }

  function test_a_check_asks_the_helper_with_remote_read_authorization() {
    var service = createService()
    verify(service.checkNumber("+55 (11) 91234-5678"))
    var process = findChild(service, "checkNumberProcess")
    verify(process.running)
    var payload = JSON.parse(process.payload)
    compare(payload.account, "work")
    compare(payload.authorization, "remote-read")
    verify(service.numberCheckFor("5511912345678").loading)
    process.stdout.text = JSON.stringify({ ok: true, registered: true,
      jid: "551191234567@s.whatsapp.net", has_chat: false, name: "" })
    process.running = false
    process.exited(0)
    var check = service.numberCheckFor("+55 11 91234 5678")
    verify(check !== null)
    verify(check.registered)
    compare(check.jid, "551191234567@s.whatsapp.net")
    service.statusAccount = "personal"
    compare(service.numberCheckFor("5511912345678"), null,
      "a check belongs to the account that asked")
  }

  function test_a_failed_check_carries_the_helper_error() {
    var service = createService()
    service.checkNumber("+5511912345678")
    var process = findChild(service, "checkNumberProcess")
    process.stdout.text = JSON.stringify({ ok: false, error: "Synthetic check failure" })
    process.running = false
    process.exited(1)
    compare(service.numberCheckFor("5511912345678").error, "Synthetic check failure")
  }

  function test_first_message_targets_only_a_phone_number_jid() {
    var service = createService()
    verify(!service.startNewChat("team@g.us", "hi", "app"))
    verify(!service.startNewChat("abc@lid", "hi", "app"))
    verify(!service.startNewChat("5511912345678@s.whatsapp.net", "   ", "app"))
    compare(service.activeWriteKind, "")
    verify(service.startNewChat("5511912345678@s.whatsapp.net", " hi ", "app"))
    compare(service.activeWriteKind, "send-new")
    compare(service.activeWriteChatJid, "5511912345678@s.whatsapp.net")
    compare(service.activeWriteOwner, "app")
  }

  function test_first_message_accepts_the_lid_whatsapp_confirmed() {
    var service = createService()
    verify(service.startNewChat("123456789012345@lid", "hi", "app"))
    compare(service.activeWriteKind, "send-new")
  }

  function test_first_message_respects_offline_mode() {
    var service = createService()
    service.offlineMode = true
    verify(!service.startNewChat("5511912345678@s.whatsapp.net", "hi", "app"))
    compare(service.activeWriteKind, "")
  }

  function test_people_search_is_scoped_to_the_serving_account() {
    var service = createService()
    verify(service.searchPeople(" sam "))
    var process = findChild(service, "contactsProcess")
    compare(JSON.parse(process.payload).query, "sam")
    compare(JSON.parse(process.payload).account, "work")
    process.stdout.text = JSON.stringify({ ok: true, people: [{ jid: "x@s.whatsapp.net", name: "Sam" }] })
    process.running = false
    process.exited(0)
    compare(service.newChatPeople.length, 1)
  }
}
