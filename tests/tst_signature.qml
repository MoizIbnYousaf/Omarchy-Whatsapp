import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma
import "../plugins/omawhatsapp/ComposerModel.js" as ComposerModel

// The owner's idea (L210): one signature per account, off by default, the
// name in bold at the top (or at the end), shown in the message box with a
// one-message skip, on texts and captions only.
TestCase {
  id: testCase
  name: "Signature"
  width: 1100
  height: 760
  visible: true
  when: windowShown

  readonly property var target: ({ account: "work", jid: "synthetic@s.whatsapp.net" })
  readonly property var signed: ({ enabled: true, name: "Atos", position: "top" })

  Component { id: serviceComponent; Oma.Service {} }
  Component { id: appComponent; Oma.App { width: 1100; height: 760; demoMode: true; opened: true } }
  Component { id: settingsComponent; Oma.SettingsView { width: 900; height: 700; demoMode: true } }

  function createService(signature) {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.ready = true
    service.statusReady = true
    service.statusAccount = "work"
    service.offlineMode = false
    service.readOnReply = false
    service.selectedChatAccount = "work"
    service.selectedChatJid = target.jid
    service.accounts = [{ account: "work", label: "work", signature: signature },
                        { account: "home", label: "home" }]
    return service
  }

  function test_the_signature_goes_at_the_top_or_the_end_once() {
    compare(ComposerModel.signedText("Chego às 10h", signed), "*Atos:*\nChego às 10h")
    compare(ComposerModel.signedText("*Atos:*\nChego", signed), "*Atos:*\nChego", "never twice")
    var bottom = { enabled: true, name: "Atos", position: "bottom" }
    compare(ComposerModel.signedText("Chego", bottom), "Chego\n\n— *Atos*")
    compare(ComposerModel.signedText("Chego\n\n— *Atos*", bottom), "Chego\n\n— *Atos*")
    compare(ComposerModel.signedText("Chego", { enabled: false, name: "Atos" }), "Chego", "off by default")
    compare(ComposerModel.signedText("   ", signed), "   ", "nothing to sign")
    var accounts = [{ account: "work", signature: signed }, { account: "home" }]
    compare(ComposerModel.signatureOf(accounts, "work").name, "Atos")
    verify(!ComposerModel.signatureOf(accounts, "home").enabled, "each account has its own")
  }

  function test_the_service_signs_texts_unless_told_to_skip() {
    var service = createService(signed)
    var process = findChild(service, "writeProcess")
    verify(service.sendText(target, "on my way", "", [], "app"))
    compare(JSON.parse(process.payload).text, "*Atos:*\non my way")
    compare(service.selectedMessages[0].text, "*Atos:*\non my way", "the bubble shows what goes out")
    process.running = false
    process.exited(0)
    verify(service.sendText(target, "no signature here", "", [], "app", false))
    compare(JSON.parse(process.payload).text, "no signature here")
  }

  function test_captions_are_signed_and_bare_files_are_not() {
    var service = createService(signed)
    var process = findChild(service, "writeProcess")
    verify(service.sendFilesReply(target, ["/tmp/omaw-synthetic.png"], "the plan", "", "app"))
    compare(JSON.parse(process.payload).caption, "*Atos:*\nthe plan")
    process.running = false
    process.exited(0)
    verify(service.sendFilesReply(target, ["/tmp/omaw-synthetic.png"], "", "", "app"))
    compare(JSON.parse(process.payload).caption, "", "no caption, no signature")
  }

  function test_an_account_without_a_signature_sends_as_typed() {
    var service = createService({ enabled: false, name: "", position: "top" })
    var process = findChild(service, "writeProcess")
    verify(service.sendText(target, "plain", "", [], "app"))
    compare(JSON.parse(process.payload).text, "plain")
  }

  function test_the_message_box_shows_it_and_skips_it_once() {
    var app = createTemporaryObject(appComponent, testCase)
    var strip = findChild(app, "composerSignature")
    verify(!strip.visible, "off by default")
    app.demoSignature = signed
    verify(strip.visible)
    verify(findChild(app, "composerSignatureLabel").text.indexOf("Signed as Atos") >= 0)
    var composer = findChild(app, "composerInput")
    composer.text = "hello"
    app.sendDraft()
    compare(app.demoItems[0].text, "*Atos:*\nhello")
    app.signatureSkipped = true
    verify(findChild(app, "composerSignatureLabel").text.indexOf("without your signature") >= 0)
    composer.text = "just this once"
    app.sendDraft()
    compare(app.demoItems[0].text, "just this once")
    verify(!app.signatureSkipped, "the skip is for one message")
  }

  function test_settings_turn_it_on_with_a_name_and_a_place() {
    var app = createTemporaryObject(appComponent, testCase)
    var view = createTemporaryObject(settingsComponent, testCase, { app: app })
    view.openSection("chats")
    wait(0)
    var name = findChild(view, "signatureName")
    var toggle = findChild(view, "setting-signature")
    verify(name !== null && toggle !== null)
    verify(!toggle.checked)
    toggle.toggled()
    verify(!app.demoSignature.enabled, "no name yet: nothing is turned on")
    name.text = "Atos"
    name.editingFinished()
    compare(app.demoSignature.name, "Atos")
    toggle.toggled()
    verify(app.demoSignature.enabled)
    findChild(view, "signaturePosition-bottom").children[1] // the label
    view.saveSignature({ position: "bottom" })
    compare(app.demoSignature.position, "bottom")
    verify(findChild(view, "signaturePreview").visible)
  }
}
