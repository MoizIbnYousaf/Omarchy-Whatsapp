import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// New chat. It searches the people this account's mirror knows and, for a
// typed number, asks WhatsApp whether it is registered. A person with a chat
// just opens it; anyone else gets a first-message step, and nothing is sent
// until the owner presses Send.
Popup {
  id: root
  objectName: "newChatDialog"

  property var service: null
  property bool demoMode: false
  property var demoPeople: []
  property string accountLabel: ""
  property color foreground: Color.foreground
  // Popup already owns `background`.
  property color surface: Color.background
  property color accent: Color.accent
  property color muted: foreground
  property color urgent: "#e06c75"
  property string fontFamily: Style.font.family
  property bool showAvatars: true
  // Chats of this account, so a known person shows the same photo as the rail.
  property var chats: []

  property string step: "search"
  property string query: ""
  property var person: null
  property bool sending: false
  property string sendError: ""
  property var demoCheck: null
  readonly property string digits: query.replace(/[^0-9]/g, "")
  readonly property bool numberQuery: /^[+]?[0-9 ().-]+$/.test(query)
    && digits.length >= 7 && digits.length <= 15
  readonly property var check: demoMode
    ? (demoCheck && demoCheck.phone === digits ? demoCheck : null)
    : (service && typeof service.numberCheckFor === "function"
      ? service.numberCheckFor(digits) : null)
  readonly property var people: demoMode ? filterDemo(demoPeople, query)
    : (service && Array.isArray(service.newChatPeople) ? service.newChatPeople : [])
  readonly property string numberState: !numberQuery ? ""
    : check === null ? "idle"
    : check.loading ? "checking"
    : check.error ? "error"
    : check.registered ? "registered" : "absent"
  // The number as typed reads better than bare digits: +55 16 99999-0000.
  readonly property string typedNumber: (query.charAt(0) === "+" ? "" : "+") + query
  readonly property string numberText: {
    var phone = typedNumber
    if (numberState === "checking") return "Checking " + phone + " with WhatsApp…"
    if (numberState === "error") return check.error
    if (numberState === "absent") return phone + " is not on WhatsApp"
    if (numberState === "registered") return "Message " + phone
    return "Check " + phone + " on WhatsApp"
  }
  signal openChatRequested(string jid)
  // New group and joining one by link live in their own dialog.
  signal groupRequested(string kind)
  signal chatStarted(string jid)

  parent: Overlay.overlay
  anchors.centerIn: parent
  width: Math.min(Style.space(430), (parent ? parent.width : Style.space(460)) - Style.space(28))
  height: Math.min(step === "compose" ? Style.space(300) : Style.space(520),
    (parent ? parent.height : Style.space(560)) - Style.space(36))
  padding: Style.space(14)
  modal: true
  focus: true
  closePolicy: sending ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)

  onOpened: begin()
  onClosed: {
    step = "search"
    person = null
    sending = false
    sendError = ""
  }
  onQueryChanged: searchDelay.restart()
  onCheckChanged: {
    if (!check || check.loading || !check.registered || step !== "search") return
    if (check.has_chat) openExisting(check.jid)
    else compose({ jid: check.jid, name: String(check.name || ""), phone: check.phone,
      display: typedNumber, has_chat: false })
  }

  function filterDemo(list, needle) {
    var value = String(needle || "").trim().toLowerCase()
    var number = value.replace(/[^0-9]/g, "")
    return (list || []).filter(function(item) {
      return value === "" || String(item.name || "").toLowerCase().indexOf(value) >= 0
        || (number !== "" && String(item.phone || "").indexOf(number) >= 0)
    })
  }
  function begin() {
    step = "search"
    person = null
    sendError = ""
    sending = false
    demoCheck = null
    searchField.text = ""
    query = ""
    if (!demoMode && service && typeof service.searchPeople === "function")
      service.searchPeople("")
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }
  function avatarChat(item) {
    var jid = String(item && item.jid || "")
    var known = (chats || []).find(function(chat) { return String(chat.jid || "") === jid })
    return { name: label(item), kind: "dm", avatar_path: known ? String(known.avatar_path || "") : "" }
  }
  function phoneText(item) {
    var shown = String(item && item.display || "")
    return shown !== "" ? shown : "+" + String(item && item.phone || "")
  }
  function label(item) {
    var name = String(item && item.name || "")
    return name !== "" ? name : phoneText(item)
  }
  function openExisting(jid) {
    openChatRequested(String(jid))
    close()
  }
  function compose(item) {
    person = item
    step = "compose"
    sendError = ""
    firstMessage.text = ""
    Qt.callLater(function() { firstMessage.forceActiveFocus() })
  }
  function choose(item) {
    if (!item || String(item.jid || "") === "") return false
    if (item.has_chat) openExisting(item.jid)
    else compose(item)
    return true
  }
  function checkTypedNumber() {
    if (!numberQuery || numberState === "checking") return false
    if (demoMode) {
      demoCheck = { phone: digits, loading: false, responded: true, registered: true,
        jid: digits + "@s.whatsapp.net", has_chat: false, name: "", error: "" }
      return true
    }
    return service && typeof service.checkNumber === "function"
      ? service.checkNumber(query) : false
  }
  function activateNumberRow() {
    if (numberState === "registered" && check) {
      if (check.has_chat) openExisting(check.jid)
      else compose({ jid: check.jid, name: String(check.name || ""), phone: check.phone,
        display: typedNumber, has_chat: false })
      return true
    }
    if (numberState === "absent") return false
    return checkTypedNumber()
  }
  function acceptSearch() {
    if (numberQuery) return activateNumberRow()
    return people.length > 0 ? choose(people[0]) : false
  }
  // Demo captures and the IPC prefill go through the real field.
  function typeQuery(text) {
    searchField.text = String(text || "")
    query = searchField.text.trim()
    searchField.forceActiveFocus()
  }
  function back() {
    if (sending) return
    step = "search"
    person = null
    sendError = ""
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }
  function sendFirst() {
    var text = String(firstMessage.text || "").trim()
    if (sending || !person || text === "") return false
    sendError = ""
    if (demoMode) {
      chatStarted(person.jid)
      close()
      return true
    }
    if (!service || !service.startNewChat(person.jid, text, "app")) {
      sendError = service && service.errorText ? service.errorText
        : "WhatsApp is busy with another request. Try again in a moment."
      return false
    }
    sending = true
    return true
  }

  Timer {
    id: searchDelay
    interval: 160
    repeat: false
    onTriggered: if (!root.demoMode && root.service && root.opened
        && typeof root.service.searchPeople === "function") root.service.searchPeople(root.query)
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onWriteCompleted(kind, chatRef, request, owner) {
      if (kind !== "send-new" || !root.sending || !root.person
          || String(chatRef.jid || "") !== root.person.jid) return
      root.sending = false
      var landed = String(root.service.lastStartedChatJid || "")
      root.chatStarted(landed !== "" ? landed : root.person.jid)
      root.close()
    }
    function onWriteFailed(message, chatRef, details, owner) {
      if (!root.sending || !details || details.kind !== "send-new") return
      root.sending = false
      root.sendError = String(message || "The message could not be sent.")
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
        objectName: "newChatBack"
        visible: root.step === "compose"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰁍"
        tooltipText: "Back to search"
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
        anchors.right: closeButton.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.accountLabel !== "" ? "New chat · " + root.accountLabel : "New chat"
        color: root.foreground
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }
      PanelActionButton {
        id: closeButton
        objectName: "newChatClose"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        enabled: !root.sending
        iconText: "󰅖"
        tooltipText: "Close · Esc"
        foreground: root.muted
        hoverColor: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.body
        size: Style.space(28)
        onClicked: root.close()
      }
    }

    Item {
      id: searchStep
      visible: root.step === "search"
      anchors.top: header.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom

      TextField {
        id: searchField
        objectName: "newChatSearch"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        placeholderText: "Search a name or type a number"
        foreground: root.foreground
        accent: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        onTextChanged: root.query = text.trim()
        Keys.onReturnPressed: root.acceptSearch()
        Keys.onEnterPressed: root.acceptSearch()
        HoverHandler { id: searchHover }
        PanelToolTip {
          visible: searchHover.hovered && !searchField.activeFocus
          text: "Numbers need the country code, like +55 for Brazil"
        }
      }

      Rectangle {
        id: numberRow
        objectName: "newChatNumber"
        visible: root.numberQuery
        anchors.top: searchField.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? Style.space(48) : 0
        radius: Style.cornerRadius
        color: numberHover.hovered && root.numberState !== "absent"
          ? Style.hoverFillFor(root.foreground, root.accent)
          : Style.normalFillFor(root.foreground, root.accent)
        Text {
          textFormat: Text.PlainText
          id: numberIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: "󰷰"
          color: root.numberState === "registered" ? root.accent : root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
        Text {
          textFormat: Text.PlainText
          objectName: "newChatNumberText"
          anchors.left: numberIcon.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: root.numberText
          color: root.numberState === "error" || root.numberState === "absent"
            ? root.urgent : root.foreground
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        HoverHandler {
          id: numberHover
          cursorShape: root.numberState === "absent" || root.numberState === "checking"
            ? Qt.ArrowCursor : Qt.PointingHandCursor
        }
        TapHandler { onTapped: root.activateNumberRow() }
        PanelToolTip {
          visible: numberHover.hovered && root.numberState === "idle"
          text: "Asks WhatsApp whether this number has an account. Nothing is sent."
        }
      }

      Column {
        id: groupRows
        objectName: "newChatGroupRows"
        visible: !root.numberQuery && root.query === ""
        anchors.top: searchField.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(2)
        Repeater {
          model: [{ kind: "create", icon: "󰡉", label: "New group" },
                  { kind: "join", icon: "󰌷", label: "Join a group with a link" }]
          delegate: Rectangle {
            required property var modelData
            objectName: "newChatGroup-" + modelData.kind
            width: groupRows.width
            height: Style.space(40)
            radius: Style.cornerRadius
            color: groupHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.icon + "   " + modelData.label
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            HoverHandler { id: groupHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
              onTapped: {
                root.close()
                root.groupRequested(modelData.kind)
              }
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        id: peopleHeading
        anchors.top: numberRow.visible ? numberRow.bottom
          : (groupRows.visible ? groupRows.bottom : searchField.bottom)
        anchors.topMargin: Style.space(12)
        anchors.left: parent.left
        text: root.people.length > 0 ? "Contacts" : ""
        visible: text !== ""
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      ListView {
        id: peopleList
        objectName: "newChatPeople"
        anchors.top: peopleHeading.visible ? peopleHeading.bottom : peopleHeading.top
        anchors.topMargin: Style.space(4)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        spacing: Style.space(2)
        boundsBehavior: Flickable.StopAtBounds
        model: root.people
        delegate: Rectangle {
          required property var modelData
          width: peopleList.width
          height: Style.space(46)
          radius: Style.cornerRadius
          color: personHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
          ChatAvatar {
            id: personAvatar
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(32)
            height: width
            showPhoto: root.showAvatars
            chat: root.avatarChat(modelData)
            foreground: root.foreground
            background: root.surface
            accent: root.accent
            fontFamily: root.fontFamily
          }
          Column {
            anchors.left: personAvatar.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.label(modelData)
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
                + (modelData.has_chat ? "" : " · no chat yet")
              color: root.muted
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          HoverHandler { id: personHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.choose(modelData) }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.people.length === 0 && !root.numberQuery
        anchors.top: searchField.bottom
        anchors.topMargin: Style.space(28)
        anchors.left: parent.left
        anchors.right: parent.right
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.query === "" ? "No contacts synced yet. Type a number with its country code."
          : "No contact matches. Type a number with its country code to reach someone new."
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      id: composeStep
      visible: root.step === "compose"
      anchors.top: header.bottom
      anchors.topMargin: Style.space(14)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom

      Row {
        id: recipient
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)
        ChatAvatar {
          width: Style.space(44)
          height: width
          showPhoto: root.showAvatars
          chat: root.avatarChat(root.person)
          foreground: root.foreground
          background: root.surface
          accent: root.accent
          fontFamily: root.fontFamily
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: recipient.width - Style.space(56)
          Text {
            textFormat: Text.PlainText
            objectName: "newChatRecipient"
            width: parent.width
            text: root.label(root.person)
            color: root.foreground
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.person !== null && String(root.person.name || "") !== ""
            text: root.person ? root.phoneText(root.person) : ""
            color: root.muted
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Rectangle {
        id: messageSurface
        anchors.top: recipient.bottom
        anchors.topMargin: Style.space(16)
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(120)
        radius: Style.cornerRadius
        color: Style.normalFillFor(root.foreground, root.accent)
        border.width: 1
        border.color: firstMessage.activeFocus
          ? Style.hoverBorderFor(root.foreground, root.accent)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        ScrollView {
          anchors.fill: parent
          anchors.margins: Style.space(4)
          TextArea {
            id: firstMessage
            objectName: "newChatMessage"
            placeholderText: "First message"
            enabled: !root.sending
            color: root.foreground
            selectionColor: root.accent
            selectedTextColor: root.surface
            wrapMode: TextEdit.Wrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            background: null
            Keys.onReturnPressed: function(event) {
              if (event.modifiers & Qt.ShiftModifier) event.accepted = false
              else root.sendFirst()
            }
            Keys.onEnterPressed: function(event) {
              if (event.modifiers & Qt.ShiftModifier) event.accepted = false
              else root.sendFirst()
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        id: composeNote
        objectName: "newChatNote"
        anchors.top: messageSurface.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: sendButton.left
        anchors.rightMargin: Style.space(10)
        wrapMode: Text.WordWrap
        text: root.sendError !== "" ? root.sendError
          : root.sending ? "Sending…"
          : "The chat starts with this message. Enter sends, Shift+Enter adds a line."
        color: root.sendError !== "" ? root.urgent : root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Button {
        id: sendButton
        objectName: "newChatSend"
        anchors.top: messageSurface.bottom
        anchors.topMargin: Style.space(8)
        anchors.right: parent.right
        text: root.sending ? "Sending…" : "Send"
        iconText: "󰒊"
        enabled: !root.sending && firstMessage.text.trim() !== ""
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        bordered: true
        onClicked: root.sendFirst()
      }
    }
  }
}
