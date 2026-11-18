# Using install-jdk

Run `bash ./install-jdk.sh --help` for the current list of options and environment
settings. Pass `--jdk-version` explicitly in automation so the installer chooses
the major version your application expects.

## Versions and platforms

The script offers automatic Corretto downloads for JDK 8, 11, 17, 21, 25, and 27.
It defaults to 27, or 11 on 32-bit x86 Linux, when no version is supplied.
For an existing application, specify the major it supports.

| Install mode | Where it fits | Destination |
| --- | --- | --- |
| `auto` (default) | Uses packages when eligible and running as root. Uses archives for personal installs, custom targets, an existing `/usr/java/jdk` link, macOS, and early access. | Follows the selected method. |
| `package` | Requires root and GnuPG. Uses APT on Debian 12+ or Ubuntu 22+, or DNF/YUM on AlmaLinux, Rocky Linux, or RHEL 8+, or CentOS Stream 9+. | Under `/usr/lib/jvm`. |
| `archive` | Verifies a vendor archive against its SHA-256 checksum. Use it on Linux and macOS where the vendor build is compatible. | A personal install uses `${XDG_DATA_HOME:-$HOME/.local/share}/rimuhosting/java`. A system-wide archive uses `/usr/java` on Linux or `/Library/Java/JavaVirtualMachines` on macOS. Supply `--install-target` with an absolute path to override. |

Automatic archives cover 64-bit Intel/AMD and Arm systems where the vendor
publishes a compatible build.

### Older Linux and 32-bit x86

Check the host libraries and the Java version your application currently uses.

```bash
getconf LONG_BIT
getconf GNU_LIBC_VERSION
java -version
```

On 32-bit x86 Linux, the installer defaults to the Corretto 11 archive and
verifies the vendor's SHA-256 checksum. This also applies to a 32-bit
userspace on an x86-64 kernel. On 64-bit Linux, the installer rejects requests
for x86 builds. It also checks the bitness of the Linux Java executable from
the archive before switching the JDK.

Preview the install with the same privilege level as the actual install.
Set `INSTALL_JDK_VERSION` or `--jdk-version` to choose a major explicitly.
An unavailable major stops the install with an explanation.

```bash
INSTALL_JDK_VERSION=11 bash ./install-jdk.sh --dry-run
```

Corretto 11 x86 targets glibc 2.12 or newer. Debian 6 shipped with eglibc 2.11,
so it falls below that floor. Even with compatible glibc, the host needs
working HTTPS downloads and the libraries required by the vendor build.
For older hosts, review the vendor's OS support before testing the JDK.
If the host cannot reach the vendor over HTTPS, use a current machine to
download and verify the archive. Transfer the verified file and follow the
vendor's manual installation instructions.
[Corretto build targets](https://github.com/corretto/corretto-11/blob/develop/CHANGELOG.md) ·
[Debian 6 package history](https://sources.debian.org/src/eglibc/)

If the application requires Java 8, keep that major version until you have tested
a migration. Corretto 8 has no Linux x86 build. Choose a maintained 32-bit build
from another vendor, such as Azul Zulu, and use its installation instructions.
If the vendor provides an HTTPS tarball and a plain SHA-256 checksum file, you
can pass them to the script with `--download-url` and `--checksum-url`.
[Corretto 8 downloads](https://docs.aws.amazon.com/corretto/latest/corretto-8-ug/downloads-list.html) ·
[Azul supported platforms](https://docs.azul.com/core/supported-platforms.html)

### Try an early-access JDK

For development and compatibility testing, preview JDK 28 where OpenJDK
publishes an archive for your OS and architecture.

```bash
bash ./install-jdk.sh --jdk-version 28 --early-access --dry-run
```

This preview queries the OpenJDK download page. To install for testing, remove
`--dry-run`. Keep production services on a maintained release.

## Select the JDK to run

| Activation | Effect |
| --- | --- |
| `auto` (default) | Follows the distro's alternatives policy for packages. For archives, prints exports when your shell would need them and leaves startup files alone. |
| `alternatives` | Selects the installed `java` and `javac` as the system alternatives. Requires package mode. |
| `user-profile` | Writes `JAVA_HOME` and prepends its `bin` directory to `PATH` in new Bash or Zsh sessions. Run as the intended user without `sudo`. |
| `system-profile` | Adds `/etc/profile.d/java.sh` for login shells on Linux. Requires a root archive install and checks for conflicting settings first. |

With `user-profile`, the exports live in `~/.config/rimuhosting/java.sh`.
Bash sources that file from `~/.bashrc` and from the first existing login file.
Bash checks `~/.bash_profile`, `~/.bash_login`, and `~/.profile` in that order.
If none exists, the installer creates `~/.bash_profile`. Zsh uses `~/.zprofile` and
`~/.zshrc`. If your default login shell differs from the shell you want to set
up, use `--profile-shell bash` or `--profile-shell zsh`.

For services or applications that use separate Java settings, point their
configuration at the installer-reported JDK directory. Use a version-specific
directory when multiple services need different JDKs. The archive install's
`jdk` symlink on Linux and personal installs can move to the last JDK
activated in that target.

Run these commands to check the JDK in your current shell.

```bash
type -a java
java -version
javac -version
printf '%s\n' "$JAVA_HOME"
```

If `java` still resolves to another install, check the paths in the installer's
diagnostics. On older RimuHosting installs, `/etc/profile.d/java.sh` may place
`/usr/java/jdk/bin` ahead of the package-managed Java. In a new shell, rerun
the checks after adjusting the relevant profile or service setting.

## Update an existing installation

- **Package** — update through APT or DNF/YUM using your normal update policy.
  If you use scheduled or unattended updates, check that your policy includes
  Corretto's repository.
- **Archive** — rerun the installer with the same major, install target, and
  activation choice. If the new build uses the same directory name, the
  installer keeps the existing JDK by default. Use `--prompt` to confirm an
  interactive replacement or `--force-install true` to replace it directly.
- **Running applications** — restart affected services after an update. Verify the
  active JDK using the service's configured path, which may differ from the
  shell's `java`.

## Automate a preview

Use `INSTALL_JDK_` environment variables for defaults and command-line flags
for overrides. This example prints newline-delimited JSON. Look for the record
with `"type":"plan"`.

```bash
INSTALL_JDK_VERSION=21 INSTALL_JDK_MODE=archive \
  bash ./install-jdk.sh --dry-run --output json
```

In a deployment that requires one exact build, use a versioned vendor archive
URL and its published checksum. The default Corretto source tracks the vendor's
latest build within the chosen major.
