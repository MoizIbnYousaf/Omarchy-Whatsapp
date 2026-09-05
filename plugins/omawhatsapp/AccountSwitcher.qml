import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui
import "AccountModel.js" as AccountModel

Item {
  id: root

  required property var accounts
  required property color foreground
  required property color background
  required property color accent
  required property color muted
  required property color urgent
  required property string fontFamily
  property string selectedScope: ""
  property bool linkBusy: false
  property bool avatarBusy: false
  property bool allowAccountLink: true
  property string statusMessage: ""

  signal scopeSelected(string scope)
  signal linkRequested(string name)

  readonly property var options: AccountModel.accountOptions(accounts)
  readonly property string normalizedScope:
    AccountModel.normalizeScope(selectedScope, accounts)
  readonly property bool legacyAccount: accounts.length === 1
    && String(accounts[0].account || "") === "primary"
  readonly property int controlHeight: Style.space(34)
  readonly property bool hasStatus: statusMessage !== ""

  implicitHeight: controlHeight + (hasStatus
    ? statusLabel.implicitHeight + Style.space(4) : 0)

  ListView {
    id: accountList
    anchors.left: parent.left
    anchors.right: addButton.left
    anchors.rightMargin: Style.space(6)
    anchors.top: parent.top
    height: root.controlHeight
    orientation: ListView.Horizontal
    spacing: Style.space(5)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.options

    delegate: Rectangle {
      id: accountChip
      required property var modelData
      height: accountList.height
      width: Math.max(Style.space(52), chipLabel.implicitWidth + Style.space(18))
      radius: height / 2
      color: modelData.scope === root.normalizedScope
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
        : Style.normalFillFor(root.foreground, root.accent)
      border.width: modelData.scope === root.normalizedScope ? 1 : 0
      border.color: root.accent

      Text {
        textFormat: Text.PlainText
        id: chipLabel
        anchors.centerIn: parent
        text: String(accountChip.modelData.label || "default")
        color: accountChip.modelData.scope === root.normalizedScope
          ? root.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: accountChip.modelData.scope === root.normalizedScope
          ? Font.DemiBold : Font.Normal
      }
      TapHandler {
        onTapped: root.scopeSelected(String(accountChip.modelData.scope || ""))
      }
    }
  }

  Rectangle {
    id: addButton
    anchors.right: parent.right
    anchors.top: parent.top
    width: root.controlHeight
    height: width
    radius: width / 2
    color: addHover.hovered
      ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
    opacity: root.allowAccountLink ? 1 : 0.45
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: root.linkBusy ? "…" : "+"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }
    HoverHandler { id: addHover }
    TapHandler {
      enabled: root.allowAccountLink && !root.linkBusy && !root.avatarBusy
      onTapped: accountDialog.open()
    }
    Controls.ToolTip.visible: addHover.hovered
    Controls.ToolTip.text: root.linkBusy ? root.statusMessage : "Link another account"
  }

  Text {
    textFormat: Text.PlainText
    id: statusLabel
    objectName: "accountOperationStatus"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: root.controlHeight + Style.space(4)
    visible: root.hasStatus
    text: root.statusMessage
    elide: Text.ElideRight
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Controls.Popup {
    id: accountDialog
    x: Math.max(0, root.width - width)
    y: root.height + Style.space(6)
    width: Math.min(Style.space(330), Math.max(Style.space(240), root.width))
    modal: true
    focus: true
    closePolicy: Controls.Popup.CloseOnEscape
      | Controls.Popup.CloseOnPressOutside
    padding: Style.space(14)
    onOpened: {
      accountName.text = ""
      validation.text = ""
      accountName.forceActiveFocus()
    }
    background: Rectangle {
      radius: Style.cornerRadius
      color: root.background
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g,
        root.foreground.b, 0.16)
    }
    contentItem: Column {
      spacing: Style.space(10)
      Text {
        textFormat: Text.PlainText
        text: "Link another WhatsApp account"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: root.legacyAccount
          ? "Your existing session will be preserved as primary. A terminal will open for the new QR code."
          : "A terminal will open for the QR code. Reuse the same name to resume an unfinished link."
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      TextField {
        id: accountName
        width: parent.width
        placeholderText: "Account name, e.g. work"
        foreground: root.foreground
        accent: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Keys.onReturnPressed: root.submitAccountName()
        Keys.onEnterPressed: root.submitAccountName()
      }
      Text {
        textFormat: Text.PlainText
        id: validation
        width: parent.width
        visible: text !== ""
        wrapMode: Text.Wrap
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Rectangle {
        width: parent.width
        height: Style.space(34)
        radius: Style.cornerRadius
        color: submitHover.hovered
          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.84)
          : root.accent
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: "Open linking terminal"
          color: root.background
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }
        HoverHandler { id: submitHover }
        TapHandler { onTapped: root.submitAccountName() }
      }
    }
  }

  function submitAccountName() {
    var name = String(accountName.text || "").trim()
    var error = AccountModel.accountNameError(name, legacyAccount)
    if (error !== "") {
      validation.text = error
      return
    }
    accountDialog.close()
    linkRequested(name)
  }
}
