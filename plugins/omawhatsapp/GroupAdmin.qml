import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Group control inside the details panel. Local data shows at once; the live
// settings (description, who may send, who may edit, invite link, requests)
// are read from WhatsApp only when asked, because that pauses sync a moment.
// Destructive actions take a second click to confirm.
Column {
  id: root
  objectName: "groupAdmin"

  property var service: null
  property string localRole: ""
  property color foreground: Color.foreground
  property color surface: Color.background
  property color accent: Color.accent
  property color muted: foreground
  property color urgent: "#e06c75"
  property string fontFamily: Style.font.family
  readonly property var settings: service && service.groupSettings ? service.groupSettings : ({})
  readonly property bool loaded: settings.ok === true
  readonly property string role: loaded && settings.my_role ? settings.my_role : localRole
  readonly property bool admin: role === "admin" || role === "superadmin"
  readonly property bool canEditInfo: admin || (loaded && !settings.locked)
  readonly property var result: service && service.lastGroupResult ? service.lastGroupResult : ({})
  readonly property string inviteLink: result.action === "invite-get" || result.action === "invite-revoke"
    ? String(result.link || "") : ""
  readonly property var requests: result.action === "requests" && Array.isArray(result.requests)
    ? result.requests : []
  property string armed: ""
  signal copyRequested(string text)

  function act(action, value) {
    if (!service) return false
    return service.groupAction(action, value, "app")
  }
  // A destructive action runs on the second click within four seconds.
  function confirmThen(key, action, value) {
    if (armed !== key) { armed = key; disarm.restart(); return false }
    armed = ""
    return act(action, value)
  }

  spacing: Style.space(10)
  width: parent ? parent.width : Style.space(300)

  Timer { id: disarm; interval: 4000; onTriggered: root.armed = "" }

  Text {
    textFormat: Text.PlainText
    text: "Manage group"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Button {
    objectName: "groupLoadSettings"
    visible: !root.loaded
    text: root.service && root.service.groupSettingsLoading ? "Reading settings…" : "Load group settings"
    enabled: !!root.service && !root.service.groupSettingsLoading
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    bordered: true
    onClicked: root.service.loadGroupSettings()
  }
  Text {
    textFormat: Text.PlainText
    visible: !root.loaded
    width: root.width
    wrapMode: Text.WordWrap
    text: root.service && root.service.groupSettingsError !== "" ? root.service.groupSettingsError
      : "Asks WhatsApp for the description and who may send or edit; sync pauses for a few seconds."
    color: root.service && root.service.groupSettingsError !== "" ? root.urgent : root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Column {
    visible: root.loaded
    width: root.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: "Name"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Row {
      width: parent.width
      spacing: Style.space(6)
      TextField {
        id: nameField
        objectName: "groupNameField"
        width: parent.width - saveName.width - Style.space(6)
        text: String(root.settings.name || "")
        enabled: root.canEditInfo
        foreground: root.foreground
        accent: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Button {
        id: saveName
        objectName: "groupSaveName"
        text: "Save"
        enabled: root.canEditInfo && nameField.text.trim() !== "" && nameField.text.trim() !== String(root.settings.name || "")
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        bordered: true
        onClicked: root.act("rename", nameField.text.trim())
      }
    }

    Text {
      textFormat: Text.PlainText
      text: "Description"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Rectangle {
      width: parent.width
      height: Style.space(72)
      radius: Style.cornerRadius
      color: Style.normalFillFor(root.foreground, root.accent)
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      ScrollView {
        anchors.fill: parent
        anchors.margins: Style.space(4)
        TextArea {
          id: descriptionField
          objectName: "groupDescriptionField"
          text: String(root.settings.description || "")
          enabled: root.canEditInfo
          wrapMode: TextEdit.Wrap
          color: root.foreground
          selectionColor: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          background: null
        }
      }
    }
    Button {
      objectName: "groupSaveDescription"
      text: "Save description"
      enabled: root.canEditInfo && descriptionField.text !== String(root.settings.description || "")
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      bordered: true
      onClicked: root.act("description", descriptionField.text)
    }

    Repeater {
      model: root.admin ? [
        { key: "announce", label: "Only admins send messages", value: root.settings.announce_only === true },
        { key: "locked", label: "Only admins edit group info", value: root.settings.locked === true }
      ] : []
      delegate: Item {
        required property var modelData
        width: parent.width
        height: Style.space(34)
        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.right: groupToggle.left
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.label
          color: root.foreground
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        ToggleSwitch {
          id: groupToggle
          objectName: "groupToggle-" + modelData.key
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: modelData.value
          foreground: root.foreground
          accent: root.accent
          onToggled: root.act(modelData.key, !modelData.value)
        }
      }
    }

    Row {
      visible: root.admin
      spacing: Style.space(6)
      Button {
        objectName: "groupInviteGet"
        text: root.inviteLink !== "" ? "Copy invite link" : "Get invite link"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        bordered: true
        onClicked: root.inviteLink !== "" ? root.copyRequested(root.inviteLink) : root.act("invite-get")
      }
      Button {
        objectName: "groupInviteRevoke"
        text: root.armed === "revoke" ? "Confirm reset" : "Reset link"
        foreground: root.armed === "revoke" ? root.urgent : root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        bordered: true
        onClicked: root.confirmThen("revoke", "invite-revoke")
      }
    }
    Text {
      textFormat: Text.PlainText
      objectName: "groupInviteLink"
      visible: root.inviteLink !== ""
      width: parent.width
      text: root.inviteLink
      color: root.accent
      elide: Text.ElideMiddle
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Button {
      objectName: "groupRequests"
      visible: root.admin
      text: "Pending join requests"
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      bordered: true
      onClicked: root.act("requests")
    }
    Repeater {
      model: root.requests
      delegate: Item {
        required property var modelData
        width: parent.width
        height: Style.space(34)
        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.right: requestButtons.left
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.phone ? "+" + modelData.phone : modelData.jid
          color: root.foreground
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Row {
          id: requestButtons
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)
          Button { text: "Approve"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; bordered: true
            onClicked: root.act("approve", modelData.jid) }
          Button { text: "Reject"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; bordered: true
            onClicked: root.act("reject", modelData.jid) }
        }
      }
    }
    Text {
      textFormat: Text.PlainText
      visible: root.admin && root.result.action === "requests" && root.requests.length === 0
      text: "No pending requests"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      visible: root.admin
      width: parent.width
      spacing: Style.space(6)
      TextField {
        id: addField
        objectName: "groupAddField"
        width: parent.width - addButton.width - Style.space(6)
        placeholderText: "Add by number, with country code"
        foreground: root.foreground
        accent: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Button {
        id: addButton
        objectName: "groupAdd"
        text: "Add"
        enabled: /[0-9]{7,}/.test(addField.text.replace(/[^0-9]/g, ""))
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        bordered: true
        onClicked: if (root.act("add", [addField.text.trim()])) addField.text = ""
      }
    }
    Text {
      textFormat: Text.PlainText
      visible: root.result.action === "add" && Array.isArray(root.result.failed) && root.result.failed.length > 0
      width: parent.width
      wrapMode: Text.WordWrap
      text: "WhatsApp did not add everyone: their privacy settings may require an invite link."
      color: root.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Button {
    objectName: "groupLeave"
    text: root.armed === "leave" ? "Confirm: leave this group" : "Leave group"
    foreground: root.urgent
    accent: root.urgent
    fontFamily: root.fontFamily
    bordered: true
    onClicked: root.confirmThen("leave", "leave")
  }
}
