// Synthetic baseline only. NEVER run this probe inside the desktop shell.
#include <QCoreApplication>
#include <QFile>
#include <QImageReader>
#include <cstdio>
#include <sys/resource.h>
int main(int argc, char **argv) {
  rlimit mem{384 * 1024 * 1024, 384 * 1024 * 1024}, cpu{5, 5}, core{0, 0};
  if (setrlimit(RLIMIT_AS, &mem) || setrlimit(RLIMIT_CPU, &cpu) ||
      setrlimit(RLIMIT_CORE, &core))
    return 2;
  QCoreApplication app(argc, argv);
  QImageReader reader(QString::fromLocal8Bit(argv[1]));
  auto image = reader.read();
  struct rusage usage{};
  getrusage(RUSAGE_SELF, &usage);
  QFile status("/proc/self/status");
  if (!status.open(QIODevice::ReadOnly))
    return 2;
  auto text = status.readAll();
  for (auto line : text.split('\n'))
    if (line.startsWith("VmHWM:") || line.startsWith("VmPeak:"))
      puts(line.constData());
  return image.isNull() ? 1 : 0;
}
