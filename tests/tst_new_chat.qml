import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// New chat: a known person opens their chat, anyone else gets a first-message
// step, and a typed number is checked with WhatsApp before anything is sent.
TestCase {
  id: testCase
  name: "NewChat"
  width: 600
  height: 700
  visible: true
  when: windowShown

  readonly property var people: [
    { jid: "15550001111@s.whatsapp.net", name: "Synthetic known", phone: "15550001111", has_chat: true },
    { jid: "15550002222@s.whatsapp.net", name: "Synthetic new", phone: "15550002222", has_chat: false }
  ]

  Component {
    id: serviceComponent
    QtObject {
      property var newChatPeople: []
      property var numberCheck: null
      property string errorText: ""
      property var searches: []
      property var checks: []
      property var started: null
      property string lastStartedChatJid: ""
      property bool accept: true
      signal writeCompleted(string kind, var chatRef, var request, string owner)
      signal writeFailed(string message, var chatRef, var details, string owner)
      function searchPeople(query) { searches = searches.concat([query]); return true }
      function numberCheckFor(digits) {
        return numberCheck && numberCheck.phone === digits ? numberCheck : null
      }
      function checkNumber(phone) {
        checks = checks.concat([phone])
        numberCheck = { phone: String(phone).replace(/[^0-9]/g, ""), loading: true }
        return true
      }
      function startNewChat(jid, text, owner) {
        started = { jid: jid, text: text, owner: owner }
        return accept
      }
    }
  }

  Component {
    id: dialogComponent
    Oma.NewChatDialog { parent: testCase }
  }

  function createDialog() {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.newChatPeople = people
    var dialog = createTemporaryObject(dialogComponent, testCase, { service: service })
    verify(dialog !== null)
    dialog.open()
    tryCompare(dialog, "opened", true)
    return { dialog: dialog, service: service }
  }

  function test_opening_searches_every_known_person() {
    var h = createDialog()
    compare(h.service.searches[0], "")
    compare(h.dialog.step, "search")
    compare(h.dialog.people.length, 2)
  }

  function test_a_person_with_a_chat_just_opens_it() {
    var h = createDialog()
    var spy = createTemporaryObject(signalSpyComponent, testCase,
      { target: h.dialog, signalName: "openChatRequested" })
    verify(h.dialog.choose(people[0]))
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], people[0].jid)
    tryCompare(h.dialog, "opened", false)
    compare(h.service.started, null, "opening a chat sends nothing")
  }

  function test_a_person_without_a_chat_needs_a_first_message() {
    var h = createDialog()
    verify(h.dialog.choose(people[1]))
    compare(h.dialog.step, "compose")
    var send = findChild(h.dialog.contentItem, "newChatSend")
    verify(!send.enabled, "nothing to send yet")
    verify(!h.dialog.sendFirst())
    compare(h.service.started, null)
    findChild(h.dialog.contentItem, "newChatMessage").text = "  hello  "
    verify(send.enabled)
    var spy = createTemporaryObject(signalSpyComponent, testCase,
      { target: h.dialog, signalName: "chatStarted" })
    verify(h.dialog.sendFirst())
    compare(h.service.started.jid, people[1].jid)
    compare(h.service.started.text, "hello")
    compare(h.service.started.owner, "app")
    verify(h.dialog.sending)
    h.service.writeCompleted("send-new", { account: "work", jid: people[1].jid }, {}, "app")
    compare(spy.count, 1)
    tryCompare(h.dialog, "opened", false)
  }

  function test_the_started_chat_is_followed_where_wacli_filed_it() {
    var h = createDialog()
    h.dialog.choose({ jid: "123456789012345@lid", name: "", phone: "5511912345678", has_chat: false })
    findChild(h.dialog.contentItem, "newChatMessage").text = "hello"
    var spy = createTemporaryObject(signalSpyComponent, testCase,
      { target: h.dialog, signalName: "chatStarted" })
    verify(h.dialog.sendFirst())
    h.service.lastStartedChatJid = "5511912345678@s.whatsapp.net"
    h.service.writeCompleted("send-new", { account: "work", jid: "123456789012345@lid" }, {}, "app")
    compare(spy.signalArguments[0][0], "5511912345678@s.whatsapp.net")
  }

  function test_a_failed_first_message_stays_on_screen_with_the_reason() {
    var h = createDialog()
    h.dialog.choose(people[1])
    findChild(h.dialog.contentItem, "newChatMessage").text = "hello"
    verify(h.dialog.sendFirst())
    h.service.writeFailed("Synthetic failure", { jid: people[1].jid }, { kind: "send-new" }, "app")
    verify(!h.dialog.sending)
    compare(h.dialog.sendError, "Synthetic failure")
    verify(h.dialog.opened)
    compare(findChild(h.dialog.contentItem, "newChatNote").text, "Synthetic failure")
  }

  function test_a_typed_number_is_checked_before_anything_else() {
    var h = createDialog()
    h.dialog.typeQuery("+55 (11) 91234-5678")
    verify(h.dialog.numberQuery)
    compare(h.dialog.numberState, "idle")
    compare(h.dialog.numberText, "Check +55 (11) 91234-5678 on WhatsApp", "shown as typed")
    verify(h.dialog.acceptSearch())
    compare(h.service.checks[0], "+55 (11) 91234-5678")
    compare(h.dialog.numberState, "checking")
    h.service.numberCheck = { phone: "5511912345678", loading: false, responded: true,
      registered: true, jid: "551191234567@s.whatsapp.net", has_chat: false, name: "", error: "" }
    compare(h.dialog.step, "compose", "a registered number goes straight to the first message")
    compare(h.dialog.person.jid, "551191234567@s.whatsapp.net",
      "the recipient is WhatsApp's JID, not the typed digits")
  }

  function test_a_checked_number_with_a_chat_opens_that_chat() {
    var h = createDialog()
    var spy = createTemporaryObject(signalSpyComponent, testCase,
      { target: h.dialog, signalName: "openChatRequested" })
    h.dialog.typeQuery("+1 555 000 1111")
    h.dialog.acceptSearch()
    h.service.numberCheck = { phone: "15550001111", loading: false, responded: true,
      registered: true, jid: people[0].jid, has_chat: true, name: "Synthetic known", error: "" }
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], people[0].jid)
  }

  function test_a_number_that_is_not_on_whatsapp_goes_nowhere() {
    var h = createDialog()
    h.dialog.typeQuery("+5511900000000")
    h.service.numberCheck = { phone: "5511900000000", loading: false, responded: true,
      registered: false, jid: "", has_chat: false, name: "", error: "" }
    compare(h.dialog.numberState, "absent")
    compare(h.dialog.numberText, "+5511900000000 is not on WhatsApp")
    verify(!h.dialog.activateNumberRow())
    compare(h.dialog.step, "search")
    compare(h.service.checks.length, 0)
  }

  function test_short_or_lettered_text_is_a_name_search() {
    var h = createDialog()
    h.dialog.typeQuery("12345")
    verify(!h.dialog.numberQuery)
    h.dialog.typeQuery("Synthetic 1")
    verify(!h.dialog.numberQuery)
    verify(!findChild(h.dialog.contentItem, "newChatNumber").visible)
  }

  function test_back_returns_to_search_without_sending() {
    var h = createDialog()
    h.dialog.choose(people[1])
    h.dialog.back()
    compare(h.dialog.step, "search")
    compare(h.service.started, null)
  }

  Component { id: signalSpyComponent; SignalSpy {} }

  Component { id: groupSpyComponent; SignalSpy {} }

  function test_new_group_and_join_by_link_start_from_here() {
    var h = createDialog()
    h.dialog.open()
    tryCompare(h.dialog, "opened", true)
    var rows = findChild(h.dialog, "newChatGroupRows")
    verify(rows.visible, "shown before anything is typed")
    var spy = createTemporaryObject(groupSpyComponent, testCase,
      { target: h.dialog, signalName: "groupRequested" })
    var join = null
    for (var i = 0; i < rows.children.length; i++)
      if (rows.children[i].objectName === "newChatGroup-join") join = rows.children[i]
    verify(join !== null)
    tryVerify(function() { return rows.height >= join.height * 2 }, 1000,
      "the rows take their own room above the contacts")
    mouseClick(join)
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "join")
    tryCompare(h.dialog, "opened", false)
    h.dialog.open()
    tryCompare(h.dialog, "opened", true)
    h.dialog.typeQuery("Ana")
    verify(!findChild(h.dialog, "newChatGroupRows").visible, "a search hides them")
  }
}
