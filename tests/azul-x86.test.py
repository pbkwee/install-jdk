#!/usr/bin/env python3

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / "install-jdk.sh"
API = "https://api.azul.com/metadata/v1/zulu/packages/"
PACKAGE = "72c92e2b-06e7-4901-945f-c3231b139d20"
BUILD = "zulu8.98.0.201-ca-jdk8.0.514-linux_i686"
ARCHIVE_URL = f"https://cdn.azul.com/zulu/bin/{BUILD}.tar.gz"


with tempfile.TemporaryDirectory(prefix="install-jdk-azul-test-") as directory:
    root = Path(directory)
    commands = root / "bin"
    commands.mkdir()

    def executable(path, body):
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(0o755)

    # Reproduce 32-bit userspace on an x86-64 kernel.
    executable(commands / "uname", 'case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; *) exit 1 ;; esac')
    executable(commands / "getconf", 'case "$1" in LONG_BIT) echo "$BITS" ;; GNU_LIBC_VERSION) echo "glibc 2.24" ;; *) exit 1 ;; esac')
    executable(commands / "curl", f'''
url=${{@: -1}}
case "$url" in
  '{API}?java_version=8&os=linux_glibc&arch=i686&archive_type=tar.gz&java_package_type=jdk&javafx_bundled=false&release_status=ga&availability_types=CA&release_type=PSU&latest=true&page_size=1')
    cat "$HOME/list.json"
    ;;
  '{API + PACKAGE}') cp "$HOME/details.json" "$8" ;;
  '{ARCHIVE_URL}') cp "$HOME/archive.tar.gz" "$8" ;;
  *) printf 'Unexpected URL: %s\\n' "$url" >&2; exit 99 ;;
esac''')

    binaries = root / BUILD / "bin"
    binaries.mkdir(parents=True)
    executable(binaries / "java", """printf 'openjdk version "1.8.0_514"\\n' >&2""")
    executable(binaries / "javac", "exit 0")
    archive = root / "archive.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(binaries.parent, arcname=BUILD)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    listing = {"package_uuid": PACKAGE, "download_url": ARCHIVE_URL}
    (root / "list.json").write_text(json.dumps([listing]))
    target = root / "java"

    def run(*options, status=0, bits="32"):
        env = {"PATH": f"{commands}:/usr/bin:/bin", "HOME": directory, "TMPDIR": directory, "BITS": bits}
        result = subprocess.run(
            ["bash", str(SCRIPT), "--install-target", str(target), *options],
            env=env, capture_output=True, text=True, timeout=15,
        )
        assert result.returncode == status, result.stdout + result.stderr
        return result.stdout

    def plan(*options, bits="32"):
        records = [json.loads(line) for line in run(*options, "--dry-run", "--output", "json", bits=bits).splitlines()]
        return next(record for record in records if record.get("type") == "plan")

    zulu = plan("--jdk-version", "8")
    assert zulu["architecture"] == "x86" and zulu["installMode"] == "archive"
    assert zulu["downloadUrl"] == ARCHIVE_URL and zulu["checksumUrl"] == API + PACKAGE
    assert "amazon-corretto-11-x86-linux" in plan()["downloadUrl"]
    assert "amazon-corretto-8-x64-linux" in plan("--jdk-version", "8", bits="64")["downloadUrl"]
    custom = plan("--jdk-version", "8", "--download-url", "https://example.test/custom.tar.gz")
    assert custom["downloadUrl"] == "https://example.test/custom.tar.gz"
    failure = run("--jdk-version", "17", "--dry-run", "--output", "json", status=1)
    assert "No automatic download is available for JDK 17 on 32-bit x86 Linux" in failure
    assert not target.exists()

    older = dict(listing, download_url=ARCHIVE_URL.replace("8.0.514", "8.0.512"))
    (root / "list.json").write_text(json.dumps([older]))
    failure = run("--jdk-version", "8", "--dry-run", "--output", "json", status=1)
    assert "Azul returned Zulu 8u512" in failure
    (root / "list.json").write_text(json.dumps([listing]))

    target.mkdir()
    old = target / "old"
    old.mkdir()
    link = target / "jdk"
    link.symlink_to(old)
    metadata = root / "details.json"
    metadata.write_text(json.dumps(dict(listing, sha256_hash="0" * 64)))
    failure = run("--jdk-version", "8", "--output", "json", status=1)
    assert "does not match the expected checksum" in failure
    assert link.resolve() == old and not (target / BUILD).exists()

    metadata.write_text(json.dumps(dict(listing, download_url="https://example.test/other.tar.gz", sha256_hash=digest)))
    failure = run("--jdk-version", "8", "--output", "json", status=1)
    assert "checksum metadata does not identify the selected archive" in failure
    assert link.resolve() == old

    metadata.write_text(json.dumps(dict(listing, sha256_hash=digest)))
    installed = run("--jdk-version", "8")
    assert "Verified the SHA-256 checksum" in installed
    assert "Azul Zulu 8 is installed" in installed
    assert "Restart services that use the link" in installed
    assert link.resolve() == target / BUILD and old.is_dir()

print("Azul Zulu 8 archive selection, verification and activation passed")
