import hashlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('prebuilt', str(ROOT/'scripts/install-private-wacli'))
spec = importlib.util.spec_from_loader(loader.name, loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)


class PrebuiltTests(unittest.TestCase):
    def bundle(self, root, binary=b'synthetic executable', unsafe=False):
        out=root/'archive.tar.gz'
        with tarfile.open(out,'w:gz') as tar:
            for name,data in [('wacli',binary),('LICENSE.wacli',b'license'),('wacli-provenance.json',b'{}')]:
                info=tarfile.TarInfo(name); info.size=len(data)
                if unsafe and name=='wacli': info.type=tarfile.SYMTYPE; info.linkname='/synthetic/outside'
                tar.addfile(info,io.BytesIO(data))
        return out,{'archive_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),
                    'binary_sha256':hashlib.sha256(binary).hexdigest()}

    def test_verified_install_and_replacement(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);archive,pin=self.bundle(root);target=root/'bin/wacli'
            m.install(m.verified_binary(archive,pin),target)
            self.assertEqual(target.read_bytes(),b'synthetic executable')
            self.assertEqual(target.stat().st_mode & 0o777,0o755)

    def test_tampered_archive_binary_and_symlink_are_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);archive,pin=self.bundle(root)
            for field in ('archive_sha256','binary_sha256'):
                with self.assertRaises(ValueError): m.verified_binary(archive,{**pin,field:'0'*64})
            archive,pin=self.bundle(root,unsafe=True)
            with self.assertRaises(ValueError): m.verified_binary(archive,pin)
            victim=root/'victim';victim.write_bytes(b'unchanged');target=root/'link';target.symlink_to(victim)
            with self.assertRaises(ValueError): m.install(b'new',target)
            self.assertEqual(victim.read_bytes(),b'unchanged')

    def test_pins_are_concrete_reviewed_values(self):
        pin=json.loads((ROOT/'dependencies/wacli-prebuilt.json').read_text())
        self.assertEqual(pin['archive_sha256'],'b1d15d9079a9c73c7fe587e8b9b8481298c31aecb41d84d97e88ecae0c8103bf')
        self.assertEqual(pin['binary_sha256'],'24abe6cc36425af4e25816b791a18d234f666ee863525d682c725745729304d0')
