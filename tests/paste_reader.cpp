// Exercise the actual native bounded reader with disposable producers.
#include "../native/inputs.cpp"
#include <QTemporaryDir>
#include <QFile>
#include <QEventLoop>
#include <QElapsedTimer>
int main(int argc,char **argv) {
 QCoreApplication app(argc,argv);
 QTemporaryDir dir;
 auto run=[&](const QByteArray &body,bool success,int minimumMs=0) {
   QString path=dir.filePath("producer");
   QFile file(path); if(!file.open(QIODevice::WriteOnly))return false;
   file.write("#!/usr/bin/python3\n"+body);file.close();
   file.setPermissions(QFile::ReadOwner|QFile::WriteOwner|QFile::ExeOwner);
   QEventLoop loop;
   bool passed=false,finished=false;
   auto request=new PasteRequest(&app);
   request->complete=[&](QString value){passed=success&&value==QString::fromUtf8("Grüße 世界");finished=true;loop.quit();};
   request->reject=[&](QString){passed=!success;finished=true;loop.quit();};
   QTimer::singleShot(5000,&loop,&QEventLoop::quit);
   QElapsedTimer elapsed;elapsed.start();request->start(path);loop.exec();
   return finished&&passed&&elapsed.elapsed()>=minimumMs&&elapsed.elapsed()<4500;
 };
 if(!run("import os\nos.write(1, 'Grüße 世界'.encode())\n",true))return 1;
 if(!run("import os\nwhile True: os.write(1,b'x'*65536)\n",false))return 2;
 if(!run("import time\ntime.sleep(30)\n",false,2500))return 3;
 if(!run("raise SystemExit(2)\n",false))return 4;
 QCoreApplication::sendPostedEvents(nullptr,QEvent::DeferredDelete);
 return 0;
}
