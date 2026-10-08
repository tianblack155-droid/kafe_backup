"""Production-process smoke tests without cloud credentials or DB writes."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent


def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def request(base, path):
    try:
        with urllib.request.urlopen(base + path, timeout=4) as res:
            return res.status, res.read().decode()
    except urllib.error.HTTPError as err:
        return err.code, err.read().decode()


def exercise(command, env, cases):
    p = port()
    # Remove inherited cloud credentials: these tests must not contact Supabase.
    clean = {k: v for k, v in os.environ.items()
             if not k.startswith(('NUXT_', 'DATABASE_URL', 'APP_ENV', 'HOST', 'PORT', 'NITRO_'))}
    clean.update(env)
    clean.update(PORT=str(p), HOST='127.0.0.1')
    base = f'http://127.0.0.1:{p}'
    with tempfile.TemporaryFile() as logs:
        proc = subprocess.Popen(command, cwd=ROOT, env=clean, stdout=logs, stderr=logs)
        try:
            deadline = time.monotonic() + 20
            while True:
                if proc.poll() is not None:
                    logs.seek(0)
                    raise AssertionError(logs.read().decode())
                try:
                    with socket.create_connection(('127.0.0.1', p), timeout=0.2):
                        break
                except OSError:
                    if time.monotonic() > deadline:
                        raise AssertionError('server did not become reachable')
                    time.sleep(0.1)
            for path, expected, contains in cases:
                code, body = request(base, path)
                assert code == expected, (path, code, body[:300])
                assert contains in body, (path, body[:300])
                print(f'PASS {path}: HTTP {code}')
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=12)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                raise AssertionError('server did not stop on SIGTERM')
        assert proc.returncode == 0, f'unclean exit: {proc.returncode}'
        print('PASS clean SIGTERM exit')


exercise([str(ROOT / 'backend/bin/server')], {'APP_ENV': 'test'}, [
    ('/health', 200, 'ok'), ('/ready', 503, 'not_ready'),
    ('/api/v1/orders', 503, 'Database not configured'),
])
exercise(['node', 'frontend/.output/server/index.mjs'], {}, [
    ('/admin/login', 200, '<html'),
    ('/api/table?t=invalid', 404, 'QR tidak valid'),
    ('/api/menu', 500, 'Server belum dikonfigurasi'),
    ('/api/orders', 410, 'Go cash-only'),
    ('/api/core/menu', 503, 'Backend Go'),
])
print('All process smoke checks passed; no live database/business transaction tested.')
