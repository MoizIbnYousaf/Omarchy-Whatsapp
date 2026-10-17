// SPDX-License-Identifier: MIT
// No untrusted image/container decoder runs in the desktop shell.
#include <QBuffer>
#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThreadPool>
#include <QtEndian>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <malloc.h>
#include <new>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

static bool limit(int which, rlim_t value) {
  rlimit r{value, value};
  return setrlimit(which, &r) == 0;
}
static QByteArray pngPixelsOnly(const QByteArray &bytes) {
  if (!bytes.startsWith(QByteArray::fromHex("89504e470d0a1a0a")))
    return bytes;
  QByteArray clean = bytes.left(8);
  qsizetype pos = 8;
  int chunks = 0;
  bool header = false, data = false;
  while (pos + 12 <= bytes.size() && ++chunks <= 65536) {
    quint32 size = qFromBigEndian<quint32>(bytes.constData() + pos);
    if (size > quint64(bytes.size() - pos - 12))
      return {};
    QByteArray type = bytes.mid(pos + 4, 4);
    if (!header && (type != "IHDR" || size != 13))
      return {};
    header = true;
    // Do not inflate any ancillary text, ICC, EXIF, XMP or animation chunks.
    if (type == "IHDR" || type == "PLTE" || type == "tRNS" || type == "IDAT" ||
        type == "IEND")
      clean.append(bytes.constData() + pos, qsizetype(size) + 12);
    else if (!(type[0] & 0x20))
      return {}; // Unknown critical format extension.
    if (type == "IDAT")
      data = true;
    if (type == "IEND")
      return size == 0 && data ? clean : QByteArray();
    pos += qsizetype(size) + 12;
  }
  return {};
}
static QByteArray sniffFormat(const QByteArray &bytes) {
  if (bytes.startsWith(QByteArray::fromHex("89504e470d0a1a0a")))
    return "png";
  if (bytes.startsWith(QByteArray::fromHex("ffd8ff")))
    return "jpeg";
  if (bytes.startsWith("GIF87a") || bytes.startsWith("GIF89a"))
    return "gif";
  if (bytes.size() >= 12 && bytes.startsWith("RIFF") &&
      bytes.mid(8, 4) == "WEBP")
    return "webp";
  if (bytes.startsWith("BM"))
    return "bmp";
  return {};
}
static int image(const QJsonObject &request) {
  const QString path = request["path"].toString();
  if (!QFileInfo(path).isAbsolute())
    return 1;
  int fd = open(QFile::encodeName(path).constData(),
                O_RDONLY | O_NONBLOCK | O_CLOEXEC);
  struct stat st{};
  if (fd < 0)
    return 1;
  if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size <= 0 ||
      st.st_size > 64 * 1024 * 1024) {
    close(fd);
    return 1;
  }
  QFile file;
  if (!file.open(fd, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) {
    close(fd);
    return 1;
  }
  QByteArray bytes = file.read(64 * 1024 * 1024 + 1);
  if (bytes.size() > 64 * 1024 * 1024)
    return 1;
  bytes = pngPixelsOnly(bytes);
  if (bytes.isEmpty())
    return 1;
  const auto format = sniffFormat(bytes);
  if (format.isEmpty())
    return 1;
  QBuffer input(&bytes);
  input.open(QIODevice::ReadOnly);
  // Never probe unrelated installed plugins (HEIF, AVIF, JXL, etc.). Even a
  // rejected probe may load their codec libraries into this limited process.
  QImageReader reader(&input, format);
  reader.setAutoDetectImageFormat(false);
  reader.setDecideFormatFromContent(false);
  QImageReader::setAllocationLimit(96);
  reader.setAutoTransform(true);
  QSize original = reader.size();
  if (original.isEmpty() ||
      qint64(original.width()) * original.height() > 32 * 1024 * 1024)
    return 1;
  int edge = qBound(32, request["edge"].toInt(1024), 1024);
  QSize scaled = original;
  if (original.width() > edge || original.height() > edge)
    scaled = original.scaled(edge, edge, Qt::KeepAspectRatio);
  reader.setScaledSize(scaled);
  int count = qMax(1, reader.imageCount());
  int index = request["frame"].toInt();
  if (count > 1000 || index < 0 || index >= count)
    return 1;
  QImage frame;
  for (int i = 0; i <= index; i++) {
    frame = reader.read();
    if (frame.isNull())
      return 1;
  }
  if (frame.width() > edge || frame.height() > edge)
    frame =
        frame.scaled(edge, edge, Qt::KeepAspectRatio, Qt::SmoothTransformation);
  frame = frame.convertToFormat(QImage::Format_RGBA8888);
  if (frame.isNull() || frame.sizeInBytes() > 4 * 1024 * 1024)
    return 1;
  QJsonObject header{{"w", frame.width()},
                     {"h", frame.height()},
                     {"sw", original.width()},
                     {"sh", original.height()},
                     {"count", count},
                     {"index", index},
                     {"delay", qBound(40, reader.nextImageDelay(), 60000)}};
  QByteArray line = QJsonDocument(header).toJson(QJsonDocument::Compact) + '\n';
  if (fwrite(line.constData(), 1, line.size(), stdout) != size_t(line.size()))
    return 1;
  // RGBA bytes only: no compressed metadata or image parser in the parent.
  for (int y = 0; y < frame.height(); y++)
    if (fwrite(frame.constScanLine(y), 1, frame.width() * 4, stdout) !=
        size_t(frame.width() * 4))
      return 1;
  return fflush(stdout) == 0 ? 0 : 1;
}
static int media(const QJsonObject &request) {
  const QString path = request["path"].toString(),
                output = request["output"].toString();
  if (!QFileInfo(path).isAbsolute() || !QFileInfo(output).isAbsolute())
    return 1;
  int in = open(QFile::encodeName(path).constData(),
                O_RDONLY | O_NONBLOCK | O_CLOEXEC);
  int out = open(QFile::encodeName(output).constData(), O_RDWR | O_CLOEXEC);
  struct stat a{}, b{};
  if (in < 0 || out < 0 || fstat(in, &a) || fstat(out, &b) ||
      !S_ISREG(a.st_mode) || !S_ISREG(b.st_mode) || a.st_size <= 0 ||
      a.st_size > 512 * 1024 * 1024 || b.st_uid != getuid() ||
      (b.st_mode & 077) || (a.st_dev == b.st_dev && a.st_ino == b.st_ino))
    return 1;
  // Duplicate above all source FDs before assigning the fixed protocol FDs.
  int input = fcntl(in, F_DUPFD_CLOEXEC, 10),
      dest = fcntl(out, F_DUPFD_CLOEXEC, 10);
  if (input < 0 || dest < 0 || dup2(input, 3) < 0 || dup2(dest, 4) < 0)
    return 1;
  close(input);
  close(dest);
  for (int i = 5; i < 64; i++)
    close(i);
  bool audio = request["kind"].toString() == "audio";
  QList<QByteArray> args = {
      "/usr/bin/ffmpeg",
      "-v",
      "error",
      "-nostdin",
      "-y",
      "-max_alloc",
      "67108864",
      "-threads",
      "1",
      "-filter_threads",
      "1",
      "-filter_complex_threads",
      "1",
      "-protocol_whitelist",
      "file,pipe",
      "-format_whitelist",
      "mov,matroska,webm,mp3,ogg,wav,flac,aac,amr,avi,mpegts,mpeg",
      "-max_pixels",
      "16777216",
      "-i",
      "/proc/self/fd/3",
      "-map_metadata",
      "-1",
      "-map_chapters",
      "-1",
      "-sn",
      "-dn"};
  if (audio)
    args << "-map" << "0:a:0" << "-vn" << "-c:a" << "pcm_s16le" << "-ar"
         << "48000" << "-ac" << "2" << "-f" << "wav";
  else
    args << "-map" << "0:v:0" << "-map" << "0:a:0?" << "-vf"
         << "scale=w=min(1280\\,iw):h=min(720\\,ih):force_original_aspect_"
            "ratio=decrease:force_divisible_by=2"
         << "-r" << "24" << "-c:v" << "mpeg4" << "-q:v" << "5" << "-threads"
         << "1"
         << "-c:a" << "aac" << "-b:a" << "96k" << "-ar" << "48000" << "-ac"
         << "2" << "-f" << "mp4";
  args << "/proc/self/fd/4";
  QList<char *> argv;
  for (auto &arg : args)
    argv.append(arg.data());
  argv.append(nullptr);
  // This applies to the new process image after exec; mallopt below applies
  // to the current image decoder. Avoid per-thread 64-MiB arena reservations.
  if (setenv("MALLOC_ARENA_MAX", "1", 1))
    return 1;
  // The only media paths in ffmpeg argv are the fixed inherited descriptors.
  execv(argv[0], argv.data());
  return 1;
}
int main(int argc, char **argv) {
  // Bound glibc arena reservations before Qt can start any decoding threads.
  if (!mallopt(M_ARENA_MAX, 1))
    return 1;
  try {
    bool av = argc == 2 && QByteArray(argv[1]) == "--media";
    const pid_t parent = getppid();
    if (prctl(PR_SET_PDEATHSIG, SIGKILL) || getppid() != parent ||
        prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) || !limit(RLIMIT_CORE, 0) ||
        // FFmpeg maps its linked codec libraries before decoding. This is a
        // total address-space bound; -max_alloc separately limits each
        // allocation.
        !limit(RLIMIT_AS, (av ? 1024 : 384) * 1024 * 1024) ||
        !limit(RLIMIT_CPU, av ? 30 : 5) ||
        !limit(RLIMIT_FSIZE, 128 * 1024 * 1024) || !limit(RLIMIT_NOFILE, 64))
      return 1;
    alarm(av ? 60 : 6);
    QCoreApplication app(argc, argv);
    QThreadPool::globalInstance()->setMaxThreadCount(2);
    QFile input;
    if (!input.open(stdin, QIODevice::ReadOnly))
      return 1;
    QByteArray data = input.read(16385);
    if (data.size() > 16384)
      return 1;
    QJsonParseError error;
    auto document = QJsonDocument::fromJson(data, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
      return 1;
    return av ? media(document.object()) : image(document.object());
  } catch (const std::bad_alloc &) {
    // A rejected allocation is an unavailable preview, not a crash report.
    return 1;
  }
}
