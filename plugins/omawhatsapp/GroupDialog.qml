import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// New group and joining one by link, as on the phone's new chat screen.
// Creating picks people this account knows and then names the group; nothing
// reaches WhatsApp until the owner presses Create or Join.
Popup {
  id: root
  objectName: "groupDialog"

  property var service: null
  property bool demoMode: false
  property var demoPeople: []
  property color foreground: Color.foreground
  property color surface: Color.background
  property color accent: Color.accent
  property color muted: foreground
  property string fontFamily: Style.font.family
  property bool showAvatars: true
  property var chats: []

  // "create" (step "pick", then "name") or "join".
  property string mode: "create"
  property string step: "pick"
  property string query: ""
  property var chosen: []
  property string error: ""
  property bool waiting: false
  readonly property var people: demoMode ? demoPeople.filter(function(item) {
      return query === "" || String(item.name || "").toLowerCase().indexOf(query.toLowerCase()) >= 0 })
    : (service && Array.isArray(service.newChatPeople) ? service.newChatPeople : [])
  readonly property string groupName: nameField.text.replace(/\s+/g, " ").trim()
  readonly property string invite: inviteField.text.trim()
  readonly property bool inviteValid:
    /^(https?:\/\/)?(chat\.whatsapp\.com\/(invite\/)?)?[A-Za-z0-9]{16,32}\/?$/.test(invite)
  signal groupReady(string jid)

  parent: Overlay.overlay
  anchors.centerIn: parent
  width: Math.min(Style.space(430), (parent ? parent.width : Style.space(460)) - Style.space(28))
  height: Math.min(mode === "join" || step === "name" ? Style.space(250) : Style.space(520),
    (parent ? parent.height : Style.space(560)) - Style.space(36))
  padding: Style.space(14)
  modal: true
  focus: true
  closePolicy: waiting ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)

  function openFor(kind) {
    mode = kind === "join" ? "join" : "create"
    step = "pick"
    chosen = []
    error = ""
    waiting = false
    query = ""
    searchField.text = ""
    nameField.text = ""
    inviteField.text = ""
    open()
    if (mode === "create" && !demoMode && service && typeof service.searchPeople === "function")
      service.searchPeople("")
    Qt.callLater(function() {
      if (root.mode === "join") inviteField.forceActiveFocus()
      else searchField.forceActiveFocus()
    })
  }
  function isChosen(jid) {
    return chosen.some(function(item) { return item.jid === jid })
  }
  function toggle(person) {
    var jid = String(person && person.jid || "")
    if (jid === "") return false
    chosen = isChosen(jid) ? chosen.filter(function(item) { return item.jid !== jid })
      : chosen.concat([{ jid: jid, name: String(person.name || ("+" + String(person.phone || ""))) }])
    return true
  }
  function next() {
    if (chosen.length === 0) return false
    step = "name"
    error = ""
    Qt.callLater(function() { nameField.forceActiveFocus() })
    return true
  }
  function back() {
    if (waiting) return
    step = "pick"
    error = ""
  }
  function create() {
    if (waiting || groupName === "" || groupName.length > 100 || chosen.length === 0) return false
    error = ""
    if (demoMode) { close(); return true }
    var started = service && service.createGroup(groupName,
      chosen.map(function(item) { return item.jid }))
    if (!started) {
      error = service && service.groupRequest ? String(service.groupRequest.error || "") : ""
      if (error === "") error = "WhatsApp is busy with another request. Try again in a moment."
      return false
    }
    waiting = true
    return true
  }
  function join() {
    if (waiting || !inviteValid) return false
    error = ""
    if (demoMode) { close(); return true }
    if (!service || !service.joinGroup(invite)) {
      error = service && service.groupRequest ? String(service.groupRequest.error || "") : ""
      if (error === "") error = "WhatsApp is busy with another request. Try again in a moment."
      return false
    }
    waiting = true
    return true
  }

  onQueryChanged: searchDelay.restart()
  onClosed: { waiting = false; error = "" }

  Timer {
    id: searchDelay
    interval: 160
    repeat: false
    onTriggered: if (!root.demoMode && root.service && root.opened && root.mode === "create"
        && typeof root.service.searchPeople === "function") root.service.searchPeople(root.query)
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onGroupRequestChanged() {
      var request = root.service.groupRequest
      if (!root.waiting || !request || request.loading) return
      root.waiting = false
      if (String(request.error || "") !== "") {
        root.error = String(request.error)
        return
      }
      root.groupReady(String(request.jid || ""))
      root.close()
    }
  }

  background: Rectangle {
    radius: Style.cornerRadius
    color: root.surface
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
  }

  contentItem: Item {
    Item {
      id: header
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: Style.space(30)
      PanelActionButton {
        id: backButton
        objectName: "groupDialogBack"
        visible: root.mode === "create" && root.step === "name"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰁍"
        tooltipText: "Back to people"
        foreground: root.muted
        hoverColor: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.body
        size: Style.space(28)
        onClicked: root.back()
      }
      Text {
        textFormat: Text.PlainText
        anchors.left: backButton.visible ? backButton.right : parent.left
        anchors.leftMargin: backButton.visible ? Style.space(6) : 0
        anchors.verticalCenter: parent.verticalCenter
        text: root.mode === "join" ? "Join a group"
          : root.step === "name" ? "Name the group" : "New group"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      PanelActionButton {
        objectName: "groupDialogClose"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅖"
        tooltipText: "Close · Esc"
        foreground: root.muted
        hoverColor: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.body
        size: Style.space(28)
        onClicked: if (!root.waiting) root.close()
      }
    }

    // ---------------------------------------------------------------- pick
    Item {
      visible: root.mode === "create" && root.step === "pick"
      anchors.top: header.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom

      TextField {
        id: searchField
        objectName: "groupSearch"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        placeholderText: "Search people to add"
        foreground: root.foreground
        accent: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        onTextChanged: root.query = text.trim()
      }

      Text {
        textFormat: Text.PlainText
        id: chosenLine
        objectName: "groupChosen"
        anchors.top: searchField.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        text: root.chosen.length === 0 ? "Choose at least one person."
          : root.chosen.length + (root.chosen.length === 1 ? " person: " : " people: ")
            + root.chosen.map(function(item) { return item.name }).join(", ")
        color: root.muted
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      ListView {
        id: peopleList
        objectName: "groupPeople"
        anchors.top: chosenLine.bottom
        anchors.topMargin: Style.space(6)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: nextButton.top
        anchors.bottomMargin: Style.space(8)
        clip: true
        spacing: Style.space(2)
        boundsBehavior: Flickable.StopAtBounds
        model: root.people
        delegate: Rectangle {
          required property var modelData
          readonly property bool picked: root.isChosen(String(modelData.jid || ""))
          width: peopleList.width
          height: Style.space(44)
          radius: Style.cornerRadius
          color: personHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
          Text {
            textFormat: Text.PlainText
            id: mark
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: parent.picked ? "󰄲" : "󰄱"
            color: parent.picked ? root.accent : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
          }
          Column {
            anchors.left: mark.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: String(modelData.name || "") || ("+" + String(modelData.phone || ""))
              color: root.foreground
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: String(modelData.name || "") !== ""
              text: "+" + String(modelData.phone || "")
              color: root.muted
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          HoverHandler { id: personHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.toggle(modelData) }
        }
      }

      Button {
        id: nextButton
        objectName: "groupNext"
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        text: "Next"
        iconText: "󰁔"
        enabled: root.chosen.length > 0
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        bordered: true
        onClicked: root.next()
      }
    }

    // ---------------------------------------------------------------- name
    Item {
      visible: root.mode === "create" && root.step === "name"
      anchors.top: header.bottom
      anchors.topMargin: Style.space(14)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom

      TextField {
        id: nameField
        objectName: "groupName"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        placeholderText: "Group name"
        maximumLength: 100
        foreground: root.foreground
        accent: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Keys.onReturnPressed: root.create()
        Keys.onEnterPressed: root.create()
      }
      Text {
        textFormat: Text.PlainText
        id: nameNote
        objectName: "groupNote"
        anchors.top: nameField.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        wrapMode: Text.WordWrap
        text: root.error !== "" ? root.error
          : "With " + root.chosen.map(function(item) { return item.name }).join(", ")
            + ". They are added straight away, as on the phone."
        color: root.error !== "" ? "#e06c75" : root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Button {
        objectName: "groupCreate"
        anchors.top: nameNote.bottom
        anchors.topMargin: Style.space(12)
        anchors.right: parent.right
        text: root.waiting ? "Creating…" : "Create"
        iconText: "󰐕"
        enabled: !root.waiting && root.groupName !== ""
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        bordered: true
        onClicked: root.create()
      }
    }

    // ---------------------------------------------------------------- join
    Item {
      visible: root.mode === "join"
      anchors.top: header.bottom
      anchors.topMargin: Style.space(14)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom

      TextField {
        id: inviteField
        objectName: "groupInvite"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        placeholderText: "https://chat.whatsapp.com/…"
        foreground: root.foreground
        accent: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Keys.onReturnPressed: root.join()
        Keys.onEnterPressed: root.join()
      }
      Text {
        textFormat: Text.PlainText
        id: joinNote
        objectName: "groupJoinNote"
        anchors.top: inviteField.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        wrapMode: Text.WordWrap
        text: root.error !== "" ? root.error
          : root.invite !== "" && !root.inviteValid ? "That does not look like a group invite link."
          : "Paste the invite link someone sent you."
        color: root.error !== "" || (root.invite !== "" && !root.inviteValid) ? "#e06c75" : root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Button {
        objectName: "groupJoin"
        anchors.top: joinNote.bottom
        anchors.topMargin: Style.space(12)
        anchors.right: parent.right
        text: root.waiting ? "Joining…" : "Join"
        iconText: "󰍉"
        enabled: !root.waiting && root.inviteValid
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        bordered: true
        onClicked: root.join()
      }
    }
  }
}
