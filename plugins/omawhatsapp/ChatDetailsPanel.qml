import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "TimeFormat.js" as TimeFormat

// Chat details: what this computer's mirror knows about the open chat. Every
// row is local; nothing here asks WhatsApp, so opening it never pauses sync.
Rectangle {
  id: root
  objectName: "chatDetailsPanel"

  property var details: ({})
  property var chat: null
  property bool loading: false
  property bool showAvatars: true
  property color foreground: Color.foreground
  property color surface: Color.background
  property color accent: Color.accent
  property color muted: foreground
  property string fontFamily: Style.font.family
  property var service: null
  property color urgent: "#e06c75"
  readonly property string myRole: group && group.my_role ? String(group.my_role) : ""
  readonly property bool admin: myRole === "admin" || myRole === "superadmin"
  property var menuPerson: null
  property string menuArmed: ""
  signal copyRequested(string text)
  function participantActions(person) {
    if (!person) return []
    var actions = [{ key: "message", label: "Message" }]
    if (admin && person.me !== true && person.role !== "superadmin") {
      actions.push(person.role === "admin"
        ? { key: "demote", label: "Dismiss as admin" }
        : { key: "promote", label: "Make group admin" })
      actions.push({ key: "remove", label: menuArmed === "remove" ? "Confirm: remove from group" : "Remove from group",
        destructive: true })
    }
    return actions
  }
  function runParticipantAction(key) {
    var person = menuPerson
    if (!person) return false
    if (key === "message") {
      participantMenu.close()
      openChatRequested(String(person.jid || ""), String(person.name || ""), String(person.phone || ""))
      return true
    }
    if (key === "remove" && menuArmed !== "remove") { menuArmed = "remove"; return false }
    participantMenu.close()
    menuArmed = ""
    return !!service && service.groupAction(key, String(person.jid || ""), "app")
  }
  readonly property bool isGroup: String(details && details.chat ? details.chat.kind : (chat ? chat.kind : "")) === "group"
  readonly property var person: details && details.person ? details.person : null
  readonly property var group: details && details.group ? details.group : null
  readonly property var counts: details && details.counts ? details.counts : ({})
  readonly property string title: String(chat && chat.name || details && details.chat && details.chat.name || "WhatsApp chat")
  readonly property string subtitle: {
    if (isGroup) {
      var n = group ? Number(group.participant_count || 0) : 0
      return n > 0 ? "Group · " + n + (n === 1 ? " participant" : " participants") : "Group"
    }
    var phone = person ? String(person.phone || "") : ""
    return /^[0-9]{6,}$/.test(phone) ? "+" + phone : ""
  }
  readonly property string alsoKnownAs: {
    if (!person) return ""
    var names = []
    function add(value, prefix) {
      var text = String(value || "").trim()
      if (text !== "" && text !== root.title && names.indexOf(prefix + text) < 0) names.push(prefix + text)
    }
    add(person.alias, "Saved as ")
    add(person.business_name, "")
    add(person.full_name, "")
    add(person.push_name, "~")
    return names.join(" · ")
  }
  readonly property var actions: {
    var c = chat || ({})
    return [
      { key: "mute", icon: c.muted ? "󰂜" : "󰪑", label: c.muted ? "Unmute" : "Mute",
        action: c.muted ? "unmute" : "mute" },
      { key: "pin", icon: c.pinned ? "󰤰" : "󰤱", label: c.pinned ? "Unpin" : "Pin",
        action: c.pinned ? "unpin" : "pin" },
      { key: "unread", icon: "󱥂", label: "Unread", action: "unread" },
      { key: "search", icon: "󰍉", label: "Search", action: "search" },
      { key: "export", icon: "󰈇", label: "Export", action: "export" }
    ]
  }
  signal closeRequested()
  signal actionRequested(string action)
  readonly property var personRef: ({ account: String(details && details.account || ""),
    jid: String(chat && chat.jid || "") })
  readonly property var personTags: {
    var tags = person && person.tags ? person.tags : []
    var list = []
    for (var i = 0; i < Number(tags.length || 0); i++) list.push(String(tags[i]))
    return list
  }
  readonly property var profile: service && service.contactProfile
    && service.contactProfile.jid === personRef.jid ? service.contactProfile : null
  readonly property var businessLines: {
    var business = profile && profile.business ? profile.business : ({})
    var labels = { description: "About the business", category: "Category", address: "Address",
      email: "Email", website: "Website", business_hours: "Hours", hours: "Hours" }
    var lines = []
    for (var key in business) {
      var value = business[key]
      var text = typeof value === "string" ? value
        : (value && value.length !== undefined ? Array.prototype.join.call(value, ", ") : JSON.stringify(value))
      if (String(text || "").trim() !== "")
        lines.push({ label: labels[key] || key.replace(/_/g, " "), text: String(text) })
    }
    return lines
  }
  function saveAlias(text) {
    if (!service || !person) return false
    return service.setContactAlias(personRef, personRef.jid, String(text || "").trim(), "app")
  }
  function changeTag(tag, remove) {
    var value = String(tag || "").trim()
    if (!service || !person || value === "") return false
    return service.setContactTag(personRef, personRef.jid, value, remove === true, "app")
  }
  signal filterRequested(string filter)
  signal openChatRequested(string jid, string name, string phone)

  function dateText(ts) {
    var value = Number(ts || 0)
    if (value <= 0) return ""
    return Qt.formatDate(new Date(value * 1000), "d MMM yyyy")
  }
  function countText(value) {
    return Number(value || 0).toLocaleString(Qt.locale(), "f", 0)
  }
  function roleLabel(role) {
    if (role === "superadmin") return "Owner"
    if (role === "admin") return "Admin"
    return ""
  }

  color: surface

  // Owns every click, hover and wheel inside the panel: without it, a right
  // click on a participant reached the message bubble underneath and opened
  // that message's menu.
  MouseArea {
    objectName: "panelPointerGuard"
    anchors.fill: parent
    z: -1
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    onWheel: function(wheel) { wheel.accepted = true }
  }
  Rectangle {
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    width: 1
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
  }

  Item {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(54)
    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(18)
      anchors.verticalCenter: parent.verticalCenter
      text: root.isGroup ? "Group info" : "Contact info"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    PanelActionButton {
      objectName: "chatDetailsClose"
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅖"
      tooltipText: "Close · Esc"
      foreground: root.muted
      hoverColor: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.body
      size: Style.space(30)
      onClicked: root.closeRequested()
    }
  }

  Popup {
    id: participantMenu
    objectName: "participantMenu"
    x: parent ? parent.width - width - Style.space(8) : 0
    y: parent ? parent.height : 0
    width: Style.space(230)
    padding: Style.space(5)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: root.menuArmed = ""
    background: Rectangle {
      radius: Style.cornerRadius
      color: root.surface
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
    }
    contentItem: Column {
      spacing: Style.space(2)
      Repeater {
        model: root.participantActions(root.menuPerson)
        delegate: Rectangle {
          required property var modelData
          objectName: "participantAction-" + modelData.key
          width: Style.space(220)
          height: Style.space(32)
          radius: Style.cornerRadius
          color: participantActionHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            color: modelData.destructive ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          HoverHandler { id: participantActionHover }
          TapHandler { onTapped: root.runParticipantAction(modelData.key) }
        }
      }
    }
  }

  Flickable {
    id: scroller
    anchors.top: header.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    contentWidth: width
    contentHeight: body.implicitHeight + Style.space(24)
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: body
      x: Style.space(18)
      width: scroller.width - Style.space(36)
      spacing: Style.space(14)

      Item { width: 1; height: Style.space(4) }

      ChatAvatar {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.space(96)
        height: width
        showPhoto: root.showAvatars
        chat: ({ name: root.title, kind: root.isGroup ? "group" : "dm",
          avatar_path: String(root.chat && root.chat.avatar_path || root.details.avatar_path || "") })
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        fontFamily: root.fontFamily
      }

      Column {
        width: parent.width
        spacing: Style.space(3)
        Text {
          textFormat: Text.PlainText
          objectName: "chatDetailsTitle"
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.title
          color: root.foreground
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
        }
        Text {
          textFormat: Text.PlainText
          objectName: "chatDetailsSubtitle"
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: text !== ""
          text: root.subtitle
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: text !== ""
          text: root.alsoKnownAs
          color: root.muted
          wrapMode: Text.Wrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(8)
        Repeater {
          model: root.actions
          delegate: Rectangle {
            required property var modelData
            objectName: "chatDetailsAction-" + modelData.key
            width: Style.space(64)
            height: Style.space(56)
            radius: Style.cornerRadius
            color: actionHover.hovered ? Style.hoverFillFor(root.foreground, root.accent)
              : Style.normalFillFor(root.foreground, root.accent)
            Column {
              anchors.centerIn: parent
              spacing: Style.space(3)
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.icon
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.actionRequested(modelData.action) }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) }

      Text {
        textFormat: Text.PlainText
        text: "Media, links and docs"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Row {
        width: parent.width
        spacing: Style.space(8)
        Repeater {
          model: [
            { key: "media", icon: "󰋩", label: "Media", count: root.counts.media, filter: "media" },
            { key: "links", icon: "󰌷", label: "Links", count: root.counts.links, filter: "links" },
            { key: "documents", icon: "󰈙", label: "Docs", count: root.counts.documents, filter: "docs" }
          ]
          delegate: Rectangle {
            required property var modelData
            objectName: "chatDetailsCount-" + modelData.key
            width: (body.width - Style.space(16)) / 3
            height: Style.space(52)
            radius: Style.cornerRadius
            color: countHover.hovered && modelData.filter !== ""
              ? Style.hoverFillFor(root.foreground, root.accent)
              : Style.normalFillFor(root.foreground, root.accent)
            Column {
              anchors.centerIn: parent
              spacing: Style.space(2)
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.icon + "  " + root.countText(modelData.count)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.label
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            HoverHandler {
              id: countHover
              cursorShape: modelData.filter !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
            TapHandler { onTapped: if (modelData.filter !== "") root.filterRequested(modelData.filter) }
            PanelToolTip {
              visible: countHover.hovered
              text: "Open " + modelData.label.toLowerCase() + " of this chat"
            }
          }
        }
      }

      Row {
        spacing: Style.space(8)
        visible: Number(root.counts.starred || 0) > 0
        Text { textFormat: Text.PlainText; text: "󰓎"; color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.body }
        Text {
          textFormat: Text.PlainText
          objectName: "chatDetailsStarred"
          text: root.countText(root.counts.starred) + (Number(root.counts.starred) === 1 ? " starred message" : " starred messages")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Row {
        objectName: "chatDetailsMissing"
        spacing: Style.space(8)
        visible: Number(root.counts.missing || 0) > 0
        Text { textFormat: Text.PlainText; text: "󰇚"; color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.body }
        Text {
          textFormat: Text.PlainText
          text: "Download " + root.countText(root.counts.missing)
            + (Number(root.counts.missing) === 1 ? " missing attachment" : " missing attachments")
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          HoverHandler { cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.actionRequested("download-missing") }
        }
      }

      Column {
        objectName: "chatDetailsContact"
        visible: !root.isGroup && root.person !== null
        width: parent.width
        spacing: Style.space(8)
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) }
        Text {
          textFormat: Text.PlainText
          text: "Your name for them"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Row {
          width: parent.width
          spacing: Style.space(6)
          TextField {
            id: aliasField
            objectName: "chatDetailsAlias"
            width: parent.width - aliasSave.width - Style.space(6)
            text: root.person ? String(root.person.alias || "") : ""
            placeholderText: "An alias only this computer shows"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            Keys.onReturnPressed: root.saveAlias(text)
            Keys.onEnterPressed: root.saveAlias(text)
          }
          PanelActionButton {
            id: aliasSave
            objectName: "chatDetailsAliasSave"
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰄬"
            tooltipText: "Save the alias"
            foreground: root.accent
            hoverColor: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            size: Style.space(30)
            onClicked: root.saveAlias(aliasField.text)
          }
        }
        Text {
          textFormat: Text.PlainText
          text: "Tags"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Flow {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: root.personTags
            delegate: Rectangle {
              required property string modelData
              objectName: "chatDetailsTag"
              width: tagText.implicitWidth + Style.space(30)
              height: Style.space(26)
              radius: height / 2
              color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)
              Text {
                textFormat: Text.PlainText
                id: tagText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: "󰅖"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.changeTag(modelData, true) }
              }
            }
          }
          TextField {
            id: tagField
            objectName: "chatDetailsNewTag"
            width: Style.space(140)
            placeholderText: "Add a tag"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            Keys.onReturnPressed: if (root.changeTag(text, false)) text = ""
            Keys.onEnterPressed: if (root.changeTag(text, false)) text = ""
          }
        }
        Text {
          textFormat: Text.PlainText
          objectName: "chatDetailsProfileButton"
          visible: root.profile === null || (!root.profile.loading && root.profile.error !== "")
          text: "󰋽  Show their about and business profile"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          HoverHandler { cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: if (root.service) root.service.loadContactProfile(root.personRef, root.personRef.jid) }
        }
        Text {
          textFormat: Text.PlainText
          objectName: "chatDetailsProfile"
          visible: root.profile !== null
          width: parent.width
          wrapMode: Text.Wrap
          text: !root.profile ? "" : root.profile.loading ? "Asking WhatsApp…"
            : root.profile.error !== "" ? root.profile.error
            : (root.profile.about !== "" ? "About: " + root.profile.about : "No about text.")
              + root.businessLines.map(function(line) { return "\n" + line.label + ": " + line.text }).join("")
          color: root.profile && root.profile.error !== "" ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) }

      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        text: root.isGroup
          ? (root.group && Number(root.group.participant_count || 0) > 0
            ? root.countText(root.group.participant_count) + " participants" : "")
          : ((root.details.groups_in_common || []).length > 0
            ? (root.details.groups_in_common.length === 1 ? "1 group in common"
              : root.details.groups_in_common.length + " groups in common") : "")
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        objectName: "chatDetailsPeople"
        model: root.isGroup ? (root.details.participants || []) : (root.details.groups_in_common || [])
        delegate: Rectangle {
          required property var modelData
          width: body.width
          height: Style.space(44)
          radius: Style.cornerRadius
          color: personHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
          ChatAvatar {
            id: rowAvatar
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(32)
            height: width
            showPhoto: false
            chat: ({ name: String(modelData.name || ""), kind: root.isGroup ? "dm" : "group", avatar_path: "" })
            foreground: root.foreground
            background: root.surface
            accent: root.accent
            fontFamily: root.fontFamily
          }
          Column {
            anchors.left: rowAvatar.right
            anchors.leftMargin: Style.space(10)
            anchors.right: roleText.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: String(modelData.name || "")
              color: root.foreground
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.isGroup && /^[0-9]{6,}$/.test(String(modelData.phone || ""))
                && String(modelData.name || "") !== String(modelData.phone || "")
              text: "+" + String(modelData.phone || "")
              color: root.muted
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Text {
            textFormat: Text.PlainText
            id: roleText
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.isGroup ? root.roleLabel(String(modelData.role || "")) : ""
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          HoverHandler { id: personHover; cursorShape: Qt.PointingHandCursor }
          TapHandler {
            onTapped: root.openChatRequested(String(modelData.jid || ""), String(modelData.name || ""),
              String(modelData.phone || ""))
          }
          TapHandler {
            acceptedButtons: Qt.RightButton
            enabled: root.isGroup
            onTapped: {
              root.menuPerson = modelData
              root.menuArmed = ""
              participantMenu.parent = parent
              participantMenu.open()
            }
          }
          PanelActionButton {
            objectName: "participantMenuButton"
            visible: root.isGroup && personHover.hovered && modelData.me !== true
            anchors.right: roleText.left
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰇙"
            tooltipText: "Participant actions"
            foreground: root.muted
            hoverColor: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            size: Style.space(26)
            onClicked: {
              root.menuPerson = modelData
              root.menuArmed = ""
              participantMenu.parent = parent
              participantMenu.open()
            }
          }
        }
      }

      Rectangle {
        visible: groupAdmin.visible
        width: parent.width; height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
      }

      GroupAdmin {
        id: groupAdmin
        visible: root.isGroup && !(root.group && root.group.left)
        width: body.width
        service: root.service
        localRole: root.myRole
        foreground: root.foreground
        surface: root.surface
        accent: root.accent
        muted: root.muted
        urgent: root.urgent
        fontFamily: root.fontFamily
        onCopyRequested: function(text) { root.copyRequested(text) }
      }

      Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) }

      Text {
        textFormat: Text.PlainText
        objectName: "chatDetailsHistory"
        width: parent.width
        wrapMode: Text.Wrap
        text: {
          var parts = []
          if (root.isGroup && root.group && Number(root.group.created_ts || 0) > 0)
            parts.push("Created " + root.dateText(root.group.created_ts)
              + (String(root.group.owner_name || "") !== "" ? " by " + root.group.owner_name : ""))
          if (Number(root.details.since || 0) > 0)
            parts.push("On this computer since " + root.dateText(root.details.since)
              + " · " + root.countText(root.counts.total) + " messages")
          if (root.group && root.group.left) parts.push("You are no longer in this group")
          return root.loading && parts.length === 0 ? "Reading local history…" : parts.join("\n")
        }
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
