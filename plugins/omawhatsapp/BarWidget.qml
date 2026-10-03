import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// One quiet notification affordance over the resident local archive.
BarWidget {
  id: root

  readonly property string pluginId: "io.github.moizibnyousaf.omawhatsapp"

  readonly property var oma: bar && bar.shell
    ? bar.shell.serviceFor(root.pluginId) : null
  readonly property int unreadCount: oma ? oma.notificationUnreadCount : 0
  readonly property bool available: !!oma && oma.railReady
  readonly property bool showUnreadCount:
    root.oma ? root.oma.showUnreadCount !== false : true

  readonly property bool muted: !!oma && oma.notificationsMuted === true

  function refresh() { if (oma) oma.refresh() }
  function dismissNotifications() { if (oma) oma.dismissNotifications("") }
  function toggleMute() { if (oma) oma.toggleNotificationsMuted() }

  readonly property bool opened: dropdownLoader.item
    ? dropdownLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: dropdownLoader.item
    ? dropdownLoader.item.popoutSwitchClosing === true : false

  function injectDropdown() {
    var target = dropdownLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.oma
    if ("maxRows" in target) target.maxRows = root.oma ? Number(root.oma.dropdownRows || 7) : 7
  }

  function open() {
    injectDropdown()
    if (dropdownLoader.item) dropdownLoader.item.open()
  }

  function close() {
    if (dropdownLoader.item) dropdownLoader.item.close()
  }

  // A clicked message popup opens its chat here, ready for a reply.
  function openChat(payload) {
    injectDropdown()
    if (!dropdownLoader.item) return false
    dropdownLoader.item.open()
    return dropdownLoader.item.openChatRef(String(payload.account || ""), String(payload.jid || ""))
  }

  function closeForPopoutSwitch() {
    if (dropdownLoader.item) dropdownLoader.item.closeForPopoutSwitch()
  }

  function toggleDropdown() {
    if (dropdownLoader.item) dropdownLoader.item.toggle()
  }

  function openDropdownDemo(conversation) {
    injectDropdown()
    if (!dropdownLoader.item) return
    dropdownLoader.item.openDemo()
    // {"demo":true,"conversation":true} opens the first demo chat, so the
    // mini conversation can be captured with repository-owned data only.
    if (conversation === true && dropdownLoader.item.filteredChats.length > 0)
      dropdownLoader.item.openConversation(dropdownLoader.item.filteredChats[0])
  }

  function openFullApp(payload) {
    if (root.oma && typeof root.oma.openApp === "function")
      root.oma.openApp(JSON.stringify(payload || ({})))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectDropdown()
  onSettingsChanged: injectDropdown()
  onOmaChanged: injectDropdown()

  Loader {
    id: dropdownLoader
    active: true
    source: Qt.resolvedUrl("Dropdown.qml")
    visible: false
    onLoaded: {
      root.injectDropdown()
      Qt.callLater(root.injectDropdown)
    }
  }

  WidgetButton {
    id: button
    objectName: "barButton"
    anchors.fill: parent
    bar: root.bar
    // Muted shows a crossed bell next to the count; a vertical bar has room
    // for one glyph, so the bell replaces the logo there.
    text: root.vertical
      ? (root.muted ? "󰂛" : "󰖣")
      : "󰖣" + (root.available && root.showUnreadCount && root.unreadCount > 0
        ? " " + (root.unreadCount > 99 ? "99+" : root.unreadCount) : "")
        + (root.muted ? " 󰂛" : "")
    active: root.available && root.unreadCount > 0
    // Closed: grey until it opens again.
    dimmed: root.muted || (!!root.oma && root.oma.closed === true)
    horizontalMargin: 8
    tooltipText: root.oma ? root.oma.barTooltipWithMute : "OmaWhatsApp · reconnecting"

    onPressed: function(code) {
      if (code === Qt.MiddleButton) root.dismissNotifications()
      else if (code === Qt.RightButton) root.toggleMute()
      else {
        // A closed OmaWhatsApp opens again from its icon.
        if (root.oma && root.oma.closed === true) root.oma.launchApp()
        root.toggleDropdown()
      }
    }
  }

  Connections {
    target: dropdownLoader.item
    function onFullAppRequested(payload) { root.openFullApp(payload || ({})) }
    function onRefreshRequested() { root.refresh() }
  }

  Connections {
    target: root.oma
    function onOpenDropdownRequested(payload) {
      if (payload && payload.demo) root.openDropdownDemo(payload.conversation === true)
      else if (payload && String(payload.jid || "") !== "") root.openChat(payload)
      else root.open()
    }
    function onToggleDropdownRequested() {
      root.toggleDropdown()
    }
  }
}
