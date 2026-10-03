import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// Chat details: everything shown is local, the actions reuse the chat's own
// actions, and a panel that covers the conversation does not count as reading it.
TestCase {
  id: testCase
  name: "ChatDetails"
  width: 1000
  height: 700
  visible: true
  when: windowShown

  readonly property var groupDetails: ({
    ok: true, chat: { kind: "group", name: "Synthetic group" }, since: 1780000000,
    counts: { total: 1284, media: 42, documents: 7, links: 19, starred: 1 },
    group: { created_ts: 1760000000, owner_name: "Synthetic owner", participant_count: 2, left: false },
    participants: [
      { jid: "1@s.whatsapp.net", name: "Synthetic owner", phone: "15550000001", role: "superadmin" },
      { jid: "2@s.whatsapp.net", name: "Synthetic member", phone: "15550000002", role: "member" }
    ]
  })

  Component {
    id: panelComponent
    Oma.ChatDetailsPanel { width: 340; height: 700 }
  }

  function test_a_group_shows_its_participants_counts_and_history() {
    var panel = createTemporaryObject(panelComponent, testCase, {
      details: groupDetails, chat: { name: "Synthetic group", kind: "group", muted: false, pinned: true } })
    compare(findChild(panel, "chatDetailsTitle").text, "Synthetic group")
    compare(findChild(panel, "chatDetailsSubtitle").text, "Group · 2 participants")
    verify(findChild(panel, "chatDetailsHistory").text.indexOf("by Synthetic owner") > 0)
    verify(findChild(panel, "chatDetailsHistory").text.indexOf("messages") > 0)
    compare(findChild(panel, "chatDetailsStarred").text, "1 starred message")
    compare(panel.roleLabel("superadmin"), "Owner")
    compare(panel.actions[1].label, "Unpin", "the pin button follows the chat")
  }

  function test_a_person_shows_the_phone_and_other_names() {
    var panel = createTemporaryObject(panelComponent, testCase, {
      details: { ok: true, chat: { kind: "dm", name: "Synthetic person" }, counts: {},
        person: { phone: "15550000003", alias: "Sy", full_name: "Synthetic Person Full", push_name: "syn", business_name: "" },
        groups_in_common: [{ jid: "g@g.us", name: "Synthetic group" }] },
      chat: { name: "Synthetic person", kind: "dm", muted: true } })
    compare(findChild(panel, "chatDetailsSubtitle").text, "+15550000003")
    compare(panel.alsoKnownAs, "Saved as Sy · Synthetic Person Full · ~syn")
    compare(panel.actions[0].label, "Unmute")
  }

  function test_actions_and_filters_are_signals_for_the_app() {
    var panel = createTemporaryObject(panelComponent, testCase, {
      details: groupDetails, chat: { name: "Synthetic group", kind: "group" } })
    var actions = createTemporaryObject(spyComponent, testCase, { target: panel, signalName: "actionRequested" })
    var filters = createTemporaryObject(spyComponent, testCase, { target: panel, signalName: "filterRequested" })
    var links = findChild(panel, "chatDetailsCount-links")
    tryVerify(function() { return links.x > 0 }, 2000, "the row has laid out")
    var mute = findChild(panel, "chatDetailsAction-mute")
    mouseClick(mute, mute.width / 2, mute.height / 2)
    compare(actions.signalArguments[0][0], "mute")
    var media = findChild(panel, "chatDetailsCount-media")
    mouseClick(media, media.width / 2, media.height / 2)
    compare(filters.signalArguments[0][0], "media")
    var docs = findChild(panel, "chatDetailsCount-documents")
    mouseClick(docs, docs.width / 2, docs.height / 2)
    compare(filters.signalArguments[1][0], "docs", "documents open in the media browser too")
  }

  Component { id: spyComponent; SignalSpy {} }

  Component {
    id: detailsServiceStub
    Item {
      property var calls: []
      property var contactProfile: ({ jid: "", loading: false, about: "", business: ({}), error: "" })
      function setContactAlias(ref, person, alias, owner) { calls = calls.concat([["alias", person, alias]]); return true }
      function setContactTag(ref, person, tag, remove, owner) { calls = calls.concat([["tag", person, tag, remove]]); return true }
      function loadContactProfile(ref, person) { calls = calls.concat([["profile", person]]); return true }
    }
  }

  function personPanel(service) {
    return createTemporaryObject(panelComponent, testCase, {
      service: service,
      details: { ok: true, account: "work", chat: { kind: "dm", name: "Ana" },
        counts: { total: 9, media: 3, missing: 2 },
        person: { phone: "15550000003", alias: "", full_name: "Ana", push_name: "", business_name: "",
                  tags: ["suppliers"] }, groups_in_common: [] },
      chat: { jid: "15550000003@s.whatsapp.net", name: "Ana", kind: "dm" } })
  }

  function test_export_and_missing_attachments_are_actions() {
    var panel = personPanel(null)
    compare(panel.actions[panel.actions.length - 1].action, "export")
    var missing = findChild(panel, "chatDetailsMissing")
    verify(missing.visible)
    var actions = createTemporaryObject(spyComponent, testCase, { target: panel, signalName: "actionRequested" })
    var label = missing.children[1]
    mouseClick(label)
    compare(actions.signalArguments[0][0], "download-missing")
  }

  function test_a_person_gets_an_alias_tags_and_a_business_profile() {
    var service = createTemporaryObject(detailsServiceStub, testCase)
    var panel = personPanel(service)
    verify(findChild(panel, "chatDetailsContact").visible)
    verify(panel.saveAlias("  Ana from the shop "))
    compare(service.calls[0], ["alias", "15550000003@s.whatsapp.net", "Ana from the shop"])
    verify(panel.changeTag("clients", false))
    verify(panel.changeTag("suppliers", true))
    compare(service.calls[1], ["tag", "15550000003@s.whatsapp.net", "clients", false])
    compare(service.calls[2], ["tag", "15550000003@s.whatsapp.net", "suppliers", true])
    compare(panel.personTags, ["suppliers"])
    service.contactProfile = { jid: "15550000003@s.whatsapp.net", loading: false, about: "Open 8-18",
      business: { address: "Main street, 1", website: ["https://shop.example"] }, error: "" }
    var shown = findChild(panel, "chatDetailsProfile").text
    verify(shown.indexOf("About: Open 8-18") === 0)
    verify(shown.indexOf("Address: Main street, 1") > 0)
    verify(shown.indexOf("Website: https://shop.example") > 0)
  }

  function test_a_group_has_no_contact_section() {
    var panel = createTemporaryObject(panelComponent, testCase, {
      details: groupDetails, chat: { name: "Synthetic group", kind: "group" } })
    verify(!findChild(panel, "chatDetailsContact").visible)
    verify(!findChild(panel, "chatDetailsMissing").visible)
  }
}
