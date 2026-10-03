import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma
import "../plugins/omawhatsapp/PresenceModel.js" as PresenceModel

// The owner asked for online, last seen and typing, as on the phone. wacli
// builds that follow presence keep presence.json in the store; the app reads
// it directly, and shows the account online only while it has focus.
TestCase {
  id: testCase
  name: "Presence"
  width: 600
  height: 400
  visible: true
  when: windowShown

  readonly property int now: 1790000000
  readonly property string alice: "15550000002@s.whatsapp.net"
  readonly property string bob: "15550000003@s.whatsapp.net"
  readonly property string group: "120363000000000001@g.us"

  function snapshot(fields) {
    return PresenceModel.parse(JSON.stringify(Object.assign({
      version: 1, updated_at: now, available: true, contacts: {}, typing: {}
    }, fields || {})))
  }

  function test_nothing_is_claimed_without_a_valid_snapshot() {
    compare(PresenceModel.parse(""), null)
    compare(PresenceModel.parse("{\"version\":2}"), null)
    compare(PresenceModel.line(null, alice, { now: now }).text, "")
  }

  function test_a_person_typing_online_or_last_seen() {
    var typing = {}
    typing[alice] = {}
    typing[alice][alice] = { at: now - 3 }
    var contacts = {}
    contacts[alice] = { online: true, updated_at: now }
    var value = snapshot({ typing: typing, contacts: contacts })
    compare(PresenceModel.line(value, alice, { now: now }).text, "typing…")
    verify(PresenceModel.line(value, alice, { now: now }).live)
    compare(PresenceModel.line(value, alice, { now: now + 30 }).text, "online",
      "typing fades after 25 seconds without an update")
    typing[alice][alice] = { at: now - 1, media: "audio" }
    compare(PresenceModel.line(snapshot({ typing: typing }), alice, { now: now }).text, "recording audio…")
    contacts[alice] = { online: false, last_seen: now - 60, updated_at: now }
    var seen = PresenceModel.line(snapshot({ contacts: contacts }), alice,
      { now: now, date: new Date(now * 1000), clock: "HH:mm" }).text
    verify(seen.indexOf("last seen today at ") === 0, seen)
    contacts[alice] = { online: false, updated_at: now }
    compare(PresenceModel.line(snapshot({ contacts: contacts }), alice, { now: now }).text, "",
      "a hidden last seen shows nothing")
    contacts[alice] = { online: true, updated_at: now }
    compare(PresenceModel.line(snapshot({ contacts: contacts, available: false }), alice, { now: now }).text, "",
      "while this device is not online, WhatsApp sends nothing current")
  }

  function test_a_group_names_who_is_typing() {
    var typing = {}
    typing[group] = {}
    typing[group][alice] = { at: now - 2 }
    var names = {}
    names[alice] = "Alice Silva"
    names[bob] = "Bob"
    var options = { now: now, group: true, names: names }
    compare(PresenceModel.line(snapshot({ typing: typing }), group, options).text, "Alice is typing…")
    typing[group][bob] = { at: now - 1 }
    compare(PresenceModel.line(snapshot({ typing: typing }), group, options).text, "Alice and Bob are typing…")
    typing[group]["15550000004@s.whatsapp.net"] = { at: now }
    compare(PresenceModel.line(snapshot({ typing: typing }), group, options).text, "3 people are typing…")
    verify(PresenceModel.isTyping(snapshot({ typing: typing }), group, now))
    verify(!PresenceModel.isTyping(snapshot({ typing: typing }), alice, now))
  }

  Component { id: serviceComponent; Oma.Service {} }

  function createService() {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.showOnline = true
    service.ready = true
    service.statusReady = true
    service.statusAccount = "work"
    service.offlineMode = false
    service.selectedChatAccount = "work"
    service.selectedChatKind = "dm"
    service.selectedChatJid = alice
    return service
  }

  function finish(process, payload) {
    process.stdout.text = JSON.stringify(payload)
    process.running = false
    process.exited(0)
  }

  function test_focus_shows_the_account_online_and_follows_the_open_person() {
    var service = createService()
    var process = findChild(service, "presenceProcess")
    compare(process.running, false, "nothing is sent without focus")
    service.setPresenceFocus("app", true)
    verify(service.presenceActive)
    verify(process.running)
    var first = JSON.parse(process.payload || "{}")
    compare(first.action, "available")
    compare(first.account, "work")
    compare(first.lease, 90)
    finish(process, { ok: true })
    compare(JSON.parse(process.payload).action, "subscribe")
    compare(JSON.parse(process.payload).jid, alice)
    finish(process, { ok: true, sent_now: true })
    service.setPresenceFocus("dropdown", true)
    service.setPresenceFocus("app", false)
    verify(service.presenceActive, "the dropdown still looks at it")
    service.setPresenceFocus("dropdown", false)
    compare(JSON.parse(process.payload).action, "unavailable")
    finish(process, { ok: true })
    service.showOnline = false
    service.setPresenceFocus("app", true)
    verify(!service.presenceActive, "the setting keeps the account offline")
  }

  function test_an_official_wacli_is_asked_once() {
    var service = createService()
    var process = findChild(service, "presenceProcess")
    service.setPresenceFocus("app", true)
    finish(process, { ok: false, supported: false })
    verify(!service.presenceSupported)
    verify(!service.presenceActive)
    service.selectedChatJid = bob
    verify(!process.running, "no more presence calls this session")
  }

  function test_the_snapshot_file_feeds_the_open_chat() {
    var service = createService()
    var typing = {}
    typing[alice] = {}
    typing[alice][alice] = { at: Math.floor(Date.now() / 1000) }
    service.applyPresence(service.storeForAccount("work"), JSON.stringify({
      version: 1, updated_at: now, available: true, contacts: {}, typing: typing }))
    verify(PresenceModel.isTyping(service.presenceSnapshotFor("work"), alice, service.presenceNow))
    service.applyPresence(service.storeForAccount("work"), "not json")
    compare(service.presenceSnapshotFor("work"), null, "a bad file clears what was shown")
  }
}
