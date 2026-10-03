import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// L235: the first run explains what OmaWhatsApp is and links the phone from
// the window, instead of an empty list that says "Loading…".
TestCase {
  id: testCase
  name: "Onboarding"
  width: 1100
  height: 760
  visible: true
  when: windowShown

  Component {
    id: operationsStub
    QtObject {
      property bool linkBusy: false
      property bool avatarBusy: false
      property string statusMessage: ""
      property string linked: ""
      function linkMainAccount(name) { linked = name; linkBusy = true
        statusMessage = "Scan the QR code in the terminal with your phone"; return true }
    }
  }
  Component {
    id: serviceStub
    QtObject {
      property bool wacliInstalled: true
      property bool anyAuthenticated: false
      property string defaultAccountName: "primary"
      property var accountOperations: null
      property bool needsSetup: false
      property var setupConflicts: []
      property bool wacliTooOld: false
      property string wacliVersion: ""
      property bool setupAgents: false
      property bool originalPluginEnabled: false
      property bool setupWriting: false
      property var setupCalls: []
      property int wacliInstalls: 0
      function runSetup(agents, replaceOriginal) {
        setupCalls = setupCalls.concat([[agents, replaceOriginal]]); return true }
      function installWacli() { wacliInstalls += 1; return true }
    }
  }
  Component { id: viewComponent; Oma.OnboardingView { width: 900; height: 700 } }
  Component { id: appComponent; Oma.App { width: 1100; height: 760; demoMode: true; opened: true } }

  function test_the_welcome_links_the_main_account_from_the_window() {
    var service = createTemporaryObject(serviceStub, testCase)
    service.accountOperations = createTemporaryObject(operationsStub, testCase)
    var view = createTemporaryObject(viewComponent, testCase, { service: service })
    compare(findChild(view, "onboardingTitle").text, "Link your WhatsApp")
    verify(findChild(view, "onboardingSteps").visible)
    verify(!findChild(view, "onboardingWacliMissing").visible)
    verify(view.startLink())
    compare(service.accountOperations.linked, "primary", "the main account, by its own name")
    verify(view.linking)
    verify(findChild(view, "onboardingStatus").text.indexOf("QR code") > 0)
  }

  function test_without_wacli_it_says_what_to_install() {
    var service = createTemporaryObject(serviceStub, testCase)
    service.wacliInstalled = false
    var view = createTemporaryObject(viewComponent, testCase, { service: service })
    verify(findChild(view, "onboardingWacliMissing").visible)
    verify(!findChild(view, "onboardingSteps").visible)
    compare(findChild(view, "onboardingTitle").text, "One more piece first")
  }

  function test_without_wacli_it_offers_the_package() {
    var service = createTemporaryObject(serviceStub, testCase)
    service.wacliInstalled = false
    var view = createTemporaryObject(viewComponent, testCase, { service: service })
    compare(findChild(view, "onboardingWacliCommand").text, "omarchy pkg aur add wacli-bin")
    var button = findChild(view, "onboardingInstallWacli")
    mouseClick(button, button.width / 2, button.height / 2)
    compare(service.wacliInstalls, 1, "the package installs in a terminal the user confirms")
  }

  function test_a_wacli_too_old_asks_for_an_update() {
    var service = createTemporaryObject(serviceStub, testCase)
    service.wacliTooOld = true
    service.wacliVersion = "0.16.9"
    var view = createTemporaryObject(viewComponent, testCase, { service: service })
    verify(findChild(view, "onboardingWacliMissing").visible)
    verify(!findChild(view, "onboardingSteps").visible)
    compare(findChild(view, "onboardingWacliCommand").text, "omarchy pkg aur add wacli-bin")
  }

  function test_setup_is_asked_once_with_agents_off_by_default() {
    var service = createTemporaryObject(serviceStub, testCase)
    service.needsSetup = true
    var view = createTemporaryObject(viewComponent, testCase, { service: service })
    compare(findChild(view, "onboardingTitle").text, "Set it up on this computer")
    verify(findChild(view, "onboardingSetup").visible)
    verify(!findChild(view, "onboardingSteps").visible, "linking waits for the setup")
    verify(!findChild(view, "onboardingReplaceOriginal").visible)
    verify(!findChild(view, "onboardingAgents").checked, "agent access needs a yes")
    var button = findChild(view, "onboardingSetUp")
    mouseClick(button, button.width / 2, button.height / 2)
    compare(service.setupCalls, [[false, false]], "Set up alone adds no agent instructions")
  }

  function test_turning_agents_on_before_setting_up_asks_for_them() {
    var service = createTemporaryObject(serviceStub, testCase)
    service.needsSetup = true
    var view = createTemporaryObject(viewComponent, testCase, { service: service })
    var agents = findChild(view, "onboardingAgents")
    agents.toggled()
    verify(view.allowAgents)
    var button = findChild(view, "onboardingSetUp")
    mouseClick(button, button.width / 2, button.height / 2)
    compare(service.setupCalls, [[true, false]])
  }

  function test_paths_of_something_else_are_shown_and_block_the_setup() {
    var service = createTemporaryObject(serviceStub, testCase)
    service.needsSetup = true
    service.setupConflicts = ["/home/u/.local/bin/omawhatsapp"]
    var view = createTemporaryObject(viewComponent, testCase, { service: service })
    var conflicts = findChild(view, "onboardingConflicts")
    verify(conflicts.visible)
    verify(conflicts.text.indexOf("/home/u/.local/bin/omawhatsapp") >= 0)
    var button = findChild(view, "onboardingSetUp")
    verify(button.blocked)
    mouseClick(button, button.width / 2, button.height / 2)
    compare(service.setupCalls, [], "nothing runs until they are moved away")
    service.setupConflicts = []
    mouseClick(button, button.width / 2, button.height / 2)
    compare(service.setupCalls.length, 1)
  }

  function test_the_original_omawhatsapp_is_turned_off_only_with_the_setup() {
    var service = createTemporaryObject(serviceStub, testCase)
    service.needsSetup = true
    service.originalPluginEnabled = true
    var view = createTemporaryObject(viewComponent, testCase, { service: service })
    verify(findChild(view, "onboardingReplaceOriginal").visible)
    var button = findChild(view, "onboardingSetUp")
    mouseClick(button, button.width / 2, button.height / 2)
    compare(service.setupCalls, [[false, true]])
  }

  function test_the_app_shows_it_until_something_is_linked() {
    var app = createTemporaryObject(appComponent, testCase)
    var view = findChild(app, "onboardingView")
    verify(!view.visible, "a linked account goes straight to the chats")
    app.open(JSON.stringify({ demo: true, onboarding: true }))
    verify(view.visible)
  }
}
