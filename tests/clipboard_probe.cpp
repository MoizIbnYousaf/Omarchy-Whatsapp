// Synthetic in-process offers; never touches the desktop clipboard.
#include <QGuiApplication>
#include <QClipboard>
#include <QMimeData>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQuickItem>
#include <QInputMethodEvent>
#include <QKeyEvent>
#include <QDebug>
class Offer final : public QMimeData {
public:
 static int reads;
 QStringList formats() const override { return {QStringLiteral("text/plain")}; }
protected:
 QVariant retrieveData(const QString &, QMetaType) const override {
   ++reads; return QStringLiteral("synthetic");
 }
};
int Offer::reads = 0;
int main(int argc, char **argv) {
 QGuiApplication app(argc, argv);
 QQmlEngine engine;
 engine.addImportPath(QString::fromLocal8Bit(argv[1])+"/tests/imports");
 QQmlComponent control(&engine);
 control.setData("import QtQuick\nTextInput {}", QUrl());
 QScopedPointer<QObject> baseline(control.create());
 QGuiApplication::clipboard()->setMimeData(new Offer);
 QCoreApplication::processEvents();
 if (!baseline || Offer::reads == 0) return 1;
 baseline.reset();
 // Prove the service's runtime bootstrap registers the module before the
 // application files are loaded, without modifying the engine import path.
 QQmlComponent bootstrap(&engine);
 auto path=QUrl::fromLocalFile(QString::fromLocal8Bit(argv[2])+"/OmaWhatsApp/Inputs").toString();
 bootstrap.setData(("import QtQuick\nimport \""+path+"\" as Native\nQtObject {}").toUtf8(),QUrl());
 QScopedPointer<QObject> registration(bootstrap.create());
 if (!registration) { qCritical()<<bootstrap.errors(); return 2; }
 for (const auto &type : {"TextField", "TextArea", "TextEdit"}) {
   Offer::reads=0;
   QGuiApplication::clipboard()->setMimeData(new Offer);
   QQmlComponent c(&engine);
   c.setData((QString("import QtQuick\nimport OmaWhatsApp.Inputs as Native\nNative.")+type+" {}").toUtf8(),QUrl());
   QScopedPointer<QObject> editor(c.create());
   if (!editor) { qCritical()<<c.errors(); return 3; }
   auto item=qobject_cast<QQuickItem *>(editor.data());
   item->forceActiveFocus();
   for (int i=0;i<5;i++) {
     QGuiApplication::clipboard()->setMimeData(new Offer);
     QCoreApplication::processEvents();
     (void)editor->property("canPaste");
     editor->setProperty("readOnly",true);
     editor->setProperty("readOnly",false);
   }
   // International input-method commits continue through Qt's native engine.
   QInputMethodEvent ime;
   ime.setCommitString(QString::fromUtf8("Grüße 世界"));
   QCoreApplication::sendEvent(editor.data(),&ime);
   if (editor->property("text").toString()!=QString::fromUtf8("Grüße 世界")) {
     qCritical()<<"IME regression"<<type<<editor->property("text"); return 4;
   }
   if (Offer::reads!=0) { qCritical()<<"Unexpected clipboard read"<<type<<Offer::reads; return 5; }
 }
 qInfo()<<"All native editor classes: zero implicit clipboard reads; read-only transitions and IME pass.";
}
