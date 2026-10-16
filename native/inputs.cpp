// SPDX-License-Identifier: MIT
// This module is compiled against the installed Qt version. It keeps native
// editing/IME behavior but owns every clipboard read; no global Qt patches.
#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <QClipboard>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QInputMethodEvent>
#include <QMouseEvent>
#include <QProcess>
#include <QTimer>
#include <QStringDecoder>
#include <QtQuick/private/qquicktextinput_p_p.h>
#include <QtQuick/private/qquicktextedit_p_p.h>
#include <QtQuick/private/qquicktextcontrol_p.h>
#include <QtQuick/private/qquicktextcontrol_p_p.h>
#include <functional>
#include <QQuickPaintedItem>
#include <QImageReader>
#include <QPainter>
#include <QFileInfo>
#include <memory>

namespace {
constexpr qsizetype byteLimit = 1024 * 1024;

// One explicit request, one immutable editing target. No clipboard-change
// subscription, MIME probe, native paste, automatic retry, or shell command.
class PasteRequest : public QObject {
public:
    QProcess process;
    QTimer deadline;
    QByteArray bytes;
    bool failed = false;
    std::function<void(QString)> complete;
    std::function<void(QString)> reject;
    PasteRequest(QObject *owner) : QObject(owner) {
        deadline.setSingleShot(true);
        deadline.setInterval(3000);
        connect(&deadline, &QTimer::timeout, this, [this] { fail("The clipboard did not respond."); });
        connect(&process, &QProcess::readyReadStandardOutput, this, [this] { drain(); });
        connect(&process, &QProcess::readyReadStandardError, this, [this] {
            process.readAllStandardError(); // Never reflect clipboard producer output.
        });
        connect(&process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
            fail("The clipboard could not be read.");
        });
        connect(&process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
            deadline.stop();
            drain();
            if (!failed && (code != 0 || status != QProcess::NormalExit))
                fail("The clipboard has no text to paste.");
            if (!failed) {
                QStringDecoder decoder(QStringDecoder::Utf8);
                QString value = decoder(bytes);
                if (decoder.hasError()) fail("The clipboard text is not valid UTF-8.");
                else complete(value);
            }
            deleteLater();
        });
    }
    ~PasteRequest() override {
        deadline.stop();
        disconnect(&process, nullptr, this, nullptr);
        if (process.state() != QProcess::NotRunning) {
            process.kill();
            process.waitForFinished(100);
        }
    }
    void drain() {
        QByteArray chunk = process.readAllStandardOutput();
        if (failed) return;
        if (chunk.size() > byteLimit - bytes.size()) {
            fail("The clipboard text is too large (maximum 1 MB).");
            return;
        }
        bytes += chunk;
    }
    void fail(const QString &message) {
        if (failed) return;
        failed = true;
        deadline.stop();
        bytes.clear();
        process.kill();
        if (reject) reject(message);
        deleteLater();
    }
    void start(const QString &program = QStringLiteral("/usr/bin/wl-paste")) {
        deadline.start();
        process.setProgram(program);
        process.setArguments({"--no-newline", "--type", "text/plain"});
        process.start(QIODevice::ReadOnly);
    }
};

void seal(QQuickTextInput *item) {
    QObject::disconnect(QGuiApplication::clipboard(), nullptr, item, nullptr);
    auto d = static_cast<QQuickTextInputPrivate *>(QQuickItemPrivate::get(item));
    d->canPaste = false;
    d->canPasteValid = true;
}
void seal(QQuickTextEdit *item) {
    QObject::disconnect(QGuiApplication::clipboard(), nullptr, item, nullptr);
    auto d = static_cast<QQuickTextEditPrivate *>(QQuickItemPrivate::get(item));
    d->canPaste = false;
    d->canPasteValid = true;
}
// Qt's public setters call the eager clipboard slot synchronously. Update the
// editing flag without that call, then emit its ordinary notification. The
// private API is deliberately rebuilt for the host Qt and covered natively.
void setReadOnlySafely(QQuickTextInput *item, bool value) {
    if (item->isReadOnly() == value) return;
    auto d = static_cast<QQuickTextInputPrivate *>(QQuickItemPrivate::get(item));
    d->m_readOnly = value;
    item->setFlag(QQuickItem::ItemAcceptsInputMethod, !value);
    item->setCursorVisible(!value && item->hasActiveFocus());
    item->update();
    emit item->readOnlyChanged(value);
}
void setReadOnlySafely(QQuickTextEdit *item, bool value) {
    if (item->isReadOnly() == value) return;
    auto d = static_cast<QQuickTextEditPrivate *>(QQuickItemPrivate::get(item));
    auto control = static_cast<QQuickTextControlPrivate *>(QObjectPrivate::get(d->control));
    if (value) control->interactionFlags &= ~Qt::TextEditable;
    else control->interactionFlags |= Qt::TextEditable;
    item->setFlag(QQuickItem::ItemAcceptsInputMethod, !value);
    item->setCursorVisible(!value && item->hasActiveFocus());
    item->update();
    emit item->readOnlyChanged(value);
}

template<class Base> class Editor : public Base {
public:
    QPointer<PasteRequest> pending;
    quint64 revision = 0;
    std::function<void(QString)> pasteError;
    Editor(QQuickItem *parent = nullptr) : Base(parent) {
        seal(this); // Constructor-time: before QML properties or incubation.
        auto changed = [this] { ++revision; cancelPaste(); };
        QObject::connect(this, &Base::textChanged, this, changed);
        QObject::connect(this, &Base::selectionStartChanged, this, changed);
        QObject::connect(this, &Base::cursorPositionChanged, this, changed);
        QObject::connect(this, &Base::preeditTextChanged, this, changed);
        QObject::connect(this, &Base::selectionEndChanged, this, changed);
        QObject::connect(this, &QQuickItem::activeFocusChanged, this, changed);
        QObject::connect(this, &Base::readOnlyChanged, this, changed);
    }
    void cancelPaste() {
        if (pending) { auto p = pending; pending = nullptr; delete p; }
    }
    void safeReadOnly(bool value) {
        setReadOnlySafely(this, value);
        this->updateInputMethod(Qt::ImEnabled);
    }
    bool safeCanPaste() const { return !this->isReadOnly(); }
    void safePaste() {
        if (this->isReadOnly() || pending) return;
        const auto captured = revision;
        auto p = new PasteRequest(this);
        pending = p;
        p->complete = [this, captured, p](const QString &text) {
            if (pending != p || revision != captured || this->isReadOnly()) return;
            pending = nullptr; // Mutation signals must not delete the callback owner.
            QInputMethodEvent commit;
            commit.setCommitString(text);
            QCoreApplication::sendEvent(this, &commit);
        };
        p->reject = [this, p](const QString &message) {
            if (pending != p) return;
            pending = nullptr;
            if (pasteError) pasteError(message);
        };
        p->start();
    }
    bool event(QEvent *event) override {
        // Let QML Keys run first. Native key handling itself is overridden
        // below, so application-specific paste shortcuts retain precedence.
        if (event->type() == QEvent::DragEnter || event->type() == QEvent::DragMove
            || event->type() == QEvent::Drop) {
            event->ignore(); return false;
        }
        return Base::event(event);
    }
    void keyPressEvent(QKeyEvent *event) override {
        if (event->matches(QKeySequence::Paste)) {
            safePaste(); event->accept(); return;
        }
        Base::keyPressEvent(event);
    }
    void mouseReleaseEvent(QMouseEvent *event) override {
        if (event->button() == Qt::MiddleButton) { event->accept(); return; }
        Base::mouseReleaseEvent(event);
    }
    void mousePressEvent(QMouseEvent *event) override {
        if (event->button() == Qt::MiddleButton) { event->accept(); return; }
        Base::mousePressEvent(event);
    }
};
} // namespace

class SafeTextField : public Editor<QQuickTextInput> {
 Q_OBJECT
 QML_NAMED_ELEMENT(TextField)
 QML_ADDED_IN_VERSION(6, 0)
 Q_PROPERTY(qreal implicitHeight READ implicitHeight WRITE setImplicitHeight NOTIFY implicitHeightChanged)
 Q_PROPERTY(qreal implicitWidth READ implicitWidth WRITE setImplicitWidth NOTIFY implicitWidthChanged)
 Q_PROPERTY(qreal padding READ padding WRITE setPadding NOTIFY paddingChanged)
 Q_PROPERTY(qreal leftPadding READ leftPadding WRITE setLeftPadding NOTIFY leftPaddingChanged)
 Q_PROPERTY(qreal rightPadding READ rightPadding WRITE setRightPadding NOTIFY rightPaddingChanged)
 Q_PROPERTY(qreal topPadding READ topPadding WRITE setTopPadding NOTIFY topPaddingChanged)
 Q_PROPERTY(qreal bottomPadding READ bottomPadding WRITE setBottomPadding NOTIFY bottomPaddingChanged)
 Q_PROPERTY(bool canPaste READ safeCanPaste NOTIFY clipboardCapabilityChanged)
 Q_PROPERTY(bool readOnly READ isReadOnly WRITE safeReadOnly NOTIFY readOnlyChanged)
public:
 SafeTextField(QQuickItem *p=nullptr):Editor<QQuickTextInput>(p) {
   pasteError=[this](QString e){emit pasteFailed(e);};
   connect(this,&QQuickTextInput::readOnlyChanged,this,&SafeTextField::clipboardCapabilityChanged);
   connect(this,&QQuickTextInput::editingFinished,this,&SafeTextField::editingFinished);
 }
 Q_INVOKABLE void paste() { safePaste(); }
 Q_INVOKABLE void cancelClipboardPaste() { cancelPaste(); }
signals:
 void editingFinished();
 void pasteFailed(QString message);
 void clipboardCapabilityChanged();
};
class SafeTextArea : public Editor<QQuickTextEdit> {
 Q_OBJECT
 QML_NAMED_ELEMENT(TextArea)
 QML_ADDED_IN_VERSION(6, 0)
 Q_PROPERTY(qreal implicitHeight READ implicitHeight WRITE setImplicitHeight NOTIFY implicitHeightChanged)
 Q_PROPERTY(qreal implicitWidth READ implicitWidth WRITE setImplicitWidth NOTIFY implicitWidthChanged)
 Q_PROPERTY(qreal padding READ padding WRITE setPadding NOTIFY paddingChanged)
 Q_PROPERTY(qreal leftPadding READ leftPadding WRITE setLeftPadding NOTIFY leftPaddingChanged)
 Q_PROPERTY(qreal rightPadding READ rightPadding WRITE setRightPadding NOTIFY rightPaddingChanged)
 Q_PROPERTY(qreal topPadding READ topPadding WRITE setTopPadding NOTIFY topPaddingChanged)
 Q_PROPERTY(qreal bottomPadding READ bottomPadding WRITE setBottomPadding NOTIFY bottomPaddingChanged)
 Q_PROPERTY(bool canPaste READ safeCanPaste NOTIFY clipboardCapabilityChanged)
 Q_PROPERTY(bool readOnly READ isReadOnly WRITE safeReadOnly NOTIFY readOnlyChanged)
public:
 SafeTextArea(QQuickItem *p=nullptr):Editor<QQuickTextEdit>(p) {
   pasteError=[this](QString e){emit pasteFailed(e);};
   connect(this,&QQuickTextEdit::readOnlyChanged,this,&SafeTextArea::clipboardCapabilityChanged);
 }
 Q_INVOKABLE void paste() { safePaste(); }
 Q_INVOKABLE void cancelClipboardPaste() { cancelPaste(); }
signals:
 void pasteFailed(QString message);
 void clipboardCapabilityChanged();
};
class SafeTextEdit : public Editor<QQuickTextEdit> {
 Q_OBJECT
 QML_NAMED_ELEMENT(TextEdit)
 QML_ADDED_IN_VERSION(6, 0)
 Q_PROPERTY(qreal implicitHeight READ implicitHeight WRITE setImplicitHeight NOTIFY implicitHeightChanged)
 Q_PROPERTY(qreal implicitWidth READ implicitWidth WRITE setImplicitWidth NOTIFY implicitWidthChanged)
 Q_PROPERTY(qreal padding READ padding WRITE setPadding NOTIFY paddingChanged)
 Q_PROPERTY(qreal leftPadding READ leftPadding WRITE setLeftPadding NOTIFY leftPaddingChanged)
 Q_PROPERTY(qreal rightPadding READ rightPadding WRITE setRightPadding NOTIFY rightPaddingChanged)
 Q_PROPERTY(qreal topPadding READ topPadding WRITE setTopPadding NOTIFY topPaddingChanged)
 Q_PROPERTY(qreal bottomPadding READ bottomPadding WRITE setBottomPadding NOTIFY bottomPaddingChanged)
 Q_PROPERTY(bool canPaste READ safeCanPaste NOTIFY clipboardCapabilityChanged)
 Q_PROPERTY(bool readOnly READ isReadOnly WRITE safeReadOnly NOTIFY readOnlyChanged)
public:
 SafeTextEdit(QQuickItem *p=nullptr):Editor<QQuickTextEdit>(p) {
   pasteError=[this](QString e){emit pasteFailed(e);};
   connect(this,&QQuickTextEdit::readOnlyChanged,this,&SafeTextEdit::clipboardCapabilityChanged);
 }
 Q_INVOKABLE void paste() { safePaste(); }
 Q_INVOKABLE void cancelClipboardPaste() { cancelPaste(); }
signals:
 void pasteFailed(QString message);
 void clipboardCapabilityChanged();
};

// Own frame advancement rather than QQuickAnimatedImage/QMovie's recursive
// finished-signal restart path. Every decode is separated by an event-loop turn.
class SafeAnimatedImage : public QQuickPaintedItem {
 Q_OBJECT
 QML_NAMED_ELEMENT(AnimatedImage)
 QML_ADDED_IN_VERSION(6, 0)
 Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
 Q_PROPERTY(bool mipmap READ mipmap WRITE setMipmap)
 Q_PROPERTY(bool playing READ playing WRITE setPlaying NOTIFY playingChanged)
 Q_PROPERTY(bool cache MEMBER cache)
 Q_PROPERTY(bool asynchronous MEMBER asynchronous)
 Q_PROPERTY(int fillMode MEMBER fillMode NOTIFY fillModeChanged)
 Q_PROPERTY(int status READ status NOTIFY statusChanged)
 Q_PROPERTY(int frameCount READ frameCount NOTIFY frameCountChanged)
 Q_PROPERTY(int currentFrame READ currentFrame NOTIFY currentFrameChanged)
 Q_PROPERTY(QSize sourceSize READ sourceSize NOTIFY sourceSizeChanged)
 QUrl url;
 std::unique_ptr<QImageReader> reader;
 QImage frame;
 QTimer advance;
 bool requested = true, failed = false;
 int state = 0, count = 0, index = -1, delay = 100;
 QSize dimensions;
 quint64 generation=0;
 void setStatus(int value) { if(state!=value){state=value;emit statusChanged();} }
 void fail() { failed=true;advance.stop();reader.reset();frame={};update();setStatus(3); }
 bool openReader() {
   const auto token=generation;
   // Quickshell resolves bundled demo assets through its local qs: scheme.
   const QString path=url.isLocalFile()?url.toLocalFile():
     (url.scheme()==QStringLiteral("qs") && url.host().isEmpty()?url.path():QString());
   if(path.isEmpty() || !QFileInfo(path).isAbsolute())return false;
   QFileInfo info(path);
   if(!info.isFile() || info.size()>64*1024*1024) return false;
   auto nextReader=std::make_unique<QImageReader>(path);
   nextReader->setAutoTransform(true);
   auto size=nextReader->size();
   if(size.isEmpty() || qint64(size.width())*size.height()>64*1024*1024) return false;
   if(size.width()>2048 || size.height()>2048)
     nextReader->setScaledSize(size.scaled(2048,2048,Qt::KeepAspectRatio));
   int nextCount=qMax(1,nextReader->imageCount());
   bool sizeChanged=dimensions!=size, countChanged=count!=nextCount;
   dimensions=size;count=nextCount;index=-1;reader=std::move(nextReader);
   if(sizeChanged)emit sourceSizeChanged();
   if(generation!=token)return false;
   if(countChanged)emit frameCountChanged();
   return generation==token;
 }
 void decode() {
   const auto token=generation;
   if(!reader || failed) return;
   QImage next=reader->read();
   if(next.isNull()){fail();return;}
   frame=next; ++index; delay=qBound(20,reader->nextImageDelay(),60000);
   emit currentFrameChanged();
   if(generation!=token)return;
   update();setStatus(1);
   if(generation!=token)return;
   if(requested && count>1) advance.start(delay);
 }
 void tick() {
   const auto token=generation;
   if(!requested || failed || !reader) return;
   if(index+1>=count && !openReader()) {
     if(generation==token)fail();
     return;
   }
   if(generation==token)decode();
 }
public:
 bool cache=true, asynchronous=true;
 int fillMode=1;
 explicit SafeAnimatedImage(QQuickItem *parent=nullptr):QQuickPaintedItem(parent){
   advance.setSingleShot(true);
   connect(&advance,&QTimer::timeout,this,[this]{tick();});
 }
 QUrl source() const{return url;}
 void setSource(const QUrl &value){
   if(url==value)return;
   const auto token=++generation;
   url=value;advance.stop();reader.reset();frame={};failed=false;index=-1;
   if(count){count=0;emit frameCountChanged();}
   if(generation!=token)return;
   if(!dimensions.isEmpty()){dimensions={};emit sourceSizeChanged();}
   if(generation!=token)return;
   update();emit sourceChanged();
   if(generation!=token)return;
   if(url.isEmpty()){setStatus(0);return;}
   setStatus(2);
   // Coalesce source replacements; never decode in a QML property setter.
   QTimer::singleShot(0,this,[this,token]{
     if(generation!=token)return;
     if(!openReader()){if(generation==token)fail();return;}
     if(generation==token)decode();
   });
 }
 bool playing()const{return requested;}
 void setPlaying(bool value){
   if(requested==value)return;
   requested=value;emit playingChanged();
   if(!value)advance.stop();
   else if(reader && !failed && count>1)advance.start(delay);
 }
 int status()const{return state;}
 int frameCount()const{return count;}
 int currentFrame()const{return index;}
 QSize sourceSize()const{return dimensions;}
 void paint(QPainter *p)override{
   if(frame.isNull())return;
   p->setRenderHint(QPainter::SmoothPixmapTransform,smooth());
   QSizeF size=frame.size();
   if(fillMode==1)size.scale(boundingRect().size(),Qt::KeepAspectRatio);
   else if(fillMode==2)size.scale(boundingRect().size(),Qt::KeepAspectRatioByExpanding);
   else size=boundingRect().size();
   QRectF target(QPointF((width()-size.width())/2,(height()-size.height())/2),size);
   p->setClipRect(boundingRect());p->drawImage(target,frame);
 }
signals:
 void sourceChanged();void playingChanged();void fillModeChanged();
 void statusChanged();void frameCountChanged();void currentFrameChanged();void sourceSizeChanged();
};

class InputsPlugin : public QQmlExtensionPlugin {
 Q_OBJECT
 Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
 void registerTypes(const char *) override {
   qmlRegisterTypesAndRevisions<SafeTextField, SafeTextArea, SafeTextEdit, SafeAnimatedImage>("OmaWhatsApp.Inputs", 6);
 }
};
#include "inputs.moc"
