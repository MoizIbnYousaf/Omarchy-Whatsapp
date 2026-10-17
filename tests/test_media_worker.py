"""Synthetic compressed-metadata, malformed media and worker resource regressions."""
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import time
import unittest
import zlib
from concurrent.futures import ThreadPoolExecutor
import shlex

ROOT=Path(__file__).resolve().parents[1]

def chunk(kind,data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)

def png(extra=b'',width=1,height=1):
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))+extra+chunk(b'IDAT',zlib.compress(b'\0\x11\x22\x33\xff'))+chunk(b'IEND',b'')

def bomb():
    # 192 distinct 1-MiB chunks stay below libpng per-chunk limits.
    compressor=zlib.compressobj()
    compressed=b''.join(compressor.compress(b'A'*65536) for _ in range(16))+compressor.flush()
    return png(b''.join(chunk(b'zTXt',('text'+str(i)).encode()+b'\0\0'+compressed) for i in range(192)))

class MediaWorker(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        imports=subprocess.check_output([str(ROOT/'scripts/build-inputs')],text=True).strip()
        cls.worker=Path(imports)/'OmaWhatsApp/Inputs/omawa-media-worker'
        cls.fixture_dir=tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.fixture_dir.cleanup)
        cls.photos=Path(cls.fixture_dir.name)
        flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','Qt6Gui'],text=True))
        subprocess.run(['g++','-std=c++17','-fPIC',str(ROOT/'tests/photo_fixtures.cpp'),'-o',str(cls.photos/'generate'),*flags],check=True,timeout=45)
        subprocess.run([str(cls.photos/'generate'),str(cls.photos)],check=True,timeout=10)
    def run_image(self,data,**fields):
        with tempfile.NamedTemporaryFile() as image:
            image.write(data);image.flush()
            return subprocess.run([str(self.worker)],input=json.dumps({'path':image.name,**fields}).encode(),capture_output=True,timeout=9)
    def test_compressed_text_is_never_expanded(self):
        data=bomb();self.assertLess(len(data),210000)
        result=self.run_image(data)
        self.assertEqual(result.returncode,0,result.stderr)
        header,pixels=result.stdout.split(b'\n',1)
        self.assertEqual((json.loads(header)['w'],pixels),(1,b'\x11\x22\x33\xff'))
    def test_other_metadata_and_many_chunks(self):
        compressed=zlib.compress(b'A'*1024*1024)
        for kind,data in [(b'iTXt',b'name\0\x01\0\0\0'+compressed),(b'iCCP',b'profile\0\0'+compressed),(b'eXIf',b'A'*1024),(b'tEXt',b'k\0'+b'A'*1024)]:
            with self.subTest(kind=kind):
                self.assertEqual(self.run_image(png(chunk(kind,data)*100)).returncode,0)
    def test_bad_chunks_dimensions_and_vectors_fail_closed(self):
        for data in [png(width=2**30,height=2**30),b'\x89PNG\r\n\x1a\n'+struct.pack('>I',2**32-1)+b'IDAT',b'<svg xmlns="http://www.w3.org/2000/svg"/>',b'not an image']:
            with self.subTest(data=data[:12]):self.assertNotEqual(self.run_image(data).returncode,0)
    def test_all_supported_formats_and_lying_signatures(self):
        import base64
        from write_media_fixtures import FIXTURES
        for data in [png(),(self.photos/'baseline.jpg').read_bytes(),
                     base64.b64decode(FIXTURES['multi.gif']),base64.b64decode(FIXTURES['multi.webp']),
                     b'BM'+struct.pack('<IHHI',58,0,0,54)+struct.pack('<IiiHHIIiiII',40,1,1,1,24,0,4,0,0,0,0)+b'\x11\x22\x33\0']:
            with self.subTest(header=data[:8]):
                result=self.run_image(data)
                self.assertEqual(result.returncode,0,result.stderr)
        for data in [b'\xff\xd8\xffnot-jpeg',b'GIF89anot-gif',b'RIFF\0\0\0\0WEBPnot-webp',
                     b'BMnot-bmp',b'II*\0not-tiff',b'\0\0\0\x0cjP  \r\n\x87\n']:
            with self.subTest(header=data[:8]):
                result=self.run_image(data)
                self.assertEqual(result.returncode,1,result.stderr)
    def test_repeated_phone_sized_photos_under_default_allocator_environment(self):
        env=dict(os.environ)
        env.pop('MALLOC_ARENA_MAX',None);env.pop('GLIBC_TUNABLES',None)
        requests=[(name,edge) for _ in range(12) for name in ('baseline.jpg','progressive.jpg') for edge in (256,1024)]
        def decode(item):
            name,edge=item
            result=subprocess.run([str(self.worker)],input=json.dumps({'path':str(self.photos/name),'edge':edge}).encode(),capture_output=True,env=env,timeout=8)
            self.assertEqual(result.returncode,0,result.stderr)
            header,pixels=result.stdout.split(b'\n',1);header=json.loads(header)
            self.assertEqual(len(pixels),header['w']*header['h']*4)
        with ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(decode,requests))
    def test_jpeg_does_not_load_unrelated_decoder_plugins(self):
        with subprocess.Popen([str(self.worker)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE) as process:
            process.stdin.write(json.dumps({'path':str(self.photos/'progressive.jpg'),'edge':1024}).encode())
            process.stdin.close();process.stdin=None
            try:
                prefix=process.stdout.read(1)
                self.assertTrue(prefix)
                maps=Path(f'/proc/{process.pid}/maps').read_text()
                self.assertIn('libqjpeg',maps)
                self.assertNotRegex(maps,r'libq(?:heif|avif|jxl|exr|tiff|jp2)')
                output,error=process.communicate(timeout=8)
                self.assertEqual(process.returncode,0,error)
                self.assertGreater(len(output),1024)
            finally:
                if process.poll() is None:process.kill();process.communicate()
    def test_fifo_is_rejected_without_waiting(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'fifo';os.mkfifo(path)
            start=time.monotonic()
            result=subprocess.run([str(self.worker)],input=json.dumps({'path':str(path)}).encode(),capture_output=True,timeout=2)
            self.assertNotEqual(result.returncode,0);self.assertLess(time.monotonic()-start,2)
    def test_request_and_image_file_caps(self):
        result=subprocess.run([str(self.worker)],input=b' '*16385,capture_output=True,timeout=2)
        self.assertNotEqual(result.returncode,0)
        with tempfile.NamedTemporaryFile() as file:
            file.truncate(64*1024*1024+1)
            result=subprocess.run([str(self.worker)],input=json.dumps({'path':file.name}).encode(),capture_output=True,timeout=2)
            self.assertNotEqual(result.returncode,0)
    def test_audio_is_regenerated_without_metadata(self):
        import wave
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/'source.wav'
            with wave.open(str(source),'wb') as sound:
                sound.setnchannels(1);sound.setsampwidth(2);sound.setframerate(8000);sound.writeframes(b'\0\0'*800)
            descriptor=os.memfd_create('synthetic-preview');os.fchmod(descriptor,0o600)
            try:
                result=subprocess.run([str(self.worker),'--media'],input=json.dumps({'path':str(source),'output':f'/proc/{os.getpid()}/fd/{descriptor}','kind':'audio'}).encode(),capture_output=True,timeout=10)
                self.assertEqual(result.returncode,0,result.stderr)
                os.lseek(descriptor,0,0)
                with os.fdopen(os.dup(descriptor),'rb') as data, wave.open(data,'rb') as decoded:
                    self.assertEqual(decoded.getnchannels(),2)
                    self.assertEqual(decoded.getframerate(),48000)
            finally:os.close(descriptor)
    def test_limits_are_live_before_any_request(self):
        with subprocess.Popen([str(self.worker)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE) as process:
            try:
                time.sleep(.05)
                limits=Path(f'/proc/{process.pid}/limits').read_text()
                self.assertRegex(limits,r'Max address space\s+402653184\s+402653184')
                self.assertRegex(limits,r'Max cpu time\s+5\s+5')
                self.assertRegex(limits,r'Max core file size\s+0\s+0')
                self.assertNotIn(b'path',Path(f'/proc/{process.pid}/cmdline').read_bytes())
            finally:process.kill();process.communicate()
    def test_media_limits_are_live_before_any_request(self):
        with subprocess.Popen([str(self.worker),'--media'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE) as process:
            try:
                time.sleep(.05)
                limits=Path(f'/proc/{process.pid}/limits').read_text()
                self.assertRegex(limits,r'Max address space\s+1073741824\s+1073741824')
                self.assertRegex(limits,r'Max cpu time\s+30\s+30')
                self.assertRegex(limits,r'Max file size\s+134217728\s+134217728')
                self.assertRegex(limits,r'Max core file size\s+0\s+0')
            finally:process.kill();process.communicate()
