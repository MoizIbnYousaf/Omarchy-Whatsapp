import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// One quiet notification affordance over the resident local archive.
BarWidget {
  id: root

  readonly property var oma: bar && bar.shell
    ? bar.shell.serviceFor("io.github.moizibnyousaf.omawhatsapp") : null
  readonly property int unreadCount: oma ? oma.notificationUnreadCount : 0
  readonly property bool available: !!oma && oma.ready
  readonly property bool showUnreadCount:
    String(root.setting("showUnreadCount", "On")) !== "Off"

  function refresh() { if (oma) oma.refresh() }
  function dismissNotifications() { if (oma) oma.dismissNotifications("") }

  function openApp(payload) {
    if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function")
      root.bar.shell.toggle("io.github.moizibnyousaf.omawhatsapp", JSON.stringify(payload || ({})))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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
      else root.openApp({})
    }
  }
}
