"""Synthetic regression coverage for the follow-on privacy/robustness audit."""
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import test_backend as fixtures

core = fixtures.backend_module
ROOT = Path(__file__).resolve().parents[1]


class FollowupTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.BackendTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.addCleanup(self.fixture.tearDown)
        self.backend = self.fixture.backend
        self.root = self.fixture.root

    def test_group_subject_wins_over_sender_and_updates_after_rename(self):
        with sqlite3.connect(self.fixture.store / 'wacli.db') as db:
            db.execute("INSERT INTO groups(jid,name) VALUES('team@g.us','Synthetic group')")
            db.execute("UPDATE chats SET name='Synthetic sender' WHERE jid='team@g.us'")
        for subject in ('Synthetic group', 'Renamed synthetic group'):
            with sqlite3.connect(self.fixture.store / 'wacli.db') as db:
                db.execute("UPDATE groups SET name=? WHERE jid='team@g.us'", [subject])
            self.assertEqual(self.backend._chat('team@g.us')['name'], subject)
            rows = self.backend._account_chats(subject, 500, {'stores': {}})
            self.assertEqual(rows[0]['name'], subject)
            self.assertEqual(rows[0]['last_sender'], 'Sam')
        self.assertEqual(self.backend._chat('alex@s.whatsapp.net')['name'], 'Alex')

    def test_private_file_modes_during_copy_and_publication(self):
        target = self.root / 'saved.bin'
        source = self.fixture.document
        previous = os.umask(0)
        self.addCleanup(os.umask, previous)
        def copy(incoming, output):
            self.assertEqual(stat.S_IMODE(os.fstat(output.fileno()).st_mode), 0o600)
            output.write(incoming.read())
        with mock.patch.object(self.backend, 'download_media', return_value={'local_path': str(source)}), \
             mock.patch.object(core.shutil, 'copyfileobj', side_effect=copy):
            self.backend.save_media('team@g.us', 't2', str(target))
        self.assertEqual(target.read_bytes(), source.read_bytes())
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)

    def test_save_and_export_do_not_replace_racing_file_or_symlink(self):
        for export in (False, True):
            for link in (False, True):
                with self.subTest(export=export, symlink=link):
                    target = self.root / ('export.txt' if export else 'saved.bin')
                    target.unlink(missing_ok=True)
                    victim = self.root / 'victim'
                    victim.write_bytes(b'unchanged')
                    def race(*args):
                        if link:
                            target.symlink_to(victim)
                        else:
                            target.write_bytes(b'concurrent')
                        return {'local_path': str(self.fixture.document)} if not export else {'messages': [], 'has_more': False}
                    with mock.patch.object(self.backend, 'download_media' if not export else 'messages', side_effect=race), \
                         mock.patch.object(core, 'HOME', self.root):
                        with self.assertRaises(core.OmaWhatsAppError):
                            if export:
                                self.backend.export_chat('team@g.us', str(target))
                            else:
                                self.backend.save_media('team@g.us', 't2', str(target))
                    self.assertEqual(victim.read_bytes(), b'unchanged')
                    if not link:
                        self.assertEqual(target.read_bytes(), b'concurrent')
                    self.assertFalse(list(self.root.glob('.omawhatsapp-*.part')))

    def test_parent_replacement_cannot_redirect_export(self):
        parent = self.root / 'output'; parent.mkdir()
        moved = self.root / 'original'
        def page(*args):
            parent.rename(moved); parent.mkdir()
            return {'messages': [], 'has_more': False}
        with mock.patch.object(self.backend, 'messages', side_effect=page), mock.patch.object(core, 'HOME', self.root):
            with self.assertRaisesRegex(core.OmaWhatsAppError, 'folder changed'):
                self.backend.export_chat('team@g.us', str(parent / 'chat.txt'))
        self.assertFalse((parent / 'chat.txt').exists())
        self.assertFalse((moved / 'chat.txt').exists())
        self.assertFalse(list(moved.glob('.omawhatsapp-*.part')))

    def test_explicit_replace_and_failed_copy_cleanup(self):
        target = self.root / 'saved.bin'; target.write_bytes(b'old')
        with mock.patch.object(self.backend, 'download_media', return_value={'local_path': str(self.fixture.document)}):
            self.backend.save_media('team@g.us', 't2', str(target), replace=True)
        self.assertEqual(target.read_bytes(), b'pdf')
        with mock.patch.object(self.backend, 'download_media', side_effect=core.OmaWhatsAppError('synthetic failure')):
            with self.assertRaises(core.OmaWhatsAppError):
                self.backend.save_media('team@g.us', 't2', str(target), replace=True)
        self.assertEqual(target.read_bytes(), b'pdf')
        self.assertFalse(list(self.root.glob('.omawhatsapp-*.part')))

    def test_handoffs_are_private_single_use_expiring_and_purpose_bound(self):
        payload = {'account': 'synthetic-account', 'jid': 'synthetic@g.us'}
        token = self.backend.prepare_handoff('notification', payload)
        path = self.backend.state_dir / 'handoffs.json'
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertNotIn('synthetic', token)
        self.assertEqual(self.backend.consume_handoff(token, 'notification'), payload)
        with self.assertRaises(core.OmaWhatsAppError):
            self.backend.consume_handoff(token, 'notification')
        token = self.backend.prepare_handoff('link', {'name': 'synthetic'})
        with self.assertRaises(core.OmaWhatsAppError):
            self.backend.consume_handoff(token, 'notification')
        token = self.backend.prepare_handoff('link', {'name': 'synthetic'})
        with mock.patch.object(core.time, 'time', return_value=core.time.time() + 121):
            with self.assertRaises(core.OmaWhatsAppError):
                self.backend.consume_handoff(token, 'link')

    def test_sensitive_reads_presence_auth_and_metadata_use_private_process_input(self):
        binary = self.root / 'private-wacli'
        binary.write_text('#!' + sys.executable + '\n' + '''import json, os, sys
if sys.argv[1:] == ['--private-args-version']:
 print(json.dumps({'protocol': 1, 'max_bytes': 65536}))
else:
 data = json.load(sys.stdin)
 print(json.dumps({'success': True, 'data': {'input': data, 'argv': sys.argv[1:], 'env': list(os.environ.values())}}))
''')
        binary.chmod(0o700); self.backend.wacli = binary
        with mock.patch.object(self.backend, '_yield_active_sync', return_value=False), \
             mock.patch.object(self.backend, '_invalidate_doctor_cache'):
            value = self.backend.transport({'args': ['messages', 'search', 'SYNTHETIC_PRIVATE_QUERY']})['data']
            self.assertEqual(value['argv'], ['--private-args-stdin'])
            self.assertIn('SYNTHETIC_PRIVATE_QUERY', value['input'])
            self.assertNotIn('SYNTHETIC_PRIVATE_QUERY', value['env'])
            for args in (['--json', 'presence', 'subscribe', '--to', 'synthetic@s.whatsapp.net'],
                         ['--read-only', '--json', 'doctor'], ['--json', 'profile', 'picture-info', '--jid', 'synthetic@g.us']):
                value = json.loads(self.backend._run(args).stdout)['data']
                self.assertEqual(value['argv'], ['--private-args-stdin'])
                self.assertEqual(value['input'][-len(args):], args)
            seen = []
            def terminal(command, *, input_file):
                result = subprocess.run(command, stdin=input_file, text=True, capture_output=True, check=True)
                seen.append(json.loads(result.stdout)['data'])
                return result
            with mock.patch.object(self.backend, '_run_auth_terminal', side_effect=terminal):
                self.backend._transport_interactive(['auth'], authorization='interactive')
            self.assertEqual(seen[0]['argv'], ['--private-args-stdin'])
            self.assertIn('auth', seen[0]['input'])

    def test_mcp_rejects_bad_frames_then_processes_next_ping(self):
        valid = '{"jsonrpc":"2.0","id":7,"method":"ping"}\n'
        bad = [r'{"jsonrpc":"2.0","id":"\ud800","method":"ping"}',
               '{"jsonrpc":"2.0","id":[],"method":"ping"}',
               '[]', '[' + ','.join([valid.strip()] * 65) + ']',
               '{"jsonrpc":"2.0","id":1,"method":"ping","extra":' + '[' * 1100 + '0' + ']' * 1100 + '}',
               '{"jsonrpc":"2.0","id":1,"method":"ping","extra":"' + 'x' * (1024*1024) + '"}']
        for line in bad:
            with self.subTest(length=len(line)):
                result = subprocess.run([sys.executable, str(ROOT/'bin/omawhatsapp-mcp')], input=line+'\n'+valid,
                                        text=True, capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                replies = [json.loads(row) for row in result.stdout.splitlines()]
                self.assertIn('error', replies[0])
                self.assertEqual(replies[-1], {'jsonrpc':'2.0','id':7,'result':{}})


if __name__ == '__main__':
    unittest.main()
