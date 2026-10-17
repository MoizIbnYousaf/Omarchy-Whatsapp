// SPDX-License-Identifier: MIT
#pragma once
#include <QCoreApplication>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>
#include <QProcessEnvironment>
#include <QtQmlIntegration/qqmlintegration.h>
#include <dlfcn.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

namespace MediaBoundary {
constexpr qint64 frameBudget = 32 * 1024 * 1024;
inline qint64 retained = 0, mediaRetained = 0;
inline int imageJobs = 0, mediaJobs = 0;
class Job;
inline QList<QPointer<Job>> pending;
inline void locateWorkerAnchor() {}
inline QString workerPath() {
  Dl_info info{};
  if (!dladdr(reinterpret_cast<void *>(&locateWorkerAnchor), &info))
    return {};
  return QFileInfo(QString::fromLocal8Bit(info.dli_fname)).absolutePath() +
         "/omawa-media-worker";
}
void pump();
class Job : public QObject {
public:
  QProcess process;
  QTimer timer;
  QByteArray output;
  QJsonObject request;
  bool av, running = false, finished = false, bad = false;
  std::function<void(bool, const QByteArray &)> complete;
  Job(QObject *owner, QJsonObject data, bool media)
      : QObject(owner), request(data), av(media) {
    timer.setSingleShot(true);
    connect(&timer, &QTimer::timeout, this, [this] {
      bad = true;
      if (running)
        process.kill();
      else
        finish(false);
    });
    connect(&process, &QProcess::started, this, [this] {
      process.write(QJsonDocument(request).toJson(QJsonDocument::Compact));
      process.closeWriteChannel();
    });
    connect(&process, &QProcess::readyReadStandardOutput, this,
            [this] { drain(); });
    // Never copy hostile decoder diagnostics into the shell/logs.
    process.setStandardErrorFile(QProcess::nullDevice());
    connect(&process, &QProcess::errorOccurred, this,
            [this](QProcess::ProcessError e) {
              if (e == QProcess::FailedToStart)
                finish(false);
            });
    connect(&process, &QProcess::finished, this,
            [this](int code, QProcess::ExitStatus status) {
              drain();
              finish(!bad && code == 0 && status == QProcess::NormalExit);
            });
  }
  ~Job() override {
    disconnect(&process, nullptr, this, nullptr);
    timer.stop();
    if (process.state() != QProcess::NotRunning) {
      process.kill();
      process.waitForFinished(100);
    }
    if (running) {
      (av ? mediaJobs : imageJobs)--;
      running = false;
    }
    for (auto it = pending.begin(); it != pending.end();)
      if (!*it || *it == this)
        it = pending.erase(it);
      else
        ++it;
    QTimer::singleShot(0, QCoreApplication::instance(), [] { pump(); });
  }
  void drain() {
    while (process.bytesAvailable() > 0) {
      auto part = process.read(qMin<qint64>(65536, process.bytesAvailable()));
      if (part.size() > 4 * 1024 * 1024 + 512 - output.size()) {
        bad = true;
        process.kill();
        output.clear();
        return;
      }
      output += part;
    }
  }
  void finish(bool ok) {
    if (finished)
      return;
    finished = true;
    timer.stop();
    pending.removeAll(QPointer<Job>(this));
    if (running) {
      (av ? mediaJobs : imageJobs)--;
      running = false;
    }
    auto callback = std::move(complete);
    QPointer<Job> guard = this;
    if (callback)
      callback(ok, output);
    if (guard)
      deleteLater();
    pump();
  }
  void start() {
    running = true;
    (av ? mediaJobs : imageJobs)++;
    auto env = QProcessEnvironment::systemEnvironment();
    for (auto key : env.keys())
      if (key.startsWith("QT_") || key.startsWith("QML"))
        env.remove(key);
    process.setProcessEnvironment(env);
    process.setProgram(workerPath());
    process.setArguments(av ? QStringList{"--media"} : QStringList{});
    timer.start(av ? 62000 : 7000);
    process.start();
  }
  void submit() {
    if (pending.size() >= 128) {
      QTimer::singleShot(0, this, [this] { finish(false); });
      return;
    }
    timer.start(av ? 70000 : 10000); // Bound queue wait as well as active work.
    pending.append(this);
    pump();
  }
};
inline void pump() {
  for (auto it = pending.begin(); it != pending.end();) {
    auto job = *it;
    if (!job) {
      it = pending.erase(it);
      continue;
    }
    if (job->av ? mediaJobs >= 1 : imageJobs >= 2) {
      ++it;
      continue;
    }
    it = pending.erase(it);
    job->start();
  }
}
inline QString localPath(const QUrl &url) {
  QString path =
      url.isLocalFile()
          ? url.toLocalFile()
          : (url.scheme() == "qs" && url.host().isEmpty() ? url.path()
                                                          : QString());
  return QFileInfo(path).isAbsolute() && path.size() <= 4096 ? path : QString();
}
} // namespace MediaBoundary

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
  Q_PROPERTY(QSize sourceSize READ sourceSize WRITE setSourceSize NOTIFY
                 sourceSizeChanged)
  QUrl url;
  QImage frame;
  QTimer advance;
  QPointer<MediaBoundary::Job> job;
  bool requested = true;
  int state = 0, count = 0, index = -1, delay = 100;
  QSize dimensions, requestedSize;
  quint64 generation = 0;
  void setStatus(int s) {
    if (state != s) {
      state = s;
      emit statusChanged();
    }
  }
  void clearFrame() {
    MediaBoundary::retained -= frame.sizeInBytes();
    frame = {};
    update();
  }
  void cancel() {
    advance.stop();
    if (job) {
      delete job;
      job = nullptr;
    }
  }
  void fail() {
    cancel();
    clearFrame();
    setStatus(3);
  }
  void decode(int next) {
    auto path = MediaBoundary::localPath(url);
    if (path.isEmpty()) {
      fail();
      return;
    }
    const auto token = generation;
    int edge = qBound(32,
                      requestedSize.isEmpty()
                          ? int(qMax(width(), height()) * 2)
                          : qMax(requestedSize.width(), requestedSize.height()),
                      1024);
    job = new MediaBoundary::Job(
        this, {{"path", path}, {"frame", next}, {"edge", edge}}, false);
    job->complete = [this, token](bool ok, const QByteArray &bytes) {
      job = nullptr;
      if (generation != token)
        return;
      int nl = bytes.indexOf('\n');
      if (!ok || nl < 0 || nl > 511) {
        fail();
        return;
      }
      auto h = QJsonDocument::fromJson(bytes.left(nl)).object();
      int w = h["w"].toInt(), height = h["h"].toInt(), n = h["count"].toInt(),
          i = h["index"].toInt();
      int sw = h["sw"].toInt(), sh = h["sh"].toInt();
      qint64 size = qint64(w) * height * 4;
      if (w < 1 || height < 1 || w > 1024 || height > 1024 ||
          size != bytes.size() - nl - 1 || n < 1 || n > 1000 || i < 0 ||
          i >= n || sw < 1 || sh < 1 || qint64(sw) * sh > 32 * 1024 * 1024 ||
          MediaBoundary::retained - frame.sizeInBytes() + size >
              MediaBoundary::frameBudget) {
        fail();
        return;
      }
      QImage nextFrame(
          reinterpret_cast<const uchar *>(bytes.constData() + nl + 1), w,
          height, w * 4, QImage::Format_RGBA8888);
      clearFrame();
      frame = nextFrame.copy();
      MediaBoundary::retained += frame.sizeInBytes();
      QSize s(sw, sh);
      if (dimensions != s) {
        dimensions = s;
        emit sourceSizeChanged();
      }
      if (generation != token)
        return;
      if (count != n) {
        count = n;
        emit frameCountChanged();
      }
      if (generation != token)
        return;
      index = i;
      delay = qBound(40, h["delay"].toInt(), 60000);
      emit currentFrameChanged();
      if (generation != token)
        return;
      update();
      setStatus(1);
      if (generation != token)
        return;
      if (requested && isVisible() && count > 1)
        advance.start(delay);
    };
    job->submit();
  }

public:
  bool cache = true, asynchronous = true;
  int fillMode = 1;
  explicit SafeAnimatedImage(QQuickItem *parent = nullptr)
      : QQuickPaintedItem(parent) {
    advance.setSingleShot(true);
    connect(&advance, &QTimer::timeout, this, [this] {
      if (!job && requested && isVisible())
        decode((index + 1) % qMax(count, 1));
    });
    connect(this, &QQuickItem::visibleChanged, this, [this] {
      if (!isVisible())
        advance.stop();
      else if (requested && count > 1 && !job)
        advance.start(delay);
    });
  }
  ~SafeAnimatedImage() override {
    cancel();
    clearFrame();
  }
  QUrl source() const { return url; }
  void setSource(const QUrl &value) {
    if (url == value)
      return;
    auto token = ++generation;
    cancel();
    clearFrame();
    url = value;
    index = -1;
    if (count) {
      count = 0;
      emit frameCountChanged();
    }
    if (generation != token)
      return;
    if (!dimensions.isEmpty()) {
      dimensions = {};
      emit sourceSizeChanged();
    }
    if (generation != token)
      return;
    emit sourceChanged();
    if (generation != token)
      return;
    if (url.isEmpty()) {
      setStatus(0);
      return;
    }
    setStatus(2);
    QTimer::singleShot(0, this, [this, token] {
      if (generation == token)
        decode(0);
    });
  }
  bool playing() const { return requested; }
  void setPlaying(bool value) {
    if (requested == value)
      return;
    requested = value;
    emit playingChanged();
    if (!value)
      advance.stop();
    else if (count > 1 && !job)
      advance.start(delay);
  }
  int status() const { return state; }
  int frameCount() const { return count; }
  int currentFrame() const { return index; }
  QSize sourceSize() const {
    return dimensions.isEmpty() ? requestedSize : dimensions;
  }
  void setSourceSize(QSize size) { requestedSize = size; }
  void paint(QPainter *p) override {
    if (frame.isNull())
      return;
    p->setRenderHint(QPainter::SmoothPixmapTransform, smooth());
    QSizeF size = frame.size();
    if (fillMode == 1)
      size.scale(boundingRect().size(), Qt::KeepAspectRatio);
    else if (fillMode == 2)
      size.scale(boundingRect().size(), Qt::KeepAspectRatioByExpanding);
    else
      size = boundingRect().size();
    QRectF target(
        QPointF((width() - size.width()) / 2, (height() - size.height()) / 2),
        size);
    p->setClipRect(boundingRect());
    p->drawImage(target, frame);
  }
signals:
  void sourceChanged();
  void playingChanged();
  void fillModeChanged();
  void statusChanged();
  void frameCountChanged();
  void currentFrameChanged();
  void sourceSizeChanged();
};

class SafeMediaSource : public QObject {
  Q_OBJECT
  QML_NAMED_ELEMENT(MediaSource)
  QML_ADDED_IN_VERSION(6, 0)
  Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
  Q_PROPERTY(QUrl safeSource READ safeSource NOTIFY safeSourceChanged)
  Q_PROPERTY(QString kind MEMBER kind)
  Q_PROPERTY(int status READ status NOTIFY statusChanged)
  QUrl original, safe;
  int state = 0;
  quint64 generation = 0;
  QPointer<MediaBoundary::Job> job;
  int outputFd = -1;
  qint64 outputBytes = 0;
  void clearOutput() {
    if (outputFd >= 0) {
      close(outputFd);
      outputFd = -1;
    }
    MediaBoundary::mediaRetained -= outputBytes;
    outputBytes = 0;
  }
  void setStatus(int s) {
    if (state != s) {
      state = s;
      emit statusChanged();
    }
  }

public:
  QString kind = "audio";
  explicit SafeMediaSource(QObject *parent = nullptr) : QObject(parent) {}
  ~SafeMediaSource() override {
    if (job)
      delete job;
    clearOutput();
  }
  QUrl source() const { return original; }
  QUrl safeSource() const { return safe; }
  int status() const { return state; }
  void setSource(QUrl value) {
    if (value == original)
      return;
    const auto token = ++generation;
    if (job) {
      delete job;
      job = nullptr;
    }
    original = value;
    safe = QUrl();
    emit safeSourceChanged();
    if (generation != token)
      return;
    clearOutput();
    emit sourceChanged();
    if (generation != token)
      return;
    if (value.isEmpty()) {
      setStatus(0);
      return;
    }
    auto path = MediaBoundary::localPath(value);
    if (path.isEmpty()) {
      setStatus(3);
      return;
    }
    outputFd = memfd_create("omawa-preview", MFD_CLOEXEC);
    if (outputFd < 0 || fchmod(outputFd, 0600)) {
      clearOutput();
      setStatus(3);
      return;
    }
    setStatus(2);
    if (generation != token)
      return;
    QString destination = QString("/proc/%1/fd/%2").arg(getpid()).arg(outputFd);
    job = new MediaBoundary::Job(
        this, {{"path", path}, {"output", destination}, {"kind", kind}}, true);
    job->complete = [this, token](bool ok, const QByteArray &) {
      if (generation != token)
        return;
      job = nullptr;
      struct stat metadata{};
      if (!ok || outputFd < 0 || fstat(outputFd, &metadata) ||
          metadata.st_size <= 0 ||
          MediaBoundary::mediaRetained + metadata.st_size > 128 * 1024 * 1024) {
        clearOutput();
        setStatus(3);
        return;
      }
      outputBytes = metadata.st_size;
      MediaBoundary::mediaRetained += outputBytes;
      safe = QUrl::fromLocalFile(QString("/proc/self/fd/%1").arg(outputFd));
      emit safeSourceChanged();
      if (generation == token)
        setStatus(1);
    };
    job->submit();
  }
signals:
  void sourceChanged();
  void safeSourceChanged();
  void statusChanged();
};
