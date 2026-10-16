// Synthetic regression: a clipboard offer must never be read by the account
// field merely being constructed, focused, or notified about a new offer.
#include <QGuiApplication>
#include <QClipboard>
#include <QMimeData>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQuickItem>
#include <QCoreApplication>
#include <QDebug>

class Offer final : public QMimeData {
public:
    static int reads;
    QStringList formats() const override { return {QStringLiteral("text/plain")}; }
protected:
    QVariant retrieveData(const QString &, QMetaType) const override {
        ++reads;
        // A real hostile Wayland source could stream forever here. Never
        // block the test: count entry into that payload-acquisition path.
        return QStringLiteral("synthetic-account");
    }
};
int Offer::reads = 0;

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    QQmlEngine engine;
    engine.addImportPath(QString::fromLocal8Bit(argv[1]) + "/tests/imports");
    QQmlComponent component(&engine);
    component.setData("import QtQuick\nimport qs.Ui as Ui\nUi.TextField {}", QUrl());
    QScopedPointer<QObject> baseline(component.create());
    if (!baseline) { qCritical() << component.errors(); return 1; }
    QGuiApplication::clipboard()->setMimeData(new Offer);
    QCoreApplication::processEvents();
    if (Offer::reads == 0) { qCritical() << "Control did not exercise native clipboard acquisition"; return 1; }
    baseline.reset();
    QGuiApplication::clipboard()->setMimeData(new Offer);
    Offer::reads = 0;
    component.loadUrl(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])
        + "/plugins/omawhatsapp/AccountNameField.qml"));
    QScopedPointer<QObject> field(component.create());
    if (!field) { qCritical() << component.errors(); return 1; }
    auto *item = qobject_cast<QQuickItem *>(field.data());
    item->forceActiveFocus();
    for (int i = 0; i < 5; ++i) {
        QGuiApplication::clipboard()->setMimeData(new Offer);
        QCoreApplication::processEvents();
        (void)field->property("canPaste");
    }
    if (Offer::reads != 0) { qCritical() << "Account field read clipboard without a paste" << Offer::reads; return 1; }
    if (!field->property("readOnly").toBool()) return 1;
    qInfo() << "Native clipboard probe passed: editable control reads offer; account field performs zero payload reads.";
}
