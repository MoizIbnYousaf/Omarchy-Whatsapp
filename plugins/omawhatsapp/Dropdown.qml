import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DropdownModel.js" as DropdownModel

// A complete, bar-anchored mini client. The resident service stays the single
// source of truth; this surface only owns transient navigation and draft state.
Panel {
  id: root
  moduleName: "io.github.moizibnyousaf.omawhatsapp"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool demoMode: false
  property int maxRows: 7
  property int selectedIndex: 0
  property int messageIndex: 0
  property string searchText: ""
  property string viewMode: "chats"
  property var currentChat: null
  property var replyTarget: null
  property var pendingAttachments: []
  property string pendingWriteJid: ""
  property string errorText: ""
  property bool copiedVisible: false
  property var demoItems: [
    { id: "demo-message-1", text: "The bar dropdown can send now.", sender: "Alex", timestamp: 1787540400, from_me: false, media_type: "", mime_type: "", local_path: "", reactions: [] },
    { id: "demo-message-2", text: "Fast, local, and keyboard-first.", sender: "You", timestamp: 1787540100, from_me: true, media_type: "", mime_type: "", local_path: "", reactions: [{ emoji: "⚡", from_me: false }] },
    { id: "demo-message-3", text: "Open the full client only when you need the whole toolbox.", sender: "Design team", timestamp: 1787539800, from_me: false, media_type: "", mime_type: "", local_path: "", reactions: [] }
  ]

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: Color.popups.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color muted: Qt.rgba(
    foreground.r * 0.60 + background.r * 0.40,
    foreground.g * 0.60 + background.g * 0.40,
    foreground.b * 0.60 + background.b * 0.40, 1)
  readonly property color subtle: Qt.rgba(
    foreground.r * 0.10 + background.r * 0.90,
    foreground.g * 0.10 + background.g * 0.90,
    foreground.b * 0.10 + background.b * 0.90, 1)
  readonly property color selected: Qt.rgba(
    accent.r * 0.18 + background.r * 0.82,
    accent.g * 0.18 + background.g * 0.82,
    accent.b * 0.18 + background.b * 0.82, 1)
  readonly property string fontFamily: Style.font.family
  readonly property var demoChats: [
    { jid: "demo-team", name: "Design team", kind: "group", preview: "The compact client can send now", timestamp: 1787540400, unread: 3, notification_unread: 3, pinned: true },
    { jid: "demo-alex", name: "Alex", kind: "dm", preview: "Looks perfect — ship it", timestamp: 1787539800, unread: 1, notification_unread: 1, pinned: false },
    { jid: "demo-lab", name: "OmaWhatsApp Lab", kind: "group", preview: "Native, private, and instant", timestamp: 1787539200, unread: 0, notification_unread: 0, pinned: false }
  ]
  readonly property var sourceChats: demoMode
    ? demoChats : (service && Array.isArray(service.chats) ? service.chats : [])
  readonly property var filteredChats: {
    var needle = String(searchText || "").trim().toLowerCase()
    var values = sourceChats.filter(function(chat) {
      return needle === ""
        || String(chat.name || "").toLowerCase().indexOf(needle) >= 0
        || String(chat.preview || "").toLowerCase().indexOf(needle) >= 0
    })
    return values.slice(0, Math.max(1, Number(maxRows || 7)))
  }
  readonly property var sourceMessages: demoMode
    ? demoItems : (service && Array.isArray(service.messages) ? service.messages : [])
  readonly property int rowHeight: Style.space(62)
  readonly property int chatListHeight: Math.max(2,
    Math.min(Math.max(2, maxRows), Math.max(2, filteredChats.length))) * rowHeight
  readonly property int desiredHeight: viewMode === "conversation"
    ? Style.space(620) : Style.space(48 + 8 + 40 + 8 + 8 + 42) + chatListHeight
  readonly property int notificationCount: demoMode ? 4
    : (service ? Number(service.notificationUnreadCount || 0) : 0)
  readonly property bool ready: demoMode || (service && service.ready)
  readonly property bool offline: !demoMode && service && service.offlineMode
  readonly property bool sending: !demoMode && service && service.writing
    && String(service.activeWriteChatJid || "") === currentJid()

  signal fullAppRequested(var payload)
  signal refreshRequested()

  onFilteredChatsChanged: clampSelection()

  function currentJid() {
    return currentChat ? String(currentChat.jid || "") : ""
  }

  function clampSelection() {
    selectedIndex = DropdownModel.clampIndex(selectedIndex, filteredChats.length)
  }

  function openFor(realData) {
    demoMode = realData === false
    searchText = ""
    selectedIndex = 0
    messageIndex = 0
    viewMode = "chats"
    currentChat = null
    replyTarget = null
    pendingAttachments = []
    errorText = ""
    if (!demoMode && service) {
      service.dropdownOpen = true
      service.refreshChats()
    }
    controller.show()
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function open() { openFor(true) }
  function openDemo() { openFor(false) }

  function close() {
    searchField.focus = false
    composer.focus = false
    if (!demoMode && service) service.dropdownOpen = false
    controller.hide()
  }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function moveSelection(delta) {
    if (viewMode === "conversation") {
      if (sourceMessages.length === 0) return
      messageIndex = DropdownModel.clampIndex(messageIndex + delta, sourceMessages.length)
      messageList.positionViewAtIndex(messageIndex, ListView.Contain)
      return
    }
    if (filteredChats.length === 0) return
    selectedIndex = DropdownModel.clampIndex(selectedIndex + delta, filteredChats.length)
    chatList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function activateSelection() {
    if (viewMode === "conversation") {
      focusComposer()
      return
    }
    if (selectedIndex < 0 || selectedIndex >= filteredChats.length) return
    openConversation(filteredChats[selectedIndex])
  }

  function openConversation(chat) {
    if (!chat || !chat.jid) return
    currentChat = chat
    viewMode = "conversation"
    messageIndex = 0
    replyTarget = null
    pendingAttachments = []
    errorText = ""
    if (!demoMode && service) service.selectChat(chat)
    Qt.callLater(focusComposer)
  }

  function backToChats() {
    replyTarget = null
    composer.focus = false
    viewMode = "chats"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openFullApp() {
    var payload = DropdownModel.fullAppPayload(currentChat)
    close()
    fullAppRequested(payload)
  }

  function refresh() {
    if (!demoMode && service) {
      service.refreshChats()
      if (viewMode === "conversation") service.refreshMessages()
    }
    refreshRequested()
  }

  function focusSearch() {
    if (viewMode !== "chats") return
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function focusComposer() {
    if (viewMode !== "conversation") return
    composer.forceActiveFocus()
    composer.cursorPosition = composer.length
  }

  function pasteClipboard() {
    if (demoMode) {
      composer.insert(composer.cursorPosition, "pasted from clipboard")
      focusComposer()
      return
    }
    if (!service || sending) return
    pendingWriteJid = currentJid()
    service.pasteClipboard()
  }

  function localFileUrl(path) {
    return "file://" + String(path || "").split("/")
      .map(function(part) { return encodeURIComponent(part) }).join("/")
  }

  function openFilePicker() {
    if (filePickerProcess.running || sending) return
    filePickerProcess.command = ["/usr/bin/zenity", "--file-selection",
      "--multiple", "--separator=\n", "--title=Add WhatsApp attachments"]
    filePickerProcess.running = true
  }

  function sendDraft() {
    var text = String(composer.text || "").trim()
    if (text === "" && pendingAttachments.length === 0) return
    if (demoMode) {
      demoItems = [DropdownModel.demoMessage(text,
        pendingAttachments.length > 0, Date.now())].concat(demoItems)
      composer.text = ""
      pendingAttachments = []
      replyTarget = null
      return
    }
    if (!service || sending || offline) return
    pendingWriteJid = currentJid()
    errorText = ""
    var started = pendingAttachments.length > 0
      ? service.sendFilesReply(pendingAttachments, text, replyTarget ? replyTarget.id : "")
      : service.sendText(text, replyTarget ? replyTarget.id : "", [])
    if (started && pendingAttachments.length === 0) composer.text = ""
  }

  function removeAttachment(index) {
    var next = pendingAttachments.slice()
    next.splice(index, 1)
    pendingAttachments = next
  }

  function attachmentName(url) {
    var parts = String(url || "").split("/")
    try { return decodeURIComponent(parts[parts.length - 1] || "Attachment") }
    catch (error) { return parts[parts.length - 1] || "Attachment" }
  }

  function copyText(value) {
    var text = String(value || "")
    if (text === "" || clipboardProcess.running) return
    clipboardProcess.payload = text
    clipboardProcess.stdinEnabled = true
    clipboardProcess.running = true
  }

  function initials(value) {
    var parts = String(value || "?").trim().split(/\s+/).filter(function(part) { return part !== "" })
    if (parts.length === 0) return "?"
    if (parts.length === 1) return parts[0].slice(0, 1).toUpperCase()
    return (parts[0].slice(0, 1) + parts[parts.length - 1].slice(0, 1)).toUpperCase()
  }

  function timeLabel(value) {
    var seconds = Number(value || 0)
    if (!isFinite(seconds) || seconds <= 0) return ""
    var date = new Date(seconds * 1000)
    var today = new Date()
    if (date.toDateString() === today.toDateString()) return Qt.formatTime(date, "h:mm AP")
    var yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1)
    if (date.toDateString() === yesterday.toDateString()) return "Yesterday"
    return Qt.formatDate(date, "MMM d")
  }

  Connections {
    target: root.service
    function onTextPasted(text, jid) {
      if (String(jid || "") !== root.currentJid()) return
      composer.insert(composer.cursorPosition, String(text || ""))
      root.pendingWriteJid = ""
      root.focusComposer()
    }
    function onAttachmentPasted(path, jid) {
      if (String(jid || "") !== root.currentJid()) return
      var next = root.pendingAttachments.slice()
      if (next.indexOf(path) < 0 && next.length < 10) next.push(path)
      root.pendingAttachments = next
      root.pendingWriteJid = ""
      root.focusComposer()
    }
    function onWriteCompleted(kind, jid) {
      if (String(jid || "") !== root.currentJid()) return
      root.pendingWriteJid = ""
      if (kind === "send" || kind === "files") {
        composer.text = ""
        root.pendingAttachments = []
        root.replyTarget = null
      }
      root.focusComposer()
    }
    function onWriteFailed(message, jid) {
      if (String(jid || "") !== root.currentJid()) return
      root.pendingWriteJid = ""
      root.errorText = String(message || "Message could not be sent")
      root.focusComposer()
    }
  }

  Process {
    id: clipboardProcess
    property string payload: ""
    command: ["/usr/bin/wl-copy", "--type", "text/plain;charset=utf-8"]
    stdinEnabled: true
    onStarted: {
      write(payload)
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.copiedVisible = true
        copiedTimer.restart()
      }
    }
  }

  Process {
    id: filePickerProcess
    command: []
    stdout: StdioCollector { id: filePickerOutput }
    stderr: StdioCollector { id: filePickerError }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var incoming = String(filePickerOutput.text || "").split(/\r?\n/)
        .map(function(path) { return path.trim() })
        .filter(function(path) { return path.startsWith("/") })
        .map(root.localFileUrl)
      var next = root.pendingAttachments.slice()
      for (var i = 0; i < incoming.length && next.length < 10; i++)
        if (next.indexOf(incoming[i]) < 0) next.push(incoming[i])
      root.pendingAttachments = next
      root.focusComposer()
    }
  }

  Timer {
    id: copiedTimer
    interval: 1600
    repeat: false
    onTriggered: root.copiedVisible = false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(root.desiredHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || composer.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy)
        else if (dx !== 0 && root.viewMode === "chats") root.switchPanel(dx)
      }
      onActivateRequested: root.activateSelection()
      onCloseRequested: {
        if (root.viewMode === "conversation") root.backToChats()
        else root.close()
      }
      onTabRequested: function(direction) {
        if (root.viewMode === "chats") root.switchPanel(direction)
        else root.focusComposer()
      }
      onTextKey: function(text) {
        if (text === "/") root.focusSearch()
        else if (text === "r" || text === "R") root.refresh()
        else if (text === "o" || text === "O") root.openFullApp()
        else if (text === "i" || text === "I") root.focusComposer()
      }

      Item {
        anchors.fill: parent

        Column {
          visible: root.viewMode === "chats"
          anchors.fill: parent
          spacing: Style.space(8)

          Item {
            width: parent.width
            height: Style.space(48)

            Rectangle {
              id: whatsappMark
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(34)
              height: width
              radius: width / 2
              color: root.selected
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰖣"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
            }

            Column {
              anchors.left: whatsappMark.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)
              Text {
                textFormat: Text.PlainText
                text: "OmaWhatsApp"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
              Text {
                textFormat: Text.PlainText
                text: root.offline ? "offline archive"
                  : (root.ready ? "synced · local first" : "reconnecting")
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              visible: root.notificationCount > 0
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(Style.space(25), unreadHeader.implicitWidth + Style.space(10))
              height: Style.space(24)
              radius: height / 2
              color: root.accent
              Text {
                textFormat: Text.PlainText
                id: unreadHeader
                anchors.centerIn: parent
                text: root.notificationCount > 99 ? "99+" : String(root.notificationCount)
                color: root.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
              }
            }

            Rectangle {
              id: refreshButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(32)
              height: width
              radius: width / 2
              color: refreshHover.hovered ? root.selected : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰑐"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              HoverHandler { id: refreshHover }
              TapHandler { onTapped: root.refresh() }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(40)
            radius: Style.cornerRadius
            color: root.subtle
            border.width: searchField.activeFocus ? 1 : 0
            border.color: root.accent
            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(11)
              anchors.verticalCenter: parent.verticalCenter
              text: "󰍉"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            TextField {
              id: searchField
              anchors.left: parent.left
              anchors.leftMargin: Style.space(35)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              text: root.searchText
              onTextChanged: root.searchText = text
              placeholderText: "Search recent chats"
              color: root.foreground
              placeholderTextColor: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              background: null
              selectByMouse: true
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  if (text !== "") text = ""
                  else { focus = false; keyCatcher.forceActiveFocus() }
                  event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                  focus = false
                  keyCatcher.forceActiveFocus()
                  root.moveSelection(1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  focus = false
                  keyCatcher.forceActiveFocus()
                  root.activateSelection()
                  event.accepted = true
                }
              }
            }
          }

          Item {
            width: parent.width
            height: Math.max(Style.space(120),
              Math.min(root.chatListHeight, keyCatcher.height - Style.space(154)))

            ListView {
              id: chatList
              anchors.fill: parent
              clip: true
              model: root.filteredChats
              currentIndex: root.selectedIndex
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              delegate: Item {
                id: chatRow
                required property var modelData
                required property int index
                width: chatList.width
                height: root.rowHeight
                Rectangle {
                  anchors.fill: parent
                  anchors.margins: Style.space(2)
                  radius: Style.cornerRadius
                  color: chatRow.index === root.selectedIndex || rowHover.hovered
                    ? root.selected : "transparent"
                }
                Rectangle {
                  id: avatar
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(9)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(38)
                  height: width
                  radius: width / 2
                  color: root.subtle
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: root.initials(chatRow.modelData.name)
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.weight: Font.DemiBold
                  }
                }
                Column {
                  anchors.left: avatar.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: rowMeta.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: String(chatRow.modelData.name || "WhatsApp chat")
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.weight: Number(chatRow.modelData.notification_unread || 0) > 0
                      ? Font.DemiBold : Font.Normal
                  }
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: String(chatRow.modelData.preview || "No local messages yet")
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                Column {
                  id: rowMeta
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)
                  Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    text: root.timeLabel(chatRow.modelData.timestamp)
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Rectangle {
                    visible: Number(chatRow.modelData.notification_unread || 0) > 0
                    anchors.right: parent.right
                    width: Math.max(Style.space(20), rowUnread.implicitWidth + Style.space(8))
                    height: Style.space(20)
                    radius: height / 2
                    color: root.accent
                    Text {
                      textFormat: Text.PlainText
                      id: rowUnread
                      anchors.centerIn: parent
                      text: Number(chatRow.modelData.notification_unread || 0) > 99
                        ? "99+" : String(Number(chatRow.modelData.notification_unread || 0))
                      color: root.background
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.weight: Font.DemiBold
                    }
                  }
                }
                HoverHandler { id: rowHover }
                TapHandler {
                  onTapped: {
                    root.selectedIndex = chatRow.index
                    root.openConversation(chatRow.modelData)
                  }
                }
              }
            }

            Column {
              visible: root.filteredChats.length === 0
              anchors.centerIn: parent
              spacing: Style.space(7)
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.ready ? "No matching chats" : "OmaWhatsApp is reconnecting"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.ready ? "Try a different search" : "Your local archive will appear here"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(42)
            radius: Style.cornerRadius
            color: openAllHover.hovered ? root.selected : root.subtle
            border.width: 1
            border.color: root.selected
            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(13)
              anchors.verticalCenter: parent.verticalCenter
              text: "Open full client"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
            }
            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.rightMargin: Style.space(13)
              anchors.verticalCenter: parent.verticalCenter
              text: "O  ·  J/K  ·  /  ·  Enter"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            HoverHandler { id: openAllHover }
            TapHandler { onTapped: root.openFullApp() }
          }
        }

        Item {
          visible: root.viewMode === "conversation"
          anchors.fill: parent

          Item {
            id: conversationHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Style.space(48)
            Rectangle {
              id: backButton
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(32)
              height: width
              radius: width / 2
              color: backHover.hovered ? root.selected : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰁍"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              HoverHandler { id: backHover }
              TapHandler { onTapped: root.backToChats() }
            }
            Rectangle {
              id: conversationAvatar
              anchors.left: backButton.right
              anchors.leftMargin: Style.space(7)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(34)
              height: width
              radius: width / 2
              color: root.subtle
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.initials(root.currentChat ? root.currentChat.name : "")
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
              }
            }
            Column {
              anchors.left: conversationAvatar.right
              anchors.leftMargin: Style.space(9)
              anchors.right: fullButton.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.currentChat ? String(root.currentChat.name || "WhatsApp chat") : "WhatsApp chat"
                elide: Text.ElideRight
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
              Text {
                textFormat: Text.PlainText
                text: root.offline ? "offline · viewing local archive"
                  : (root.sending ? "sending…" : "Enter sends · Shift+Enter adds a line")
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Rectangle {
              id: fullButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(32)
              height: width
              radius: width / 2
              color: fullHover.hovered ? root.selected : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰏌"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              HoverHandler { id: fullHover }
              TapHandler { onTapped: root.openFullApp() }
            }
            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: root.subtle
            }
          }

          ListView {
            id: messageList
            anchors.top: conversationHeader.bottom
            anchors.topMargin: Style.space(8)
            anchors.bottom: composerCard.top
            anchors.bottomMargin: Style.space(8)
            anchors.left: parent.left
            anchors.right: parent.right
            clip: true
            spacing: Style.space(7)
            model: root.sourceMessages
            currentIndex: root.messageIndex
            verticalLayoutDirection: ListView.BottomToTop
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Item {
              required property var modelData
              required property int index
              width: messageList.width
              height: compactMessage.height
              MessageBubble {
                id: compactMessage
                width: parent.width
                message: modelData
                foreground: root.foreground
                background: root.background
                accent: root.accent
                dim: root.muted
                dimmer: root.muted
                fontFamily: root.fontFamily
                groupChat: root.currentChat && root.currentChat.kind === "group"
                selected: index === root.messageIndex
                narrow: true
                busyMedia: root.service && root.service.writing
                  && root.service.mediaDownloadId === String(modelData.id || "")
                onSelectedRequested: {
                  root.messageIndex = index
                  keyCatcher.forceActiveFocus()
                }
                onOpenMediaRequested: root.openFullApp()
                onDownloadMediaRequested: if (!root.demoMode && root.service) root.service.downloadMedia(modelData)
                onReplyRequested: {
                  root.replyTarget = modelData
                  root.focusComposer()
                }
                onReactionRequested: function(emoji) {
                  if (!root.demoMode && root.service) root.service.reactTo(modelData, emoji)
                }
                onEditRequested: root.openFullApp()
                onDeleteRequested: root.openFullApp()
                onForwardRequested: root.openFullApp()
                onCopyRequested: function(text) { root.copyText(text) }
                onOptionRequested: function(optionIndex) {
                  if (!root.demoMode && root.service) root.service.selectOption(modelData, optionIndex)
                }
              }
            }
            Text {
              textFormat: Text.PlainText
              visible: root.sourceMessages.length === 0
              anchors.centerIn: parent
              text: !root.demoMode && root.service && root.service.loadingMessages
                ? "Loading local messages…" : "No local messages in this chat"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Rectangle {
            id: composerCard
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: composerColumn.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: root.subtle
            border.width: composer.activeFocus ? 1 : 0
            border.color: root.accent
            Column {
              id: composerColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(8)
              spacing: Style.space(6)
              Rectangle {
                visible: root.replyTarget !== null
                width: parent.width
                height: visible ? Style.space(34) : 0
                radius: Style.cornerRadius
                color: root.selected
                Text {
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(9)
                  anchors.right: cancelReply.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Replying to " + String(root.replyTarget && root.replyTarget.sender || "message")
                  elide: Text.ElideRight
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  textFormat: Text.PlainText
                  id: cancelReply
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(9)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "×"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  TapHandler { onTapped: root.replyTarget = null }
                }
              }
              Row {
                visible: root.pendingAttachments.length > 0
                width: parent.width
                height: visible ? Style.space(30) : 0
                spacing: Style.space(5)
                Repeater {
                  model: root.pendingAttachments
                  delegate: Rectangle {
                    required property string modelData
                    required property int index
                    width: Math.min(Style.space(150), attachmentLabel.implicitWidth + Style.space(28))
                    height: Style.space(28)
                    radius: Style.cornerRadius
                    color: root.selected
                    Text {
                      textFormat: Text.PlainText
                      id: attachmentLabel
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(7)
                      anchors.right: removeFile.left
                      anchors.rightMargin: Style.space(5)
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.attachmentName(modelData)
                      elide: Text.ElideMiddle
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      textFormat: Text.PlainText
                      id: removeFile
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(7)
                      anchors.verticalCenter: parent.verticalCenter
                      text: "×"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      TapHandler { onTapped: root.removeAttachment(index) }
                    }
                  }
                }
              }
              Row {
                width: parent.width
                spacing: Style.space(7)
                Rectangle {
                  width: Style.space(34)
                  height: width
                  radius: width / 2
                  color: pasteHover.hovered ? root.selected : "transparent"
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "󰃦"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  HoverHandler { id: pasteHover }
                  TapHandler { onTapped: root.openFilePicker() }
                }
                Rectangle {
                  width: Style.space(34)
                  height: width
                  radius: width / 2
                  color: clipboardHover.hovered ? root.selected : "transparent"
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "󰅌"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  HoverHandler { id: clipboardHover }
                  TapHandler { onTapped: root.pasteClipboard() }
                }
                TextArea {
                  id: composer
                  width: parent.width - Style.space(123)
                  height: Math.max(Style.space(44), Math.min(implicitHeight, Style.space(96)))
                  placeholderText: root.offline ? "Offline archive is read-only" : "Message"
                  readOnly: root.offline || root.sending
                  color: root.foreground
                  placeholderTextColor: root.muted
                  selectionColor: root.accent
                  selectedTextColor: root.background
                  wrapMode: TextEdit.Wrap
                  selectByMouse: true
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  background: null
                  Keys.onPressed: function(event) {
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                      root.pasteClipboard()
                      event.accepted = true
                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_O) {
                      root.openFilePicker()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                      if (root.replyTarget) root.replyTarget = null
                      else {
                        focus = false
                        keyCatcher.forceActiveFocus()
                      }
                      event.accepted = true
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                               && !(event.modifiers & Qt.ShiftModifier)) {
                      root.sendDraft()
                      event.accepted = true
                    }
                  }
                }
                Rectangle {
                  width: Style.space(34)
                  height: width
                  radius: width / 2
                  color: root.offline || root.sending ? root.subtle : root.accent
                  opacity: root.offline ? 0.5 : 1
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: root.sending ? "…" : "󰒊"
                    color: root.offline || root.sending ? root.muted : root.background
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  TapHandler { enabled: !root.offline && !root.sending; onTapped: root.sendDraft() }
                }
              }
              Text {
                textFormat: Text.PlainText
                visible: root.errorText !== ""
                width: parent.width
                text: root.errorText
                elide: Text.ElideRight
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Rectangle {
            visible: root.copiedVisible
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: composerCard.top
            anchors.bottomMargin: Style.space(10)
            width: copiedLabel.implicitWidth + Style.space(24)
            height: Style.space(34)
            radius: Style.cornerRadius
            color: root.background
            border.width: 1
            border.color: root.accent
            Text {
              textFormat: Text.PlainText
              id: copiedLabel
              anchors.centerIn: parent
              text: "copied to clipboard"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
            }
          }
        }
      }
    }
  }
}
