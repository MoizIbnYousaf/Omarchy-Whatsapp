import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "ShortcutModel.js" as Shortcuts

Column {
  id: root
  objectName: "shortcutSettings"
  property var service: null
  property var app: null
  property bool demoMode: false
  property var overlayHost: root
  property var demoOverrides: ({})
  readonly property var overrides: demoMode ? (app && app.demoShortcuts ? app.demoShortcuts : demoOverrides) : service && service.shortcuts ? service.shortcuts : ({})
  readonly property bool enterSends: !service || service.enterSends !== false
  property bool modifiedOnly: false
  property string groupFilter: "All"
  property string editing: ""
  property int editingIndex: 0
  property var proposed: []
  property string candidate: ""
  property string error: ""
  property string notice: ""
  property bool pending: false
  readonly property bool recording: editing !== ""
  readonly property string candidateError: candidate === "" ? "" : Shortcuts.captureError(editing, candidate)
  readonly property string conflict: candidate === "" || candidateError !== "" ? "" : Shortcuts.conflict(editing, replaced(candidate), overrides, enterSends)
  signal desktopShortcutRequested()
  spacing: Style.space(12)

  function keys(id) { return Shortcuts.bindings(id, overrides, enterSends) }
  function replaced(sequence) {
    var next = proposed.slice()
    if (editingIndex >= next.length) next.push(sequence)
    else next[editingIndex] = sequence
    return next.filter(function(s, i) { return next.indexOf(s) === i })
  }
  function edit(id, index) {
    editing = id; editingIndex = index; proposed = keys(id).slice(); candidate = ""; error = ""; notice = ""
    Qt.callLater(function() { captureZone.forceActiveFocus() })
  }
  function cancel() {
    if (pending) return
    editing = ""; candidate = ""; error = ""
  }
  function commit(next) {
    if (pending) return false
    var problem = Shortcuts.configurationError(next, enterSends)
    if (problem) { error = problem; return false }
    error = ""
    if (demoMode) { if (app && app.demoShortcuts !== undefined) app.demoShortcuts = next; else demoOverrides = next; editing = ""; notice = "Saved for this preview only."; return true }
    if (!service || typeof service.setPreference !== "function") { error = "Settings are not available yet."; return false }
    pending = true
    if (!service.setPreference("shortcuts", next)) { pending = false; error = "Another setting is being saved. Try again."; return false }
    return true
  }
  function save() {
    if (!candidate || candidateError || conflict || pending) return false
    var next = Object.assign({}, overrides)
    next[editing] = replaced(candidate)
    return commit(next)
  }
  function reset(id) {
    var next = Object.assign({}, overrides); delete next[id]; return commit(next)
  }
  function remove() {
    var next = Object.assign({}, overrides)
    var sequences = proposed.slice(); sequences.splice(editingIndex, 1)
    next[editing] = sequences
    return commit(next)
  }
  function filtered() {
    var query = search.text.trim().toLowerCase()
    return Shortcuts.actions.filter(function(item) {
      return (root.groupFilter === "All" || item.group === root.groupFilter)
        && (!root.modifiedOnly || Object.prototype.hasOwnProperty.call(root.overrides, item.id))
        && (!query || (item.title + " " + item.group + " " + root.keys(item.id).join(" ")).toLowerCase().indexOf(query) >= 0)
    })
  }
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onSettingsCompleted() {
      if (!root.pending) return
      root.pending = false; root.editing = ""; root.notice = "Shortcuts saved. Ready to use in every window."
    }
    function onSettingsFailed(message) { if (root.pending) { root.pending = false; root.error = String(message) } }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    text: "Make it feel like yours"
    color: Commons.Color.foreground
    font.family: Style.font.family; font.pixelSize: Style.font.title
  }
  Text {
    textFormat: Text.PlainText
    width: parent.width; wrapMode: Text.Wrap
    text: "Click a key to change it. Add an alternative, remove a binding, or restore its default. Changes apply to every account on this device."
    color: Commons.Color.foreground; opacity: 0.65
    font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
  }
  Ui.TextField {
    id: search
    objectName: "shortcutSearch"
    width: parent.width
    placeholderText: "Search actions or keys…"
    font.family: Style.font.family; font.pixelSize: Style.font.body
    foreground: Commons.Color.foreground; accent: Commons.Color.accent
  }
  Flow {
    width: parent.width; spacing: Style.space(8)
    Ui.Button {
      text: root.modifiedOnly ? "✓ Customized only" : "Customized only"
      focusable: true; bordered: true; selected: root.modifiedOnly
      onClicked: root.modifiedOnly = !root.modifiedOnly
    }
    Ui.Button {
      objectName: "resetAllShortcuts"
      text: "Reset all…"; focusable: true; bordered: true
      enabled: Object.keys(root.overrides).length > 0 && !root.pending
      onClicked: { root.editing = "__reset__"; root.error = ""; Qt.callLater(function() { resetConfirm.forceActiveFocus() }) }
    }
  }
  Flow {
    width: parent.width; spacing: Style.space(6)
    Repeater {
      model: ["All", "Everyday actions", "Navigation", "Writing", "Mini client", "Media viewer", "Forwarding"]
      delegate: Ui.Button {
        required property string modelData
        text: modelData
        focusable: true; bordered: true; selected: root.groupFilter === modelData
        onClicked: root.groupFilter = modelData
      }
    }
  }
  Text {
    textFormat: Text.PlainText
    visible: root.notice !== "" || (root.error !== "" && !root.recording)
    width: parent.width; wrapMode: Text.Wrap
    text: root.error || root.notice
    color: root.error ? Commons.Color.urgent : Commons.Color.accent
    font.family: Style.font.family; font.pixelSize: Style.font.caption
    Accessible.role: Accessible.AlertMessage
  }
  Repeater {
    model: root.filtered()
    delegate: Column {
      id: actionRow
      required property var modelData
      required property int index
      width: root.width; spacing: Style.space(8)
      readonly property bool modified: Object.prototype.hasOwnProperty.call(root.overrides, modelData.id)
      Text {
        textFormat: Text.PlainText
        visible: actionRow.index === 0 || root.filtered()[actionRow.index - 1].group !== actionRow.modelData.group
        topPadding: Style.space(12); bottomPadding: Style.space(4)
        text: actionRow.modelData.group
        color: Commons.Color.accent
        font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.weight: Font.DemiBold
      }
      Rectangle {
        width: parent.width; height: actionContent.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: Style.normalFillFor(Commons.Color.foreground, Commons.Color.accent)
        border.width: actionRow.modified ? 1 : 0
        border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25)
        Column {
          id: actionContent
          anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Style.space(14)
          y: Style.space(12); spacing: Style.space(8)
          Text {
            textFormat: Text.PlainText
            width: parent.width; wrapMode: Text.Wrap
            text: actionRow.modelData.title + (actionRow.modified ? "  ·  Customized" : "")
            color: Commons.Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width; wrapMode: Text.Wrap
            text: actionRow.modelData.description
            color: Commons.Color.foreground; opacity: 0.6
            font.family: Style.font.family; font.pixelSize: Style.font.caption
          }
          Flow {
            width: parent.width; spacing: Style.space(6)
            Repeater {
              model: root.keys(actionRow.modelData.id)
              delegate: Ui.Button {
                required property string modelData
                required property int index
                objectName: "shortcut-" + actionRow.modelData.id + "-" + index
                text: Shortcuts.label(modelData)
                bordered: true; focusable: true
                tooltipText: "Change " + actionRow.modelData.title
                onClicked: root.edit(actionRow.modelData.id, index)
                Accessible.name: actionRow.modelData.title + ": " + text + ". Change shortcut"
              }
            }
            Ui.Button {
              objectName: "addShortcut-" + actionRow.modelData.id
              text: root.keys(actionRow.modelData.id).length === 0 ? "Set shortcut" : "+"
              visible: root.keys(actionRow.modelData.id).length < 3
              bordered: true; focusable: true
              tooltipText: "Add an alternative shortcut"
              onClicked: root.edit(actionRow.modelData.id, root.keys(actionRow.modelData.id).length)
            }
            Ui.Button {
              text: "Reset"; visible: actionRow.modified
              focusable: true; enabled: !root.pending
              onClicked: root.reset(actionRow.modelData.id)
            }
          }
        }
      }
    }
  }
  Text {
    textFormat: Text.PlainText
    visible: root.filtered().length === 0
    text: "No matching shortcuts. Try another search."
    color: Commons.Color.foreground; opacity: 0.65
    font.family: Style.font.family; font.pixelSize: Style.font.body
  }
  Text {
    textFormat: Text.PlainText
    width: parent.width; wrapMode: Text.Wrap
    text: "Tab / Shift+Tab move between controls. Esc cancels dialogs. Standard text editing and dialog confirmation keys stay available. The desktop launch shortcut (Super+Shift+W by default) is managed by Omarchy; desktop bindings can intercept keys before the app receives them."
    color: Commons.Color.foreground; opacity: 0.6
    font.family: Style.font.family; font.pixelSize: Style.font.caption
  }

  Popup {
    id: shortcutDialog
    parent: root.overlayHost
    visible: root.recording
    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose
    width: Math.min(parent.width - Style.space(24), Style.space(440))
    height: dialogColumn.implicitHeight + Style.space(40)
    x: (parent.width - width) / 2
    y: Math.max(Style.space(12), (parent.height - height) / 2)
    padding: Style.space(20)
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.65) }
    background: Rectangle {
      radius: Style.cornerRadius * 2
      color: Commons.Color.background
      border.width: 1
      border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.5)
    }
    contentItem: Column {
      id: dialogColumn
      spacing: Style.space(14)
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.cancel(); event.accepted = true }
      }
        Text {
          textFormat: Text.PlainText
          width: parent.width; wrapMode: Text.Wrap
          text: root.editing === "__reset__" ? "Restore default shortcuts?" : (Shortcuts.action(root.editing) || {}).title || "Change shortcut"
          color: Commons.Color.foreground
          font.family: Style.font.family; font.pixelSize: Style.font.title
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width; wrapMode: Text.Wrap
          text: root.editing === "__reset__" ? "Your custom bindings will be removed. Default keys will work again."
            : "Press your new shortcut. Esc cancels; Tab moves to the buttons."
          color: Commons.Color.foreground; opacity: 0.65
          font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
        }
        FocusScope {
          id: captureZone
          objectName: "shortcutCapture"
          visible: root.editing !== "__reset__"
          width: parent.width; height: Style.space(84)
          activeFocusOnTab: true
          Keys.onShortcutOverride: function(event) { if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab) event.accepted = true }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.cancel(); event.accepted = true; return }
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) return
            event.accepted = true
            if (root.pending || event.isAutoRepeat) return
            var sequence = Shortcuts.eventSequence(event)
            if (sequence) { root.candidate = sequence; root.error = "" }
          }
          Rectangle {
            anchors.fill: parent; radius: Style.cornerRadius
            color: Style.selectedFillFor(Commons.Color.foreground, Commons.Color.accent)
            border.width: 2; border.color: captureZone.activeFocus ? Commons.Color.accent : "transparent"
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WrapAnywhere
              text: root.candidate ? Shortcuts.label(root.candidate) : "Press keys…"
              color: Commons.Color.foreground
              font.family: Style.font.family; font.pixelSize: Style.font.title
            }
          }
        }
        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width; wrapMode: Text.Wrap
          text: root.error || root.candidateError || root.conflict
          color: Commons.Color.urgent
          font.family: Style.font.family; font.pixelSize: Style.font.caption
          Accessible.role: Accessible.AlertMessage
        }
        Flow {
          width: parent.width; spacing: Style.space(8)
          Ui.Button {
            id: resetConfirm
            objectName: "saveShortcut"
            text: root.pending ? "Saving…" : root.editing === "__reset__" ? "Restore defaults" : "Save shortcut"
            focusable: true; bordered: true; selected: true
            enabled: !root.pending && (root.editing === "__reset__" || !!root.candidate && !root.candidateError && !root.conflict)
            onClicked: root.editing === "__reset__" ? root.commit(({})) : root.save()
          }
          Ui.Button { text: "Cancel"; focusable: true; enabled: !root.pending; onClicked: root.cancel() }
          Ui.Button {
            text: "Remove binding"; focusable: true
            visible: root.editing !== "__reset__" && root.editingIndex < root.proposed.length
            enabled: !root.pending
            onClicked: root.remove()
          }
        }
    }
  }
}
