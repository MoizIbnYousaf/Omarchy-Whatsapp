import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// New group and joining by link, from the new chat screen as on the phone.
TestCase {
  id: testCase
  name: "GroupDialog"
  width: 700
  height: 800
  visible: true
  when: windowShown

  Component { id: spyComponent; SignalSpy {} }
  Component {
    id: serviceStub
    Item {
      property var newChatPeople: [
        { jid: "1@s.whatsapp.net", name: "Ana", phone: "15550000001", has_chat: true },
        { jid: "2@s.whatsapp.net", name: "Bruno", phone: "15550000002", has_chat: false }]
      property var groupRequest: ({ kind: "", loading: false, jid: "", error: "" })
      property var created: []
      property var joined: []
      function searchPeople(query) { return true }
      function createGroup(name, people) {
        created = created.concat([{ name: name, people: people }])
        groupRequest = { kind: "create-group", loading: true, jid: "", error: "" }
        return true
      }
      function joinGroup(invite) {
        joined = joined.concat([invite])
        groupRequest = { kind: "join-group", loading: true, jid: "", error: "" }
        return true
      }
    }
  }
  Component { id: dialogComponent; Oma.GroupDialog {} }

  function createDialog() {
    var service = createTemporaryObject(serviceStub, testCase)
    var dialog = createTemporaryObject(dialogComponent, testCase, { service: service })
    return { dialog: dialog, service: service }
  }

  function test_a_group_is_created_with_the_people_picked_and_its_name() {
    var h = createDialog()
    h.dialog.openFor("create")
    tryCompare(h.dialog, "opened", true)
    verify(!findChild(h.dialog, "groupNext").enabled, "nobody chosen yet")
    verify(h.dialog.toggle(h.service.newChatPeople[0]))
    verify(h.dialog.toggle(h.service.newChatPeople[1]))
    verify(h.dialog.toggle(h.service.newChatPeople[1]), "a second tap drops the person")
    compare(h.dialog.chosen.length, 1)
    verify(h.dialog.next())
    compare(h.dialog.step, "name")
    findChild(h.dialog, "groupName").text = "  Obra   Sorriso "
    verify(h.dialog.create())
    compare(h.service.created[0].name, "Obra Sorriso")
    compare(h.service.created[0].people, ["1@s.whatsapp.net"])
    verify(h.dialog.waiting)
    var ready = createTemporaryObject(spyComponent, testCase, { target: h.dialog, signalName: "groupReady" })
    h.service.groupRequest = { kind: "create-group", loading: false, jid: "new@g.us", error: "" }
    compare(ready.count, 1)
    compare(ready.signalArguments[0][0], "new@g.us")
    tryCompare(h.dialog, "opened", false)
  }

  function test_a_refusal_stays_on_screen() {
    var h = createDialog()
    h.dialog.openFor("create")
    h.dialog.toggle(h.service.newChatPeople[0])
    h.dialog.next()
    findChild(h.dialog, "groupName").text = "Obra"
    h.dialog.create()
    h.service.groupRequest = { kind: "create-group", loading: false, jid: "",
      error: "Offline mode is on. Go online to change WhatsApp." }
    verify(h.dialog.opened)
    compare(findChild(h.dialog, "groupNote").text, "Offline mode is on. Go online to change WhatsApp.")
  }

  function test_joining_takes_only_a_group_invite_link() {
    var h = createDialog()
    h.dialog.openFor("join")
    var field = findChild(h.dialog, "groupInvite")
    field.text = "https://evil.example/whatever"
    verify(!findChild(h.dialog, "groupJoin").enabled)
    verify(!h.dialog.join())
    field.text = "https://chat.whatsapp.com/AbCdEfGhIjKlMnOpQr12"
    verify(findChild(h.dialog, "groupJoin").enabled)
    verify(h.dialog.join())
    compare(h.service.joined, ["https://chat.whatsapp.com/AbCdEfGhIjKlMnOpQr12"])
  }
}
