import QtQuick
import OmaWhatsApp.Inputs as Native

// Loaded only after native bootstrap, never while constructing the service.
Item {
  property alias source: nativeSource.source
  property alias kind: nativeSource.kind
  readonly property alias status: nativeSource.status
  readonly property alias safeSource: nativeSource.safeSource
  Native.MediaSource { id: nativeSource }
}
