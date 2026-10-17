// Synthetic JPEG fixtures; no private files are read.
#include <QCoreApplication>
#include <QDir>
#include <QImage>
#include <QImageWriter>

int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  if (argc != 2)
    return 1;
  QImage image(900, 1600, QImage::Format_RGB32);
  for (int y = 0; y < image.height(); ++y)
    for (int x = 0; x < image.width(); ++x)
      image.setPixel(
          x, y,
          qRgb((x * 7 + y) % 256, (y * 3 + x) % 256, (x * 5 + y * 11) % 256));
  for (bool progressive : {false, true}) {
    QImageWriter writer(QDir(argv[1]).filePath(progressive ? "progressive.jpg"
                                                           : "baseline.jpg"),
                        "jpeg");
    writer.setProgressiveScanWrite(progressive);
    writer.setQuality(88);
    if (!writer.write(image))
      return 1;
  }
  return 0;
}
