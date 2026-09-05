import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "MaintenanceSettings"
  property int calls: 0
  Component {
    id: settings
    Oma.MaintenanceSettings {
      width: 320
      foreground: "white"
      accent: "green"
      fontFamily: "sans"
      service: ({settingsWriting: false, checkUpdatesOnLaunch: false,
        accountOperations: {avatarBusy: false, linkBusy: false, statusMessage: "",
          refreshAvatars: function() { testCase.calls++ }}})
      updates: ({message: "Check for updates", release: null, busy: false, online: true})
    }
  }
  function test_photo_refresh_is_in_settings_and_demo_is_disabled() {
    calls = 0
    var item = createTemporaryObject(settings, testCase)
    verify(item !== null)
    var refresh = findChild(item, "refreshChatPhotos")
    verify(refresh.enabled)
    refresh.clicked()
    compare(calls, 1)
    item.demoMode = true
    verify(!refresh.enabled)
    verify(!findChild(item, "checkUpdatesOnLaunch").enabled)
  }
  function test_busy_and_linking_disable_photo_refresh() {
    var item = createTemporaryObject(settings, testCase)
    item.service = {accountOperations: {avatarBusy: true, linkBusy: false, statusMessage: "Refreshing"}}
    verify(!findChild(item, "refreshChatPhotos").enabled)
    item.service = {accountOperations: {avatarBusy: false, linkBusy: true, statusMessage: "Linking"}}
    verify(!findChild(item, "refreshChatPhotos").enabled)
  }
}
