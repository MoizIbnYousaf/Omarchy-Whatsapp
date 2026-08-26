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
  readonly property bool available: !!oma && oma.ready
  readonly property bool showUnreadCount:
    root.oma ? root.oma.showUnreadCount !== false : true

  function refresh() { if (oma) oma.refresh() }
  function dismissNotifications() { if (oma) oma.dismissNotifications("") }

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

  function closeForPopoutSwitch() {
    if (dropdownLoader.item) dropdownLoader.item.closeForPopoutSwitch()
  }

  function toggleDropdown() {
    if (dropdownLoader.item) dropdownLoader.item.toggle()
  }

  function openDropdownDemo() {
    injectDropdown()
    if (dropdownLoader.item) dropdownLoader.item.openDemo()
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
    anchors.fill: parent
    bar: root.bar
    text: root.vertical
      ? "󰠮"
      : "󰠮" + (root.available && root.showUnreadCount && root.unreadCount > 0
        ? " " + (root.unreadCount > 99 ? "99+" : root.unreadCount) : "")
    active: root.available && root.unreadCount > 0
    horizontalMargin: 8
    tooltipText: root.oma ? root.oma.barTooltip : "OmaWhatsApp · reconnecting"

    onPressed: function(code) {
      if (code === Qt.MiddleButton) root.dismissNotifications()
      else if (code === Qt.RightButton) root.refresh()
      else root.toggleDropdown()
    }
  }

  Connections {
    target: dropdownLoader.item
    function onFullAppRequested(payload) { root.openFullApp(payload || ({})) }
    function onRefreshRequested() { root.refresh() }
  }
}
