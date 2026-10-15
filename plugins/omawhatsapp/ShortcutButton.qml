import QtQuick
import qs.Ui as Ui

// Omarchy's visual button with explicit semantics for assistive technology.
Ui.Button {
  id: root
  focusable: true
  opacity: enabled ? 1 : 0.4
  Accessible.role: Accessible.Button
  Accessible.name: text
  Accessible.description: tooltipText
  Accessible.onPressAction: if (enabled) root.clicked()
}
