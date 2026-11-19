#!/usr/bin/env python3

import os
from pathlib import Path
import subprocess
import sys
import tempfile

SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "install-jdk.sh"


def executable(path, text):
    path.write_text("#!/bin/bash\n" + text + "\n")
    path.chmod(0o755)


with tempfile.TemporaryDirectory(prefix="install-jdk-apt-test-") as temp:
    root = Path(temp)
    for directory in ("bin", "etc/apt/apt.conf.d", "etc/apt/sources.list.d", "usr/share/keyrings", "usr/lib/jvm/fixture/bin"):
        (root / directory).mkdir(parents=True)
    (root / "etc/os-release").write_text('ID=debian\nVERSION_ID="13"\n')
    script = root / "install-jdk.sh"
    # All package-manager paths point to a disposable host tree.
    source = SOURCE.read_text()
    for prefix in ("/etc/", "/usr/share/keyrings/"):
        source = source.replace(prefix, str(root) + prefix)
    source = source.replace(r"^\/usr\/lib\/jvm\/", "^" + str(root).replace("/", r"\/") + r"\/usr\/lib\/jvm\/")
    script.write_text(source)

    bin_dir = root / "bin"
    executable(bin_dir / "id", '[ "$1" = -u ] && printf "0\\n"')
    executable(bin_dir / "curl", '[ "$7" = --output ] && printf "key\\n" > "$8"')
    executable(bin_dir / "gpg", """
case " $* " in
  *' --show-keys '*) printf 'pub:\\nfpr:::::::::6DC3636DAE534049C8B94623A122542AB04F24E3:\\n' ;;
  *' --dearmor '*) while [ "$1" != --output ]; do shift; done; printf 'key\\n' > "$2" ;;
  *) exit 99 ;;
esac""")
    executable(bin_dir / "apt-get", 'case " $* " in *" update "|*" install "*) exit 0 ;; *) exit 99 ;; esac')
    executable(bin_dir / "dpkg-query", 'printf "%s\\n" "$TMPDIR/usr/lib/jvm/fixture/bin/javac"')
    executable(bin_dir / "apt-config", """
[ "$1" = shell ] || exit 99
[ -z "$PERIODIC" ] || printf "periodic='%s'\\n" "$PERIODIC"
[ -z "$INTERVAL" ] || printf "unattended='%s'\\n" "$INTERVAL"
""")
    executable(bin_dir / "unattended-upgrade", 'touch "$TMPDIR/unexpected-unattended-command"; exit 99')
    executable(root / "usr/lib/jvm/fixture/bin/java", 'printf \'openjdk version "21.0.13"\\n\'')
    executable(root / "usr/lib/jvm/fixture/bin/javac", "exit 0")

    def run(*options, periodic="", interval="", **overrides):
        env = dict(PATH=f"{bin_dir}:/usr/bin:/bin", HOME=temp, TMPDIR=temp,
                   PERIODIC=periodic, INTERVAL=interval, **overrides)
        process = subprocess.run(
            ["bash", str(script), "--install-mode", "package", "--jdk-version", "21", *options],
            env=env, capture_output=True, text=True, timeout=20,
        )
        assert process.returncode == 0, process.stdout + process.stderr
        assert not (root / "unexpected-unattended-command").exists()
        return process.stdout + process.stderr

    rule = root / "etc/apt/apt.conf.d/60-install-jdk-corretto"
    run()
    run(interval="0")
    run(periodic="0", interval="1")
    run("--dry-run", interval="1")
    assert not rule.exists()
    assert "Corretto is included" in run(interval="always")
    content = rule.read_text()
    assert "site=apt.corretto.aws,archive=stable,component=main" in content
    assert "APT::Periodic" not in content and "Automatic-Reboot" not in content
    run(periodic="1", interval="2")
    assert rule.read_text() == content
    run(interval="1", INSTALL_JDK_APT_AUTO_UPDATES="off")
    assert not rule.exists()
    run("--apt-auto-updates", "auto", interval="1", INSTALL_JDK_APT_AUTO_UPDATES="off")
    assert rule.read_text() == content
    rule.write_text("// operator-owned rule\n")
    assert "Review " in run(interval="1")
    run("--apt-auto-updates", "off", interval="1")
    assert rule.read_text() == "// operator-owned rule\n"

print("APT unattended policy fixture passed")
