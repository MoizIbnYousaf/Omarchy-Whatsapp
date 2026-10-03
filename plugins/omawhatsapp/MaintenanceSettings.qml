import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui as Ui

Column {
  id: root
  required property var service
  required property var updates
  required property color foreground
  required property color accent
  required property string fontFamily
  property bool demoMode: false
  // Settings → Media owns the chat-photo action; Updates embeds the rest.
  property bool showChatPhotos: true
  spacing: Style.space(8)
  readonly property var operations: service ? service.accountOperations : null

  Ui.Button {
    objectName: "refreshChatPhotos"
    visible: root.showChatPhotos
    width: parent.width
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    focusable: true
    bordered: true
    text: root.operations && root.operations.avatarBusy ? "Refreshing chat photos…" : "Refresh chat photos"
    enabled: !root.demoMode && !!root.operations
      && !root.operations.avatarBusy && !root.operations.linkBusy
    onClicked: root.operations.refreshAvatars()
  }
  Text {
    textFormat: Text.PlainText
    visible: root.showChatPhotos
    width: parent.width
    wrapMode: Text.Wrap
    text: root.operations && root.operations.statusMessage
      ? root.operations.statusMessage : "Fetch recent chat photos from WhatsApp when you need them."
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
  Controls.CheckBox {
    objectName: "checkUpdatesOnLaunch"
    width: parent.width
    text: "Check for updates when opening the app"
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    palette.windowText: root.foreground
    palette.highlight: root.accent
    contentItem: Text {
      textFormat: Text.PlainText
      text: parent.text
      leftPadding: parent.indicator.width + parent.spacing
      wrapMode: Text.Wrap
      color: root.foreground
      font: parent.font
      verticalAlignment: Text.AlignVCenter
    }
    checked: !!root.service && root.service.checkUpdatesOnLaunch === true
    enabled: !root.demoMode && !!root.service && !root.service.settingsWriting
    onClicked: root.service.setPreference("check_updates_on_launch", checked)
  }
  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.Wrap
    text: root.updates.message + "\nChecks contact GitHub only; no chat data is sent. Nothing installs automatically."
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
  Ui.Button {
    width: parent.width
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    focusable: true
    bordered: true
    text: root.updates.busy ? "Checking…" : "Check for updates"
    enabled: !root.demoMode && root.updates.online && !root.updates.busy
    onClicked: root.updates.check()
  }
  Ui.Button {
    objectName: "updateInTerminal"
    width: parent.width
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    focusable: true
    bordered: true
    visible: !!root.updates.release && root.updates.release.available === true
      && root.updates.release.managed === true
    text: "Update in terminal…"
    enabled: !root.demoMode && root.updates.online && !root.updates.busy
    onClicked: root.updates.install()
  }
  // Updated files wait for the shell to load them.
  Ui.Button {
    objectName: "restartShell"
    width: parent.width
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    focusable: true
    bordered: true
    visible: !!root.service && root.service.helperOutdated === true
    text: "Restart the shell to finish updating"
    enabled: !root.demoMode
    onClicked: root.service.restartShell()
  }
}
