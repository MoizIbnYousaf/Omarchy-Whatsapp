import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// Full group control from the details panel: live settings on request, admin
// actions only for admins, and destructive ones on a second click.
TestCase {
  id: testCase
  name: "GroupAdmin"
  width: 420
  height: 900
  visible: true
  when: windowShown

  Component {
    id: serviceComponent
    QtObject {
      property var groupSettings: ({})
      property bool groupSettingsLoading: false
      property string groupSettingsError: ""
      property var lastGroupResult: ({})
      property var calls: []
      property int loads: 0
      function loadGroupSettings() { loads += 1; return true }
      function groupAction(action, value, owner) { calls = calls.concat([{ action: action, value: value }]); return true }
    }
  }
  Component { id: adminComponent; Oma.GroupAdmin { width: 400 } }
  Component { id: panelComponent; Oma.ChatDetailsPanel { width: 380; height: 900 } }

  function createAdmin(settings, localRole) {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.groupSettings = settings || ({})
    var admin = createTemporaryObject(adminComponent, testCase, { service: service, localRole: localRole || "" })
    return { service: service, admin: admin }
  }

  function test_settings_load_only_when_asked() {
    var h = createAdmin({}, "member")
    verify(!h.admin.loaded)
    verify(findChild(h.admin, "groupLoadSettings").visible)
    compare(h.service.loads, 0, "opening the details never asks WhatsApp")
    findChild(h.admin, "groupLoadSettings").clicked()
    compare(h.service.loads, 1)
  }

  function test_a_member_of_a_locked_group_cannot_edit_or_toggle() {
    var h = createAdmin({ ok: true, name: "Team", description: "", announce_only: false, locked: true, my_role: "member" })
    verify(!h.admin.admin)
    verify(!findChild(h.admin, "groupNameField").enabled)
    verify(findChild(h.admin, "groupToggle-announce") === null, "no admin switches for members")
    verify(!findChild(h.admin, "groupInviteGet").visible)
    verify(findChild(h.admin, "groupLeave").visible, "anyone can leave")
  }

  function test_an_admin_toggles_renames_and_invites() {
    var h = createAdmin({ ok: true, name: "Team", description: "Old", announce_only: false, locked: false, my_role: "admin" })
    verify(h.admin.admin)
    var toggle = findChild(h.admin, "groupToggle-announce")
    verify(toggle !== null)
    toggle.toggled()
    compare(h.service.calls[0], { action: "announce", value: true })
    findChild(h.admin, "groupNameField").text = "New team"
    findChild(h.admin, "groupSaveName").clicked()
    compare(h.service.calls[1], { action: "rename", value: "New team" })
    findChild(h.admin, "groupInviteGet").clicked()
    compare(h.service.calls[2].action, "invite-get")
    h.service.lastGroupResult = { action: "invite-get", link: "https://chat.whatsapp.com/Synthetic" }
    compare(findChild(h.admin, "groupInviteLink").text, "https://chat.whatsapp.com/Synthetic")
    var copied = createTemporaryObject(spyComponent, testCase, { target: h.admin, signalName: "copyRequested" })
    findChild(h.admin, "groupInviteGet").clicked()
    compare(copied.signalArguments[0][0], "https://chat.whatsapp.com/Synthetic")
  }

  function test_leaving_and_resetting_the_link_need_a_second_click() {
    var h = createAdmin({ ok: true, name: "Team", my_role: "superadmin" })
    var leave = findChild(h.admin, "groupLeave")
    leave.clicked()
    compare(h.service.calls.length, 0, "the first click only arms it")
    compare(leave.text, "Confirm: leave this group")
    leave.clicked()
    compare(h.service.calls[0].action, "leave")
    var reset = findChild(h.admin, "groupInviteRevoke")
    reset.clicked()
    compare(h.service.calls.length, 1)
    reset.clicked()
    compare(h.service.calls[1].action, "invite-revoke")
  }

  function test_participant_actions_follow_your_role() {
    var service = createTemporaryObject(serviceComponent, testCase)
    var panel = createTemporaryObject(panelComponent, testCase, { service: service,
      chat: { name: "Team", kind: "group" },
      details: { ok: true, chat: { kind: "group", name: "Team" }, counts: {},
        group: { participant_count: 3, my_role: "admin", left: false },
        participants: [
          { jid: "me@s.whatsapp.net", name: "Me", role: "admin", me: true },
          { jid: "a@s.whatsapp.net", name: "Member", role: "member", me: false },
          { jid: "o@s.whatsapp.net", name: "Owner", role: "superadmin", me: false }] } })
    var keys = function(person) { return panel.participantActions(person).map(function(a) { return a.key }) }
    compare(keys(panel.details.participants[1]), ["message", "promote", "remove"])
    compare(keys(panel.details.participants[0]), ["message"], "nothing to do on yourself")
    compare(keys(panel.details.participants[2]), ["message"], "the group owner cannot be demoted or removed")
    panel.menuPerson = panel.details.participants[1]
    verify(!panel.runParticipantAction("remove"), "the first click arms the removal")
    compare(service.calls.length, 0)
    verify(panel.runParticipantAction("remove"))
    compare(service.calls[0], { action: "remove", value: "a@s.whatsapp.net" })
    panel.details = Object.assign({}, panel.details, { group: { participant_count: 3, my_role: "member" } })
    compare(keys(panel.details.participants[1]), ["message"], "members only get Message")
  }

  Component { id: spyComponent; SignalSpy {} }
}
