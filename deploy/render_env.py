"""Render allowlisted systemd EnvironmentFiles without logging source values.

Usage: python3 deploy/render_env.py backend_source frontend_source output_dir
The output directory must not exist. Source files use single-line dotenv
assignments, optional export, quotes and comments. No variable interpolation,
command substitution, duplicate assignments or multiline values are supported.
This module uses only the standard library; errors intentionally omit values.
"""
import argparse
import os
from pathlib import Path
import re
import sys
from urllib.parse import parse_qs, urlencode, urlsplit, urlunsplit

BACKEND_KEYS = ("DATABASE_URL", "SUPABASE_URL", "SUPABASE_ANON_KEY")
FRONTEND_KEYS = ("NUXT_PUBLIC_SUPABASE_URL", "NUXT_PUBLIC_SUPABASE_ANON_KEY")
CA_PATH = "/etc/teraskayumanis/prod-ca-2021.crt"
KEY_PATTERN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")


class ValidationError(ValueError):
    """A configuration error whose message contains no source values."""


def _safe_value(value):
    if not isinstance(value, str) or any(char in value for char in "\r\n\0"):
        raise ValidationError("Invalid environment value")
    return value


def _required(source, keys):
    result = {}
    for key in keys:
        value = _safe_value(source.get(key))
        if not value.strip():
            raise ValidationError("Missing required environment input")
        result[key] = value
    return result


def _database_url(value):
    try:
        # urlsplit silently strips some controls; reject those before parsing.
        if any(char.isspace() or ord(char) < 32 or ord(char) == 127 for char in value):
            raise ValueError
        if re.search(r"%(?![0-9A-Fa-f]{2})", value):
            raise ValueError
        url = urlsplit(value)
        if url.scheme not in ("postgres", "postgresql") or not url.hostname or url.fragment:
            raise ValueError
        if url.port is not None and not 1 <= url.port <= 65535:
            raise ValueError
        # Decode query values before replacing the encoded local CA path.
        # Leave the authority and database path encoded exactly as supplied.
        query = parse_qs(url.query, keep_blank_values=True, errors="strict")
        query["sslrootcert"] = [CA_PATH]
        query["sslmode"] = ["verify-full"]
        return urlunsplit(url._replace(query=urlencode(query, doseq=True)))
    except (ValueError, UnicodeError):
        raise ValidationError("Invalid DATABASE_URL") from None


def render_backend(source: dict) -> dict:
    result = _required(source, BACKEND_KEYS)
    result["DATABASE_URL"] = _database_url(result["DATABASE_URL"])
    result.update(APP_ENV="production", HOST="127.0.0.1", PORT="8080", GOMEMLIMIT="384MiB",
                  REALTIME_ORIGINS="https://teraskayumanis.alrizky.id")
    return result


def render_frontend(source: dict) -> dict:
    result = _required(source, FRONTEND_KEYS)
    result.update(NUXT_GO_API_URL="http://127.0.0.1:8080", HOST="127.0.0.1", PORT="3000",
                  NODE_ENV="production", NODE_OPTIONS="--max-old-space-size=512")
    return result


def serialize_env(values: dict) -> str:
    """Quote every value for systemd (which does not expand dollar signs)."""
    lines = []
    for key, value in values.items():
        if not isinstance(key, str) or not KEY_PATTERN.fullmatch(key):
            raise ValidationError("Invalid environment key")
        escaped = _safe_value(value).replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'{key}="{escaped}"\n')
    return "".join(lines)


def _parse_value(raw):
    raw = raw.strip()
    if not raw or raw[0] not in "\"'":
        # A hash inside an unquoted token is literal; whitespace starts a comment.
        return _safe_value(re.split(r"\s+#", raw, maxsplit=1)[0].rstrip())
    quote = raw[0]
    chars = []
    index = 1
    while index < len(raw):
        char = raw[index]
        if char == quote:
            rest = raw[index + 1:].strip()
            if rest and not rest.startswith("#"):
                raise ValidationError("Invalid quoted assignment")
            return _safe_value("".join(chars))
        if char == "\\" and quote == '"':
            index += 1
            if index == len(raw):
                break
            char = raw[index]
            if char in "nr0":
                raise ValidationError("Multiline or NUL escape is not supported")
            if char not in '\\"$`':
                chars.append("\\")
        chars.append(char)
        index += 1
    raise ValidationError("Unterminated quoted assignment")


def parse_env(text: str) -> dict:
    """Parse a deliberately restricted dotenv subset, never evaluate it."""
    if "\0" in text:
        raise ValidationError("NUL in source file")
    result = {}
    for line in text.split("\n"):
        line = line.removesuffix("\r")  # Accept CRLF source line endings.
        if "\r" in line:
            raise ValidationError("Invalid source line")
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        key, separator, raw = line.partition("=")
        key = key.strip()
        if not separator or not KEY_PATTERN.fullmatch(key) or key in result:
            raise ValidationError("Invalid or duplicate source assignment")
        result[key] = _parse_value(raw)
    return result


def write_output(backend_source: Path, frontend_source: Path, output_dir: Path):
    # Fully validate both inputs before creating any output. Do not copy arbitrary
    # source variables, including service-role keys, into either rendered file.
    backend = render_backend(parse_env(backend_source.read_text(encoding="utf-8")))
    frontend = render_frontend(parse_env(frontend_source.read_text(encoding="utf-8")))
    contents = {"backend.env": serialize_env(backend), "frontend.env": serialize_env(frontend)}
    output_dir.mkdir(mode=0o700, exist_ok=False)
    created = []
    try:
        output_dir.chmod(0o700)
        for name, content in contents.items():
            path = output_dir / name
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            created.append(path)
            with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
                os.fchmod(stream.fileno(), 0o600)
                stream.write(content)
    except Exception:
        for path in created:
            path.unlink()
        output_dir.rmdir()
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backend_source", type=Path)
    parser.add_argument("frontend_source", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args(argv)
    try:
        write_output(args.backend_source, args.frontend_source, args.output_dir)
    except (OSError, ValueError):
        # Never print exceptions: parser/OS errors may contain source data/paths.
        print("Environment rendering failed: check inputs and use a new output directory.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
