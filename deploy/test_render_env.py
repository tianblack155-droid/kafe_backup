"""Deployment renderer tests: all credentials and input files are synthetic."""
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit

from deploy.render_env import (
    ValidationError, parse_env, render_backend, render_frontend, serialize_env,
)

SCRIPT = Path(__file__).with_name("render_env.py")
BACKEND = {
    "DATABASE_URL": "postgresql://demo:p%40ss@db.example.test:5432/app%2Ddb?sslrootcert=%2Froot%2Fprivate%2Fprod-ca-2021.crt&sslmode=require&application_name=demo&options=a&options=b",
    "SUPABASE_URL": "https://example.test",
    "SUPABASE_ANON_KEY": "synthetic-backend-key",
}
FRONTEND = {
    "NUXT_PUBLIC_SUPABASE_URL": "https://example.test",
    "NUXT_PUBLIC_SUPABASE_ANON_KEY": "synthetic-frontend-key",
}


class RenderTests(unittest.TestCase):
    def test_preview_realtime_origin_is_explicit_and_not_copied(self):
        result = render_backend(dict(BACKEND, REALTIME_ORIGINS='https://evil.test'))
        self.assertEqual(result.get('REALTIME_ORIGINS'), 'https://teraskayumanis.alrizky.id')

    def test_encoded_root_certificate_is_rewritten(self):
        result = render_backend(BACKEND)
        url = urlsplit(result["DATABASE_URL"])
        self.assertEqual(url.netloc, "demo:p%40ss@db.example.test:5432")
        self.assertEqual(url.path, "/app%2Ddb")
        self.assertEqual(parse_qs(url.query), {
            "sslrootcert": ["/etc/teraskayumanis/prod-ca-2021.crt"],
            "sslmode": ["verify-full"], "application_name": ["demo"],
            "options": ["a", "b"],
        })
        self.assertNotIn("%2Froot%2Fprivate", result["DATABASE_URL"])

    def test_missing_or_duplicate_tls_parameters_are_overwritten(self):
        for query in ("", "?sslmode=disable&sslmode=require&sslrootcert=x&sslrootcert=y"):
            source = dict(BACKEND, DATABASE_URL="postgres://db.example.test/app" + query)
            query_out = parse_qs(urlsplit(render_backend(source)["DATABASE_URL"]).query)
            self.assertEqual(query_out["sslmode"], ["verify-full"])
            self.assertEqual(query_out["sslrootcert"], ["/etc/teraskayumanis/prod-ca-2021.crt"])

    def test_backend_allowlist_and_overrides_without_mutation(self):
        source = dict(BACKEND, SUPABASE_SERVICE_ROLE_KEY="never-copy", PATH="evil",
                      APP_ENV="development", HOST="0.0.0.0", PORT="9", GOMEMLIMIT="1GiB")
        before = dict(source)
        result = render_backend(source)
        self.assertEqual(set(result), set(BACKEND) | {"APP_ENV", "HOST", "PORT", "GOMEMLIMIT", "REALTIME_ORIGINS"})
        self.assertEqual({key: result[key] for key in ("APP_ENV", "HOST", "PORT", "GOMEMLIMIT")},
                         {"APP_ENV": "production", "HOST": "127.0.0.1", "PORT": "8080", "GOMEMLIMIT": "384MiB"})
        self.assertEqual(source, before)

    def test_frontend_allowlist_and_overrides(self):
        source = dict(FRONTEND, SUPABASE_SERVICE_ROLE_KEY="never-copy",
                      NUXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY="never-copy", DATABASE_URL="never-copy",
                      HOST="0.0.0.0", PORT="9", NODE_ENV="development",
                      NODE_OPTIONS="--inspect", NUXT_GO_API_URL="https://evil.test")
        self.assertEqual(render_frontend(source), dict(
            FRONTEND, NUXT_GO_API_URL="http://127.0.0.1:8080", HOST="127.0.0.1",
            PORT="3000", NODE_ENV="production", NODE_OPTIONS="--max-old-space-size=512"))

    def test_mandatory_inputs(self):
        for render, source in ((render_backend, BACKEND), (render_frontend, FRONTEND)):
            for key in source:
                for value in (None, "", "   ", 123):
                    with self.subTest(key=key, invalid_type=type(value).__name__):
                        invalid = dict(source)
                        if value is None:
                            del invalid[key]
                        else:
                            invalid[key] = value
                        with self.assertRaises(ValidationError):
                            render(invalid)

    def test_invalid_database_urls_are_rejected_without_value_in_error(self):
        for value in ("synthetic-secret", "https://db.example.test/app", "postgres:///app",
                      "postgres://db.example.test:bad/app", "postgres://[bad/app",
                      "postgres://db.example.test/app#secret", "postgres://db.example.test/%ZZ"):
            with self.assertRaises(ValidationError) as error:
                render_backend(dict(BACKEND, DATABASE_URL=value))
            self.assertNotIn(value, str(error.exception))

    def test_serialize_quotes_and_escapes(self):
        self.assertEqual(serialize_env({"KEY": 'a\\b"c $HOME # literal', "EMPTY": ""}),
                         'KEY="a\\\\b\\"c $HOME # literal"\nEMPTY=""\n')

    def test_reject_injection_and_non_strings(self):
        for value in ("line\nINJECT=yes", "line\rINJECT=yes", "nul\0", 1):
            with self.assertRaises(ValidationError):
                serialize_env({"KEY": value})
            with self.assertRaises(ValidationError):
                render_backend(dict(BACKEND, SUPABASE_ANON_KEY=value))
            with self.assertRaises(ValidationError):
                render_frontend(dict(FRONTEND, NUXT_PUBLIC_SUPABASE_ANON_KEY=value))
        for key in ("BAD\nKEY", "A=B", "9KEY"):
            with self.assertRaises(ValidationError):
                serialize_env({key: "value"})

    def test_parse_dotenv_without_expansion(self):
        self.assertEqual(parse_env('# comment\nexport A="a\\\\b\\"c" # comment\nB=\'literal $HOME\'\nC=plain # comment\nD=a#b\n'),
                         {"A": 'a\\b"c', "B": "literal $HOME", "C": "plain", "D": "a#b"})
        self.assertEqual(parse_env(serialize_env({"KEY": 'a\\b"c $HOME # literal'})),
                         {"KEY": 'a\\b"c $HOME # literal'})

    def test_parse_rejects_invalid_or_multiline_input(self):
        for text in ('A="unfinished', 'A="x" trailing', 'A="line\nbreak"',
                     'A="line\\nbreak"', 'A=bad\0', 'BAD-KEY=x', 'not-assignment', 'A=x\nA=y'):
            with self.assertRaises(ValidationError):
                parse_env(text)


class CliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.backend = self.root / "source-backend"
        self.frontend = self.root / "source-frontend"
        self.output = self.root / "output"
        self.backend.write_text(serialize_env(dict(BACKEND, SUPABASE_SERVICE_ROLE_KEY="never-copy")))
        self.frontend.write_text(serialize_env(dict(FRONTEND, SUPABASE_SERVICE_ROLE_KEY="never-copy")))

    def run_cli(self):
        return subprocess.run([sys.executable, str(SCRIPT), str(self.backend),
                               str(self.frontend), str(self.output)],
                              capture_output=True, text=True)

    def test_cli_outputs_private_files_and_no_logs(self):
        old = os.umask(0)
        try:
            result = self.run_cli()
        finally:
            os.umask(old)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout + result.stderr, "")
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o700)
        for name, expected in (("backend.env", render_backend(BACKEND)),
                               ("frontend.env", render_frontend(FRONTEND))):
            file = self.output / name
            self.assertEqual(stat.S_IMODE(file.stat().st_mode), 0o600)
            self.assertEqual(parse_env(file.read_text()), expected)
        self.assertEqual({p.name for p in self.output.iterdir()}, {"backend.env", "frontend.env"})

    def test_validation_failure_has_no_output_directory_or_secret_logs(self):
        self.frontend.write_text("synthetic-private-marker malformed\n")
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("synthetic-private-marker", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertFalse(self.output.exists())

    def test_existing_directory_and_symlink_are_not_reused(self):
        target = self.root / "target"
        target.mkdir()
        for symlink in (False, True):
            if symlink:
                self.output.symlink_to(target, target_is_directory=True)
            else:
                self.output.mkdir()
            self.assertNotEqual(self.run_cli().returncode, 0)
            self.assertEqual(list(self.output.iterdir()), [])
            if symlink:
                self.output.unlink()
            else:
                self.output.rmdir()

    def test_permissions_are_exact_under_restrictive_umask(self):
        old = os.umask(0o777)
        try:
            result = self.run_cli()
        finally:
            os.umask(old)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o700)
        for name in ("backend.env", "frontend.env"):
            self.assertEqual(stat.S_IMODE((self.output / name).stat().st_mode), 0o600)

    def test_cli_rejects_missing_mandatory_input_and_invalid_encoding(self):
        for content in (b'NUXT_PUBLIC_SUPABASE_URL=https://example.test\n', b'\xff'):
            self.frontend.write_bytes(content)
            result = self.run_cli()
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertNotIn("Traceback", result.stderr)
            self.assertFalse(self.output.exists())

    def test_missing_source_has_sanitized_error(self):
        self.backend.unlink()
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(str(self.backend), result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
