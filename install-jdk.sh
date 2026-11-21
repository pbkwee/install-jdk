#!/bin/bash

#codex:deprecated The previous shebang enabled bash -x for every run. Tracing is
# now opt-in through normal shell tooling so routine installs do not echo every
# command or potentially sensitive environment value.
# #!/bin/bash -x

##
# Copyright Rimuhosting.com
#
# MIT License
#
# Copyright (c) 2026 Peter Bryant
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Install a JDK package or archive on Linux or macOS. The script is intentionally
# self-contained because it is commonly downloaded and run on its own.
##

set -o pipefail

#codex:deprecated The old script exported this globally because it installed
# distro prerequisites. Package installation was removed, so changing the
# caller's package-manager environment is no longer necessary.
# export DEBIAN_FRONTEND="noninteractive"

#codex:deprecated wget previously needed a made-up User-Agent to avoid timeouts.
# Downloads now use curl when available and a descriptive bounded wget fallback.
# WGET_OPTS=(--tries=2 --timeout=10 --quiet --header="User-Agent: banana")

DEFAULT_JDK_VERSION=27
AZUL_ZULU_PACKAGES=https://api.azul.com/metadata/v1/zulu/packages/
INSTALL_JDK_VERSION=${INSTALL_JDK_VERSION-}
INSTALL_JDK_MODE=${INSTALL_JDK_MODE:-auto}
INSTALL_JDK_ACTIVATE=${INSTALL_JDK_ACTIVATE:-auto}
INSTALL_JDK_APT_AUTO_UPDATES=${INSTALL_JDK_APT_AUTO_UPDATES:-auto}
INSTALL_JDK_TARGET=${INSTALL_JDK_TARGET-}
INSTALL_JDK_DOWNLOAD_URL=${INSTALL_JDK_DOWNLOAD_URL-}
INSTALL_JDK_CHECKSUM_URL=${INSTALL_JDK_CHECKSUM_URL-}
INSTALL_JDK_ARCHITECTURE=${INSTALL_JDK_ARCHITECTURE-}

INSTALL_JDK_PROMPT=${INSTALL_JDK_PROMPT:-false}
INSTALL_JDK_FORCE_INSTALL=${INSTALL_JDK_FORCE_INSTALL:-false}
INSTALL_JDK_PERMIT_OBSOLETE=${INSTALL_JDK_PERMIT_OBSOLETE:-false}
EARLY_ACCESS=false
INSTALL_JDK_PROFILE_SHELL=${INSTALL_JDK_PROFILE_SHELL:-auto}
INSTALL_JDK_VERIFY_CHECKSUM=${INSTALL_JDK_VERIFY_CHECKSUM:-true}
INSTALL_JDK_RUN_POST_INSTALL_TESTS=${INSTALL_JDK_RUN_POST_INSTALL_TESTS:-true}
INSTALL_JDK_DRY_RUN=${INSTALL_JDK_DRY_RUN:-false}
INSTALL_JDK_QUIET=${INSTALL_JDK_QUIET:-false}
INSTALL_JDK_COLOR=${INSTALL_JDK_COLOR:-auto}
INSTALL_JDK_OUTPUT=${INSTALL_JDK_OUTPUT:-text}

PLATFORM=
PLATFORMARCH=
ARCHIVE_VENDOR=OpenJDK
ARCHIVEFILE=
ARCHIVETOPDIR=
JAVAHOME=
STAGEDIR=
DOWNLOADDIR=
BACKUPDIR=
ACTIVATEDDESTINATION=
ISNONPRIVILEGEDINSTALL=false
PACKAGEMANAGER=
PACKAGENAME=
ALTERNATIVES=
NEWREPOFILES=()
PROFILEUSER=
PROFILEHOME=
PROFILEFILES=()
PROFILECONFIGFILE=
ERRORMSG=

OUTPUTCOLOR=false
COLORRESET=
COLORBLUE=
COLORGREEN=
COLORYELLOW=
COLORRED=
COLORBOLD=

function is_command_available() {
  command -v "$1" >/dev/null 2>&1
}

function normalize_boolean_value() {
  case "$1" in
    y|Y|yes|YES|Yes|true|TRUE|True|1) echo true ;;
    n|N|no|NO|No|false|FALSE|False|0) echo false ;;
    *) return 1 ;;
  esac
}

function normalize_boolean_variable() {
  local name="$1"
  local value="${!name}"
  local normalized
  normalized=$(normalize_boolean_value "$value") || {
    ERRORMSG="$name must be true or false (legacy y/n is also accepted)"
    return 1
  }
  printf -v "$name" '%s' "$normalized"
}

function initialize_output() {
  case "$INSTALL_JDK_OUTPUT" in
    text) ;;
    json) INSTALL_JDK_COLOR=never ;;
    *) ERRORMSG="INSTALL_JDK_OUTPUT must be text or json"; return 1 ;;
  esac
  [ -n "${NO_COLOR:-}" ] && INSTALL_JDK_COLOR=never
  case "$INSTALL_JDK_COLOR" in
    always) OUTPUTCOLOR=true ;;
    never) OUTPUTCOLOR=false ;;
    auto) [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && OUTPUTCOLOR=true ;;
    *) ERRORMSG="INSTALL_JDK_COLOR must be auto, always, or never"; return 1 ;;
  esac
  if $OUTPUTCOLOR; then
    COLORRESET=$'\033[0m'
    COLORBLUE=$'\033[34m'
    COLORGREEN=$'\033[32m'
    COLORYELLOW=$'\033[33m'
    COLORRED=$'\033[31m'
    COLORBOLD=$'\033[1m'
  fi
}

function escape_json() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

function print_event() {
  local level="$1"
  shift
  if [ "$INSTALL_JDK_OUTPUT" = json ]; then
    printf '{"level":"%s","message":"%s"}\n' "$level" "$(escape_json "$*")"
    return 0
  fi
  case "$level" in
    section) $INSTALL_JDK_QUIET || printf '%s%s==>%s %s\n' "$COLORBOLD" "$COLORBLUE" "$COLORRESET" "$*" ;;
    detail) $INSTALL_JDK_QUIET || printf '    %s\n' "$*" ;;
    success) printf '%s%sOK:%s %s\n' "$COLORBOLD" "$COLORGREEN" "$COLORRESET" "$*" ;;
    warning) printf '%s%sWARNING:%s %s\n' "$COLORBOLD" "$COLORYELLOW" "$COLORRESET" "$*" >&2 ;;
    error) printf '%s%sERROR:%s %s\n' "$COLORBOLD" "$COLORRED" "$COLORRESET" "$*" >&2 ;;
  esac
}

function section() { print_event section "$@"; }
function detail() { print_event detail "$@"; }
function success() { print_event success "$@"; }
function warn() { print_event warning "$@"; }
function error() { print_event error "$@"; }

function print_version() {
  echo "install-jdk - install a JDK package or archive on Linux or macOS"
}

function print_usage() {
  local target detected
  if [ "$(id -u)" -ne 0 ]; then
    target="${XDG_DATA_HOME:-$HOME/.local/share}/rimuhosting/java"
  elif [ "$(output_platform)" = macos ]; then
    target=/Library/Java/JavaVirtualMachines
  else
    target=/usr/java
  fi
  detected=$(type -P java) || detected='not found on PATH'

  cat <<EOUSAGE
Usage: $0 [options]

  --jdk-version MAJOR              JDK 8, 11, 17, 21, 25, or 27 (default: $DEFAULT_JDK_VERSION, or 11 on 32-bit x86 Linux)
  --early-access                   Allow an OpenJDK preview, such as Java 28
  --install-mode MODE              auto, package, or archive (default: auto)
  --apt-auto-updates MODE          auto or off for unattended Corretto APT updates (default: auto)
  --activate MODE                  How the installed JDK becomes the Java you use
  --install-target PATH            Archive directory (default here: $target)
  --profile-shell SHELL            auto, bash, or zsh for --activate user-profile
  --architecture ARCH              x64, aarch64, or x86 (32-bit Linux)
  --download-url URL               Override the JDK archive download
  --checksum-url URL               Override the archive SHA-256 URL
  --verify-checksum BOOL           Verify the archive's SHA-256 (default: true)
  --permit-obsolete BOOL           Allow explicit Java 5–7, 9, or 10 archives
  --force-install BOOL             Replace an archive already installed at the same path
  --run-post-install-tests BOOL    Validate java and javac (default: true)
  --prompt                         Ask before replacing an existing archive
  --noprompt                       Never read stdin (default)
  --dry-run                        Show the plan without writing files or installing
  --quiet                          Show warnings, errors, and the final result
  --color auto|always|never        Control terminal colour (default: auto)
  --output text|json               Human text or newline-delimited JSON
  --help                           Show help without contacting download servers

Install modes:
  auto            Use signed Corretto packages when supported and running as root.
                  Use a verified archive for user installs, custom targets,
                  existing /usr/java/jdk installs, macOS, or early access.
  package         Use APT on Debian 12+ or Ubuntu 22+, or DNF/YUM on
                  AlmaLinux/Rocky/RHEL 8+ or CentOS Stream 9+.
  archive         Use a vendor archive. Rerun this installer for updates.
                  On 32-bit x86 Linux, use Azul Zulu for JDK 8 or Corretto for JDK 11.

Activation modes:
  auto            Keep the distro's alternatives policy for packages.
                  For archives, print how to use Java. Leave profiles alone.
  alternatives    Select both java and javac for a system package install.
  system-profile  For a Linux archive, set JAVA_HOME and PATH in
                  /etc/profile.d/java.sh for login shells. Requires root.
  user-profile    Write JAVA_HOME and PATH to ~/.config/rimuhosting/java.sh.
                  Bash sources it from ~/.bashrc and its first existing login
                  file (~/.bash_profile, ~/.bash_login, or ~/.profile). If none
                  exists, the installer creates ~/.bash_profile. Zsh sources it
                  from ~/.zprofile and ~/.zshrc. Run without sudo.

Environment defaults (command-line options override them):
  INSTALL_JDK_VERSION, INSTALL_JDK_MODE, INSTALL_JDK_ACTIVATE, INSTALL_JDK_TARGET
  INSTALL_JDK_PROFILE_SHELL, INSTALL_JDK_ARCHITECTURE, INSTALL_JDK_DOWNLOAD_URL
  INSTALL_JDK_CHECKSUM_URL, INSTALL_JDK_VERIFY_CHECKSUM, INSTALL_JDK_PERMIT_OBSOLETE
  INSTALL_JDK_FORCE_INSTALL, INSTALL_JDK_RUN_POST_INSTALL_TESTS, INSTALL_JDK_PROMPT
  INSTALL_JDK_DRY_RUN, INSTALL_JDK_QUIET, INSTALL_JDK_COLOR, INSTALL_JDK_OUTPUT
  INSTALL_JDK_APT_AUTO_UPDATES

Java in the current PATH: $detected

Examples:
  $0 --jdk-version 21                      # Personal install when run without sudo
  $0 --jdk-version 21 --activate user-profile
  sudo $0 --jdk-version 21 --activate alternatives
  $0 --jdk-version 28 --early-access
EOUSAGE
}

function require_option_value() {
  [ "$#" -gt 0 ] && [ -n "$1" ] && [ "${1#--}" = "$1" ]
}

function parse_command_line() {
  while [ "$#" -gt 0 ]; do
    local parameter="$1"
    case "$parameter" in
      --jdk-version|--java-version|--jre)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires a version"; return 1; }
        INSTALL_JDK_VERSION=$1
      ;;
      --install-mode)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires auto, package, or archive"; return 1; }
        INSTALL_JDK_MODE=$1
      ;;
      --activate)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires an activation mode"; return 1; }
        INSTALL_JDK_ACTIVATE=$1
      ;;
      --apt-auto-updates)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires auto or off"; return 1; }
        INSTALL_JDK_APT_AUTO_UPDATES=$1
      ;;
      --install-target|--installtarget)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires a path"; return 1; }
        INSTALL_JDK_TARGET=${1%/}
      ;;
      --architecture)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires x64, aarch64, or x86"; return 1; }
        INSTALL_JDK_ARCHITECTURE=$1
      ;;
      --64bit) INSTALL_JDK_ARCHITECTURE=x64 ;;
      --32bit) INSTALL_JDK_ARCHITECTURE=x86 ;;
      --download-url)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires a URL"; return 1; }
        INSTALL_JDK_DOWNLOAD_URL=$1
      ;;
      --checksum-url)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires a URL"; return 1; }
        INSTALL_JDK_CHECKSUM_URL=$1
      ;;
      --early-access) EARLY_ACCESS=true ;;
      --prompt) INSTALL_JDK_PROMPT=true ;;
      --noprompt) INSTALL_JDK_PROMPT=false ;;
      --force) INSTALL_JDK_FORCE_INSTALL=true ;;
      --force-install)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires true or false"; return 1; }
        INSTALL_JDK_FORCE_INSTALL=$1
      ;;
      --permit-obsolete)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires true or false"; return 1; }
        INSTALL_JDK_PERMIT_OBSOLETE=$1
      ;;
      --profile-shell)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires auto, bash, or zsh"; return 1; }
        INSTALL_JDK_PROFILE_SHELL=$1
      ;;
      --verify-checksum)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires true or false"; return 1; }
        INSTALL_JDK_VERIFY_CHECKSUM=$1
      ;;
      --run-post-install-tests)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires true or false"; return 1; }
        INSTALL_JDK_RUN_POST_INSTALL_TESTS=$1
      ;;
      --dry-run) INSTALL_JDK_DRY_RUN=true ;;
      --quiet) INSTALL_JDK_QUIET=true ;;
      --color)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires auto, always, or never"; return 1; }
        INSTALL_JDK_COLOR=$1
      ;;
      --output)
        shift; require_option_value "$@" || { ERRORMSG="$parameter requires text or json"; return 1; }
        INSTALL_JDK_OUTPUT=$1
      ;;
      --help|-h|help) print_version; print_usage; exit 0 ;;
      *) ERRORMSG="Unrecognized option '$parameter'"; return 1 ;;
    esac
    shift
  done
}

function output_platform() {
  # codex:refactor Distribution detection previously installed lsb_release and
  # attempted old 32-bit compatibility packages. Platform detection is now
  # read-only; required host packages must be managed explicitly by the caller.
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux) echo linux ;;
    *) return 1 ;;
  esac
}

#codex:deprecated A requested 32-bit install previously attempted a broad list
# of old Debian and Red Hat compatibility packages. Those package names are
# obsolete and host package changes are now left to the administrator.
# if [ "64" = "$(getconf LONG_BIT)" ] && [ "$ARCH_WANTED" = "32" ]; then
#   for i in ia32-libs compat-libstdc++-33 compat-libstdc++-296 glibc.i686; do
#     apt-get -y -qq install "$i"
#   done
# fi

function output_host_architecture() {
  case "$(uname -m)" in
    x86_64|amd64)
      # An x86-64 kernel can run a 32-bit Linux userspace.
      if [ "$PLATFORM" = linux ] && [ "$(getconf LONG_BIT 2>/dev/null)" = 32 ]; then
        echo x86
      else
        echo x64
      fi
    ;;
    arm64|aarch64) echo aarch64 ;;
    i386|i486|i586|i686) echo x86 ;;
    *) return 1 ;;
  esac
}

function output_user_home() {
  local user="$1"
  if is_command_available getent; then
    getent passwd "$user" | awk -F: 'NR == 1 {print $6}'
  elif is_command_available dscl; then
    dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
  elif [ "$user" = "$(id -un)" ]; then
    echo "$HOME"
  else
    return 1
  fi
}

function output_user_shell() {
  local user="$1"
  if is_command_available getent; then
    getent passwd "$user" | awk -F: 'NR == 1 {print $7}'
  elif is_command_available dscl; then
    dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '{print $2}'
  elif [ "$user" = "$(id -un)" ]; then
    echo "${SHELL:-/bin/bash}"
  else
    return 1
  fi
}

function resolve_user_profile() {
  local account_shell bash_login_file
  [ "$INSTALL_JDK_ACTIVATE" = user-profile ] || return 0
  PROFILEUSER=$(id -un) || return 1
  case "$PROFILEUSER" in
    ''|*[!a-zA-Z0-9_.-]*|-) ERRORMSG="PROFILEUSER is not a valid user name"; return 1 ;;
  esac
  id "$PROFILEUSER" >/dev/null 2>&1 || { ERRORMSG="Profile user '$PROFILEUSER' does not exist"; return 1; }
  PROFILEHOME=$(output_user_home "$PROFILEUSER") || {
    ERRORMSG="Could not determine the home directory for profile user '$PROFILEUSER'"
    return 1
  }
  if [ -z "$PROFILEHOME" ] || [ ! -d "$PROFILEHOME" ]; then
    ERRORMSG="Profile home '$PROFILEHOME' for user '$PROFILEUSER' does not exist"
    return 1
  fi
  if [ "$INSTALL_JDK_PROFILE_SHELL" = auto ]; then
    account_shell=$(output_user_shell "$PROFILEUSER") || account_shell=
    INSTALL_JDK_PROFILE_SHELL=$(basename "$account_shell")
    case "$INSTALL_JDK_PROFILE_SHELL" in
      bash|zsh) ;;
      *) ERRORMSG="Could not select Bash or zsh from '$account_shell'; use --profile-shell bash or zsh"; return 1 ;;
    esac
  fi
  PROFILEFILES=()
  if [ "$INSTALL_JDK_PROFILE_SHELL" = bash ]; then
    if [ -e "$PROFILEHOME/.bash_profile" ]; then
      bash_login_file="$PROFILEHOME/.bash_profile"
    elif [ -e "$PROFILEHOME/.bash_login" ]; then
      bash_login_file="$PROFILEHOME/.bash_login"
    elif [ -e "$PROFILEHOME/.profile" ]; then
      bash_login_file="$PROFILEHOME/.profile"
    else
      bash_login_file="$PROFILEHOME/.bash_profile"
    fi
    PROFILEFILES+=("$PROFILEHOME/.bashrc" "$bash_login_file")
  else
    PROFILEFILES+=("$PROFILEHOME/.zprofile" "$PROFILEHOME/.zshrc")
  fi
  PROFILECONFIGFILE="$PROFILEHOME/.config/rimuhosting/java.sh"
}

# Keep the original managed markers so existing startup hooks can be updated in place.
function output_unmanaged_java_profile_lines() {
  local file
  for file in "${PROFILEFILES[@]}"; do
    [ -f "$file" ] || continue
    awk -v file="$file" '
      $0 == "# BEGIN installjava.sh managed Java source" {managed=1; next}
      $0 == "# END installjava.sh managed Java source" {managed=0; next}
      !managed && $0 !~ /^[[:space:]]*#/ && ($0 ~ /JAVA_HOME|\/usr\/libexec\/java_home/ || ($0 ~ /PATH/ && $0 ~ /(java|jdk|corretto|temurin|zulu)[^[:space:]]*\/bin/)) {
        printf "%s:%d\n", file, NR
      }
    ' "$file"
  done
  if [ -e "$PROFILECONFIGFILE" ] && ! grep -q '^# BEGIN installjava.sh managed Java configuration$' "$PROFILECONFIGFILE"; then
    printf '%s: existing file is not managed by install-jdk\n' "$PROFILECONFIGFILE"
  fi
}

function preflight_user_profile() {
  local conflicts
  [ "$INSTALL_JDK_ACTIVATE" = user-profile ] || return 0
  conflicts=$(output_unmanaged_java_profile_lines)
  [ -z "$conflicts" ] || {
    ERRORMSG="Existing unmanaged Java profile configuration must be removed or reconciled before rerunning:
$conflicts
No download or installation was started. Review the listed lines, or rerun with --activate auto."
    return 1
  }
}

function apply_defaults_and_validate() {
  local name host_architecture
  for name in INSTALL_JDK_PROMPT INSTALL_JDK_FORCE_INSTALL INSTALL_JDK_PERMIT_OBSOLETE \
    INSTALL_JDK_VERIFY_CHECKSUM INSTALL_JDK_RUN_POST_INSTALL_TESTS INSTALL_JDK_DRY_RUN INSTALL_JDK_QUIET; do
    normalize_boolean_variable "$name" || return 1
  done
  case "$INSTALL_JDK_ACTIVATE" in
    auto|alternatives|system-profile|user-profile) ;;
    *) ERRORMSG="--activate must be auto, alternatives, system-profile, or user-profile"; return 1 ;;
  esac
  case "$INSTALL_JDK_PROFILE_SHELL" in
    auto|bash|zsh) ;;
    *) ERRORMSG="INSTALL_JDK_PROFILE_SHELL must be auto, bash, or zsh"; return 1 ;;
  esac
  case "$INSTALL_JDK_APT_AUTO_UPDATES" in
    auto|off) ;;
    *) ERRORMSG="--apt-auto-updates must be auto or off"; return 1 ;;
  esac

  PLATFORM=$(output_platform) || {
    ERRORMSG="Only Linux and macOS are currently supported"
    return 1
  }
  host_architecture=$(output_host_architecture) || host_architecture=
  PLATFORMARCH=${INSTALL_JDK_ARCHITECTURE:-$host_architecture}
  case "$PLATFORMARCH" in
    x64|aarch64|x86) ;;
    '') ERRORMSG="Could not determine the host architecture; use --architecture"; return 1 ;;
    *) ERRORMSG="INSTALL_JDK_ARCHITECTURE must be x64, aarch64, or x86"; return 1 ;;
  esac
  if [ "$PLATFORMARCH" = x86 ] && { [ "$PLATFORM" != linux ] || [ "$host_architecture" != x86 ]; }; then
    ERRORMSG="Detected $PLATFORM-${host_architecture:-unknown} userspace. The x86 JDK requires a 32-bit x86 Linux userspace. Use an architecture that matches this host."
    return 1
  fi
  if [ "$PLATFORM" = linux ] && [ "$host_architecture" = x86 ] && [ "$PLATFORMARCH" != x86 ]; then
    ERRORMSG="Detected 32-bit x86 Linux userspace. The requested $PLATFORMARCH JDK requires a 64-bit userspace. Use --architecture x86."
    return 1
  fi
  if [ "$PLATFORMARCH" = x86 ]; then DEFAULT_JDK_VERSION=11; fi
  INSTALL_JDK_VERSION=${INSTALL_JDK_VERSION:-$DEFAULT_JDK_VERSION}

  case "$INSTALL_JDK_VERSION" in
    ''|*[!0-9]*) ERRORMSG="INSTALL_JDK_VERSION must be a Java major version"; return 1 ;;
  esac
  if [ "$INSTALL_JDK_VERSION" -lt 5 ] || [ "$INSTALL_JDK_VERSION" -gt 99 ]; then
    ERRORMSG="INSTALL_JDK_VERSION must be between 5 and 99"
    return 1
  fi
  if [ "$INSTALL_JDK_VERSION" -lt 11 ] && [ "$INSTALL_JDK_VERSION" != 8 ] &&
      [ -n "$INSTALL_JDK_DOWNLOAD_URL" ] && ! $INSTALL_JDK_PERMIT_OBSOLETE; then
    ERRORMSG="Java $INSTALL_JDK_VERSION is obsolete; explicitly permit it with --permit-obsolete true"
    return 1
  fi

  if [ "$PLATFORMARCH" = x86 ]; then
    if [ "$INSTALL_JDK_MODE" = package ]; then
      ERRORMSG="Package mode has no Corretto packages for 32-bit x86 Linux. Use --install-mode archive."
      return 1
    fi
    if [ -z "$INSTALL_JDK_DOWNLOAD_URL" ] && [ "$INSTALL_JDK_VERSION" != 8 ] && [ "$INSTALL_JDK_VERSION" != 11 ]; then
      ERRORMSG="No automatic download is available for JDK $INSTALL_JDK_VERSION on 32-bit x86 Linux. For this major, supply a compatible archive with --download-url and --checksum-url. Automatic options are JDK 8 and 11."
      return 1
    fi
  fi

  if [ "$(id -u)" -ne 0 ]; then ISNONPRIVILEGEDINSTALL=true; fi
  case "$INSTALL_JDK_ACTIVATE" in
    system-profile)
      if $ISNONPRIVILEGEDINSTALL || [ "$PLATFORM" != linux ]; then
        ERRORMSG="--activate system-profile requires root on Linux"
        return 1
      fi
    ;;
    user-profile)
      if ! $ISNONPRIVILEGEDINSTALL; then
        ERRORMSG="--activate user-profile must run as the intended user without sudo"
        return 1
      fi
    ;;
  esac
  resolve_install_mode || return 1
  if [ "$INSTALL_JDK_ACTIVATE" = alternatives ]; then
    [ "$INSTALL_JDK_MODE" = package ] || {
      ERRORMSG="--activate alternatives requires a package install. Use --install-mode package, or choose profile activation for an archive."
      return 1
    }
    ALTERNATIVES=alternatives
    [ "$PACKAGEMANAGER" != apt-get ] || ALTERNATIVES='update-alternatives'
    is_command_available "$ALTERNATIVES" || {
      ERRORMSG="--activate alternatives requires $ALTERNATIVES"
      return 1
    }
  fi
  if [ "$INSTALL_JDK_MODE" = package ]; then
    INSTALL_JDK_TARGET=/usr/lib/jvm
  elif $ISNONPRIVILEGEDINSTALL; then
    INSTALL_JDK_TARGET=${INSTALL_JDK_TARGET:-${XDG_DATA_HOME:-$HOME/.local/share}/rimuhosting/java}
  elif [ "$PLATFORM" = macos ]; then
    INSTALL_JDK_TARGET=${INSTALL_JDK_TARGET:-/Library/Java/JavaVirtualMachines}
  else
    INSTALL_JDK_TARGET=${INSTALL_JDK_TARGET:-/usr/java}
  fi
  case "$INSTALL_JDK_TARGET" in
    /*) ;;
    *) ERRORMSG="INSTALL_JDK_TARGET must be an absolute path"; return 1 ;;
  esac
  [ "$INSTALL_JDK_TARGET" != / ] || { ERRORMSG="Refusing to use / as INSTALL_JDK_TARGET"; return 1; }
  resolve_user_profile || return 1
}

function download_stdout() {
  local url="$1"
  if is_command_available curl; then
    curl --fail --location --silent --show-error --max-time 30 "$url"
  elif is_command_available wget; then
    wget --quiet --timeout=30 --tries=2 --header='User-Agent: install-jdk' --output-document=- "$url"
  else
    ERRORMSG="curl or wget is required"
    return 1
  fi
}

function download_file() {
  local url="$1"
  local destination="$2"
  if is_command_available curl; then
    curl --fail --location --silent --show-error --max-time 300 --output "$destination" "$url"
  elif is_command_available wget; then
    wget --quiet --timeout=30 --tries=2 --header='User-Agent: install-jdk' --output-document="$destination" "$url"
  else
    ERRORMSG="curl or wget is required"
    return 1
  fi
}

#codex:deprecated The old installer reused a same-named archive from the current
# directory and otherwise downloaded into that directory. Isolated temporary
# downloads now prevent stale or unverified local files from being installed.
# FILE="$(basename "$INSTALL_JDK_DOWNLOAD_URL")"
# if [ ! -e "$FILE" ]; then
#   wget "${WGET_OPTS[@]}" --output-document="$FILE" "$INSTALL_JDK_DOWNLOAD_URL"
# fi

function resolve_install_mode() {
  case "$INSTALL_JDK_MODE" in
    auto|package|archive) ;;
    *) ERRORMSG="--install-mode must be auto, package, or archive"; return 1 ;;
  esac

  case "$INSTALL_JDK_VERSION" in
    8|11|17|21|25|27) ;;
    *)
      if [ -z "$INSTALL_JDK_DOWNLOAD_URL" ] && [ "$INSTALL_JDK_VERSION" != 28 ]; then
        ERRORMSG="No maintained automatic download for Java $INSTALL_JDK_VERSION. Choose 8, 11, 17, 21, 25, or 27, or supply --download-url and a SHA-256 checksum URL."
        return 1
      fi
      if [ "$INSTALL_JDK_MODE" = package ]; then
        ERRORMSG="No Corretto repository package for Java $INSTALL_JDK_VERSION; use --install-mode archive"
        return 1
      fi
      INSTALL_JDK_MODE=archive
      return 0
    ;;
  esac

  if [ "$INSTALL_JDK_MODE" != archive ] && [ "$PLATFORM" = linux ] && [ "$PLATFORMARCH" != x86 ] && ! $ISNONPRIVILEGEDINSTALL \
      && { [ "$INSTALL_JDK_ACTIVATE" = auto ] || [ "$INSTALL_JDK_ACTIVATE" = alternatives ]; } \
      && [ -z "$INSTALL_JDK_TARGET$INSTALL_JDK_ARCHITECTURE$INSTALL_JDK_DOWNLOAD_URL$INSTALL_JDK_CHECKSUM_URL" ] \
      && $INSTALL_JDK_VERIFY_CHECKSUM && ! $INSTALL_JDK_FORCE_INSTALL && is_command_available gpg; then
    # Require current APT with native HTTPS and strict refresh, or DNF on EL.
    # os-release examples: ID=debian VERSION_ID="12", ID=rocky VERSION_ID="9.6".
    local family
    family=$(awk -F= '
      $1 == "ID" {gsub(/"/, "", $2); id=$2}
      $1 == "VERSION_ID" {gsub(/"/, "", $2); version=$2+0}
      END {
        if ((id == "debian" && version >= 12) || (id == "ubuntu" && version >= 22)) print "apt"
        if ((id ~ /^(almalinux|rocky|rhel)$/ && version >= 8) || (id == "centos" && version >= 9)) print "rpm"
      }' /etc/os-release 2>/dev/null) || family=
    case "$family" in
      apt)
        if is_command_available apt-get && is_command_available dpkg-query; then
          PACKAGEMANAGER=apt-get
          PACKAGENAME="java-$INSTALL_JDK_VERSION-amazon-corretto-jdk"
          [ "$INSTALL_JDK_VERSION" != 8 ] || PACKAGENAME=java-1.8.0-amazon-corretto-jdk
        fi
      ;;
      rpm)
        if is_command_available rpm; then
          if is_command_available dnf; then PACKAGEMANAGER=dnf
          elif is_command_available yum; then PACKAGEMANAGER=yum
          fi
          PACKAGENAME="java-$INSTALL_JDK_VERSION-amazon-corretto-devel"
          [ "$INSTALL_JDK_VERSION" != 8 ] || PACKAGENAME=java-1.8.0-amazon-corretto-devel
        fi
      ;;
    esac
  fi

  if [ "$INSTALL_JDK_MODE" = auto ]; then
    INSTALL_JDK_MODE=archive
    # Reinstall into the same tree for services already using the managed link.
    if [ -n "$PACKAGEMANAGER" ] && [ ! -L /usr/java/jdk ]; then INSTALL_JDK_MODE=package; fi
  fi
  if [ "$INSTALL_JDK_MODE" = package ] && [ -z "$PACKAGEMANAGER" ]; then
    if $ISNONPRIVILEGEDINSTALL; then
      ERRORMSG="Package mode requires root. Run with sudo or use --install-mode archive."
    elif [ "$PLATFORM" != linux ]; then
      ERRORMSG="Package mode uses Linux repositories. On $PLATFORM, use --install-mode archive."
    elif ! is_command_available gpg; then
      ERRORMSG="gpg is required to verify the Corretto repository key. Install GnuPG or use --install-mode archive."
    elif [ -n "$INSTALL_JDK_TARGET$INSTALL_JDK_ARCHITECTURE$INSTALL_JDK_DOWNLOAD_URL$INSTALL_JDK_CHECKSUM_URL" ] ||
        [ "$INSTALL_JDK_ACTIVATE" = system-profile ] || $INSTALL_JDK_FORCE_INSTALL || ! $INSTALL_JDK_VERIFY_CHECKSUM; then
      ERRORMSG="Archive-only settings are active. Use --install-mode archive or remove the archive overrides to use packages."
    else
      ERRORMSG="No supported package manager was found for this Linux release. Use --install-mode archive or check the supported releases in --help."
    fi
    return 1
  fi
}

function install_repo_file() {
  local candidate="$1" destination="$2" staged
  if [ -f "$destination" ] && cmp -s "$candidate" "$destination"; then return 0; fi
  ERRORMSG="Could not create $destination. Review any existing Corretto repository configuration."
  staged=$(mktemp "$destination.XXXXXX") || return 1
  if ! cat "$candidate" > "$staged" || ! chmod 644 "$staged" || ! ln -T "$staged" "$destination"; then
    rm -f -- "$staged"
    return 1
  fi
  rm -f -- "$staged"
  NEWREPOFILES+=("$destination")
}

function configure_corretto_apt_updates() {
  local candidate="$DOWNLOADDIR/60-install-jdk-corretto" destination=/etc/apt/apt.conf.d/60-install-jdk-corretto
  if [ "$INSTALL_JDK_APT_AUTO_UPDATES" = auto ]; then
    is_command_available unattended-upgrade || return 0
    # apt-config shell emits periodic='1' and unattended='1' (or 'always').
    # APT runs periodic upgrades only when the unattended interval is enabled.
    if ! apt-config shell periodic APT::Periodic::Enable unattended APT::Periodic::Unattended-Upgrade |
      awk -F"'" '
        BEGIN { active = 1 }
        $1 == "periodic=" { active = tolower($2) ~ /^(1|yes|true|on)$/ }
        $1 == "unattended=" { scheduled = ($2 == "always" || ($2 ~ /^[0-9]+$/ && $2 > 0)) }
        END { exit !(active && scheduled) }
      '; then
      return 0
    fi
  fi

  if ! cat > "$candidate" <<'APT'
/* Managed by install-jdk */
Unattended-Upgrade::Origins-Pattern {
    "site=apt.corretto.aws,archive=stable,component=main";
};
APT
  then
    warn "Could not prepare the unattended Corretto APT rule."
    return 0
  fi
  if [ "$INSTALL_JDK_APT_AUTO_UPDATES" = off ]; then
    if [ ! -L "$destination" ] && cmp -s "$candidate" "$destination"; then
      rm -f -- "$destination" || warn "Could not remove $destination."
    fi
  elif install_repo_file "$candidate" "$destination"; then
    NEWREPOFILES=()
    detail "Corretto is included in this host's unattended APT updates."
  else
    warn "Could not add Corretto to unattended APT updates. Review $destination to allow updates from the Corretto repository."
  fi
}

function install_corretto_package() {
  local key_host=apt key="$DOWNLOADDIR/corretto.key" fingerprint files compiler
  [ "$PACKAGEMANAGER" = apt-get ] || key_host=yum
  ERRORMSG="Could not download the Corretto signing key from $key_host.corretto.aws. Check HTTPS access and retry."
  download_file "https://$key_host.corretto.aws/corretto.key" "$key" || return 1
  ERRORMSG="gpg could not read the downloaded Corretto repository key."
  fingerprint=$(gpg --batch --homedir "$DOWNLOADDIR" --with-colons --show-keys "$key" |
    awk -F: '$1 == "pub" { primary=1 } $1 == "fpr" && primary { print $10; primary=0 }') || return 1
  [ "$fingerprint" = 6DC3636DAE534049C8B94623A122542AB04F24E3 ] || {
    ERRORMSG="The Corretto repository key fingerprint differs from the expected value. Verify the key with Amazon before retrying."
    return 1
  }

  if [ "$PACKAGEMANAGER" = apt-get ]; then
    ERRORMSG="Could not prepare the Corretto APT repository"
    gpg --batch --homedir "$DOWNLOADDIR" --dearmor --output "$DOWNLOADDIR/keyring.gpg" "$key" || return 1
    printf '%s\n' 'deb [signed-by=/usr/share/keyrings/corretto-keyring.gpg] https://apt.corretto.aws stable main' > "$DOWNLOADDIR/corretto.list" || return 1
    install_repo_file "$DOWNLOADDIR/keyring.gpg" /usr/share/keyrings/corretto-keyring.gpg || return 1
    install_repo_file "$DOWNLOADDIR/corretto.list" /etc/apt/sources.list.d/corretto.list || return 1
    ERRORMSG="apt-get update failed. Fix the APT error above before installing $PACKAGENAME."
    apt-get -o APT::Update::Error-Mode=any update >&2 || return 1
    ERRORMSG="apt-get could not install $PACKAGENAME. Review the APT error above."
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$PACKAGENAME" >&2 || return 1
    NEWREPOFILES=()
    ERRORMSG="dpkg-query could not list the files installed by $PACKAGENAME."
    files=$(dpkg-query -L "$PACKAGENAME") || return 1
  else
    ERRORMSG="Could not prepare the Corretto RPM repository"
    cat > "$DOWNLOADDIR/corretto.repo" <<'REPO' || return 1
[AmazonCorretto]
name=Amazon Corretto
baseurl=https://yum.corretto.aws/$basearch
enabled=1
gpgkey=https://yum.corretto.aws/corretto.key
gpgcheck=1
REPO
    install_repo_file "$DOWNLOADDIR/corretto.repo" /etc/yum.repos.d/corretto.repo || return 1
    ERRORMSG="rpm could not import the verified Corretto signing key. Review the RPM error above."
    rpm --import "$key" >&2 || return 1
    ERRORMSG="$PACKAGEMANAGER could not install $PACKAGENAME. Review the package manager error above."
    "$PACKAGEMANAGER" --refresh --best --setopt=AmazonCorretto.skip_if_unavailable=false \
      --setopt="AmazonCorretto.gpgkey=file://$key" install -y "$PACKAGENAME" >&2 || return 1
    NEWREPOFILES=()
    ERRORMSG="rpm could not list the files installed by $PACKAGENAME."
    files=$(rpm -ql "$PACKAGENAME") || return 1
  fi
  # java may be owned by the JRE subpackage, while javac is owned by the JDK.
  compiler=$(printf '%s\n' "$files" | awk '/^\/usr\/lib\/jvm\/.*\/bin\/javac$/ {print; exit}')
  ERRORMSG="Could not find the installed JDK in $PACKAGENAME"
  [ -n "$compiler" ] && [ -x "$compiler" ] || return 1
  JAVAHOME=${compiler%/bin/javac}
}

function set_package_default() {
  local java_target="$JAVAHOME/bin/java" javac_target="$JAVAHOME/bin/javac"
  local java_state javac_state previous mode
  # Corretto 8 RPM registers the JRE launcher. The Debian JDK registers bin/java.
  if [ "$PACKAGEMANAGER" != apt-get ] && [ "$INSTALL_JDK_VERSION" = 8 ]; then
    java_target="$JAVAHOME/jre/bin/java"
  fi

  ERRORMSG="Corretto is installed, but its java and javac alternatives could not be verified"
  java_state=$(LC_ALL=C "$ALTERNATIVES" --display java) || return 1
  javac_state=$(LC_ALL=C "$ALTERNATIVES" --display javac) || return 1
  # Both commands list providers as '/usr/lib/jvm/.../bin/java - priority N'.
  awk -v path="$java_target" '$1 == path { found=1 } END { exit !found }' <<< "$java_state" || return 1
  awk -v path="$javac_target" '$1 == path { found=1 } END { exit !found }' <<< "$javac_state" || return 1
  previous=$(sed -n 's/^[[:blank:]]*link currently points to //p' <<< "$javac_state")
  case "${javac_state%%$'\n'*}" in
    'javac - auto mode'|'javac - status is auto.') mode=auto ;;
    'javac - manual mode'|'javac - status is manual.') mode=manual ;;
    *) return 1 ;;
  esac
  [ -n "$previous" ] || return 1

  ERRORMSG="Corretto is installed, but $ALTERNATIVES could not select its java and javac"
  "$ALTERNATIVES" --set javac "$javac_target" >&2 || return 1
  if ! "$ALTERNATIVES" --set java "$java_target" >&2; then
    if [ "$mode" = auto ]; then
      "$ALTERNATIVES" --auto javac >&2 || warn "Could not restore the automatic javac default"
    else
      "$ALTERNATIVES" --set javac "$previous" >&2 || warn "Could not restore javac to $previous"
    fi
    return 1
  fi
  detail "Selected Corretto $INSTALL_JDK_VERSION for java and javac in distro alternatives"
}

function output_openjdk_download_url() {
  local page os=linux
  [ "$PLATFORM" != macos ] || os=macos
  page=$(download_stdout "https://jdk.java.net/$INSTALL_JDK_VERSION/") || return 1
  # Example: .../jdk28/24/GPL/openjdk-28-ea+24_linux-x64_bin.tar.gz
  printf '%s\n' "$page" |
    grep -Eo 'https://download\.java\.net/java/[^" ]+\.tar\.gz' |
    grep -E "openjdk-${INSTALL_JDK_VERSION}([._+]|-)" |
    grep "_${os}-${PLATFORMARCH}_bin\.tar\.gz" |
    sed -n '1p'
}

function output_azul_metadata_field() {
  # For example, {"sha256_hash":"9363..."} produces 9363...
  # Callers check the complete value and reject missing or multiple matches.
  grep -Eo "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" | cut -d '"' -f 4
}

function resolve_zulu_8_x86_download() {
  local libc packages package_id archive update
  local filters='java_version=8&os=linux_glibc&arch=i686&archive_type=tar.gz&java_package_type=jdk'
  filters+='&javafx_bundled=false&release_status=ga&availability_types=CA&release_type=PSU&latest=true&page_size=1'
  local uuid_pattern='^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
  local archive_pattern='^https://cdn\.azul\.com/zulu/bin/zulu8\.[0-9]+\.[0-9]+\.[0-9]+-ca-jdk8\.0\.([1-9][0-9]{1,5})-linux_i686\.tar\.gz$'
  libc=$(getconf GNU_LIBC_VERSION 2>/dev/null) || libc=
  case "$libc" in
    'glibc '[0-9]*) ;;
    *)
      ERRORMSG="The 32-bit Azul Zulu 8 archive requires glibc. getconf GNU_LIBC_VERSION could not identify it. Supply an archive for this system with --download-url and --checksum-url."
      return 1
    ;;
  esac
  detail "Detected 32-bit x86 Linux. Corretto 8 has no build for this platform. Looking up the Azul Zulu 8 archive."
  packages=$(download_stdout "$AZUL_ZULU_PACKAGES?$filters") || {
    ERRORMSG="Could not query Azul's package metadata for 32-bit Zulu 8. Check HTTPS access to api.azul.com, then retry."
    return 1
  }
  package_id=$(output_azul_metadata_field package_uuid <<< "$packages") || package_id=
  archive=$(output_azul_metadata_field download_url <<< "$packages") || archive=
  # A matching URL has the form zulu8.98.0.201-ca-jdk8.0.514-linux_i686.tar.gz.
  if ! [[ "$package_id" =~ $uuid_pattern && "$archive" =~ $archive_pattern ]]; then
    ERRORMSG="Azul's package metadata did not contain a usable 32-bit Zulu 8 JDK archive. Check the vendor's downloads or supply --download-url and --checksum-url."
    return 1
  fi
  update=${BASH_REMATCH[1]}
  # Azul's latest filter may include old builds. Require the November 2026
  # security release or later if the feed stops listing a current x86 build.
  if [ "$update" -lt 514 ]; then
    ERRORMSG="Azul returned Zulu 8u$update for 32-bit x86 Linux. Automatic installation requires 8u514 or later. Check the vendor's downloads for an updated build."
    return 1
  fi
  ARCHIVE_VENDOR="Azul Zulu"
  INSTALL_JDK_DOWNLOAD_URL=$archive
  INSTALL_JDK_CHECKSUM_URL=${INSTALL_JDK_CHECKSUM_URL:-$AZUL_ZULU_PACKAGES$package_id}
}

function resolve_download() {
  if [ -z "$INSTALL_JDK_DOWNLOAD_URL" ]; then
    if [ "$INSTALL_JDK_VERSION" = 28 ]; then
      INSTALL_JDK_DOWNLOAD_URL=$(output_openjdk_download_url) || INSTALL_JDK_DOWNLOAD_URL=
      [ -n "$INSTALL_JDK_DOWNLOAD_URL" ] || {
        ERRORMSG="Could not locate OpenJDK $INSTALL_JDK_VERSION for $PLATFORM-$PLATFORMARCH"
        return 1
      }
    elif [ "$INSTALL_JDK_VERSION" = 8 ] && [ "$PLATFORMARCH" = x86 ]; then
      resolve_zulu_8_x86_download || return 1
    else
      local os="$PLATFORM" filename libc major minor minimum=12
      if [ "$PLATFORM" = linux ]; then
        # AWS publishes these glibc floors for the Linux JDK tarballs.
        case "$INSTALL_JDK_VERSION-$PLATFORMARCH" in 25-*|27-*|*-aarch64) minimum=17 ;; esac
        libc=$(getconf GNU_LIBC_VERSION 2>/dev/null) || libc=
        IFS='. ' read -r _ major minor _ <<< "$libc"
        if [ -z "$major" ] || [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "${minor:-0}" -lt "$minimum" ]; }; then
          ERRORMSG="Detected ${libc:-no glibc version}. Corretto $INSTALL_JDK_VERSION on $PLATFORMARCH requires glibc 2.$minimum or newer. Upgrade the OS or supply a compatible archive with --download-url and --checksum-url."
          return 1
        fi
      fi
      ARCHIVE_VENDOR="Amazon Corretto"
      filename="amazon-corretto-$INSTALL_JDK_VERSION-$PLATFORMARCH-$os-jdk.tar.gz"
      INSTALL_JDK_DOWNLOAD_URL="https://corretto.aws/downloads/latest/$filename"
      INSTALL_JDK_CHECKSUM_URL=${INSTALL_JDK_CHECKSUM_URL:-https://corretto.aws/downloads/latest_sha256/$filename}
    fi
  fi
  case "$INSTALL_JDK_DOWNLOAD_URL" in
    https://download.java.net/java/early_access/*)
      $EARLY_ACCESS || {
        ERRORMSG="OpenJDK $INSTALL_JDK_VERSION is an early-access build; use --early-access to install it"
        return 1
      }
    ;;
    https://*) ;;
    *) ERRORMSG="JDK download URLs must use HTTPS"; return 1 ;;
  esac
  INSTALL_JDK_CHECKSUM_URL=${INSTALL_JDK_CHECKSUM_URL:-$INSTALL_JDK_DOWNLOAD_URL.sha256}
  case "$INSTALL_JDK_CHECKSUM_URL" in
    https://*) ;;
    *) ERRORMSG="Checksum URLs must use HTTPS"; return 1 ;;
  esac
}

function explain_existing_archive() {
  [ "$PLATFORM" = linux ] && [ -L /usr/java/jdk ] && [ -f /etc/profile.d/java.sh ] || return 0
  if [ "$INSTALL_JDK_MODE" = archive ] && [ "$INSTALL_JDK_TARGET" = /usr/java ]; then
    detail "Found /usr/java/jdk and /etc/profile.d/java.sh. This archive install uses the existing /usr/java/jdk link."
  else
    warn "Found /usr/java/jdk and /etc/profile.d/java.sh. The old profile can still put the archive ahead of the new JDK."
  fi
  detail "Run 'type -a java' and 'readlink -f /usr/java/jdk'. Review JAVA_HOME and PATH in the profile and JAVA_HOME in each service before switching."
}

function print_install_plan() {
  if [ "$INSTALL_JDK_MODE" = package ]; then
    if [ "$INSTALL_JDK_OUTPUT" = json ]; then
      printf '{"type":"plan","javaVersion":%s,"platform":"%s","architecture":"%s","target":"%s","installMode":"package","packageManager":"%s","packageName":"%s","activation":"%s"}\n' \
        "$INSTALL_JDK_VERSION" "$PLATFORM" "$PLATFORMARCH" "$INSTALL_JDK_TARGET" "$PACKAGEMANAGER" "$PACKAGENAME" "$INSTALL_JDK_ACTIVATE"
    else
      echo "Install Java $INSTALL_JDK_VERSION via $PACKAGEMANAGER ($PACKAGENAME)"
      echo "  Add or reuse the signed Corretto repository"
      echo "  Install under /usr/lib/jvm and use distro alternatives"
      echo "  Activation:           $INSTALL_JDK_ACTIVATE"
      if [ "$PACKAGEMANAGER" = apt-get ]; then
        echo "  APT unattended updates: $INSTALL_JDK_APT_AUTO_UPDATES"
      fi
    fi
    return 0
  fi
  if [ "$INSTALL_JDK_OUTPUT" = json ]; then
    printf '{"type":"plan","javaVersion":%s,"platform":"%s","architecture":"%s","target":"%s","downloadUrl":"%s","checksumUrl":"%s","installMode":"archive","obsolete":%s,"nonPrivileged":%s,"activation":"%s","profileUser":"%s","profileShell":"%s","verifyChecksum":%s}\n' \
      "$INSTALL_JDK_VERSION" "$PLATFORM" "$PLATFORMARCH" "$(escape_json "$INSTALL_JDK_TARGET")" \
      "$(escape_json "$INSTALL_JDK_DOWNLOAD_URL")" "$(escape_json "$INSTALL_JDK_CHECKSUM_URL")" "$([ "$INSTALL_JDK_VERSION" -lt 11 ] && [ "$INSTALL_JDK_VERSION" != 8 ] && echo true || echo false)" \
      "$ISNONPRIVILEGEDINSTALL" "$INSTALL_JDK_ACTIVATE" "$(escape_json "$PROFILEUSER")" \
      "$INSTALL_JDK_PROFILE_SHELL" "$INSTALL_JDK_VERIFY_CHECKSUM"
    return 0
  fi
  echo "Java archive installation plan"
  echo "  Java version:          $INSTALL_JDK_VERSION"
  echo "  Platform:              $PLATFORM-$PLATFORMARCH"
  echo "  Install target:        $INSTALL_JDK_TARGET"
  echo "  Download:              $INSTALL_JDK_DOWNLOAD_URL"
  echo "  Checksum:              $INSTALL_JDK_CHECKSUM_URL"
  echo "  Non-privileged:        $ISNONPRIVILEGEDINSTALL"
  echo "  Activation:           $INSTALL_JDK_ACTIVATE"
  if [ "$INSTALL_JDK_ACTIVATE" = user-profile ]; then
    echo "  Profile user:          $PROFILEUSER"
    echo "  Profile shell:         $INSTALL_JDK_PROFILE_SHELL"
    echo "  Profile configuration: $PROFILECONFIGFILE"
  fi
  echo "  Verify checksum:       $INSTALL_JDK_VERIFY_CHECKSUM"
  echo "  Post-install tests:    $INSTALL_JDK_RUN_POST_INSTALL_TESTS"
}

function output_file_sha256() {
  if is_command_available sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  elif is_command_available shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif is_command_available openssl; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    return 1
  fi
}

function verify_archive_checksum() {
  # codex:refactor Downloads were previously trusted when a file merely existed.
  # SHA-256 verification is now required unless the caller explicitly disables it.
  local checksum_file="$DOWNLOADDIR/archive.sha256"
  local expected actual metadata_archive
  $INSTALL_JDK_VERIFY_CHECKSUM || { warn "Skipped archive SHA-256 verification because --verify-checksum is false."; return 0; }
  # OpenJDK's .sha256 response is one bare hexadecimal field, for example:
  # 2da09e9db53e5c4f9eeec045f49e7d8fbcd8e4153edbf0c269f520ff82fd4198
  download_file "$INSTALL_JDK_CHECKSUM_URL" "$checksum_file" || {
    ERRORMSG="Could not download the SHA-256 checksum from $INSTALL_JDK_CHECKSUM_URL. Check HTTPS access or provide a valid --checksum-url."
    return 1
  }
  case "$INSTALL_JDK_CHECKSUM_URL" in
    "$AZUL_ZULU_PACKAGES"*)
      metadata_archive=$(output_azul_metadata_field download_url < "$checksum_file") || metadata_archive=
      if [ "$metadata_archive" != "$INSTALL_JDK_DOWNLOAD_URL" ]; then
        ERRORMSG="Azul's checksum metadata does not identify the selected archive. Check the archive and checksum URLs."
        return 1
      fi
      expected=$(output_azul_metadata_field sha256_hash < "$checksum_file") || expected=
    ;;
    *) expected=$(awk 'NR == 1 {print $1}' "$checksum_file") ;;
  esac
  if ! [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]]; then
    ERRORMSG="No valid SHA-256 checksum was found at $INSTALL_JDK_CHECKSUM_URL. Check the URL for the selected archive."
    return 1
  fi
  actual=$(output_file_sha256 "$ARCHIVEFILE") || {
    ERRORMSG="sha256sum, shasum, or openssl is required for checksum verification"
    return 1
  }
  expected=$(printf '%s' "$expected" | tr 'A-F' 'a-f')
  if [ "$actual" != "$expected" ]; then
    ERRORMSG="The SHA-256 of ${ARCHIVEFILE##*/} does not match the expected checksum. Retry the download and check that the checksum belongs to this archive."
    return 1
  fi
  detail "Verified the SHA-256 checksum for ${ARCHIVEFILE##*/}."
}

function output_archive_top_directory() {
  # Linux archive: jdk-26.0.2/bin/java
  # macOS archive: jdk-26.0.2.jdk/Contents/Home/bin/java
  # Ignore an optional leading ./ and return the first top-level component.
  tar -tzf "$ARCHIVEFILE" |
    sed 's#^\./##' |
    awk -F/ 'NF && $1 != "" && first == "" {first=$1} END {print first}'
}

function validate_archive_paths() {
  # Read the complete archive listing so pipefail cannot turn grep's successful
  # early exit into a false negative when tar receives SIGPIPE.
  if tar -tzf "$ARCHIVEFILE" | grep -E '(^/|(^|/)\.\.(/|$))' >/dev/null; then
    ERRORMSG="The JDK archive contains an unsafe absolute or parent-relative path"
    return 1
  fi
  ARCHIVETOPDIR=$(output_archive_top_directory)
  [ -n "$ARCHIVETOPDIR" ] || { ERRORMSG="Could not identify the archive top-level directory"; return 1; }
}

function cleanup() {
  if [ "${#NEWREPOFILES[@]}" -gt 0 ]; then rm -f -- "${NEWREPOFILES[@]}"; fi
  [ -n "$DOWNLOADDIR" ] && [ -d "$DOWNLOADDIR" ] && rm -rf "$DOWNLOADDIR"
  [ -n "$STAGEDIR" ] && [ -d "$STAGEDIR" ] && rm -rf "$STAGEDIR"
}

function install_archive() {
  # codex:refactor Archives were previously expanded directly into INSTALL_JDK_TARGET
  # and --force deleted the existing directory. Extract and validate in a staging
  # directory, and move an existing installation to a timestamped backup instead.
  local destination staged_jdk backup_stamp launcher_output
  mkdir -p "$INSTALL_JDK_TARGET" || { ERRORMSG="Could not create $INSTALL_JDK_TARGET"; return 1; }
  STAGEDIR=$(mktemp -d "$INSTALL_JDK_TARGET/.install-jdk.XXXXXX") || {
    ERRORMSG="Could not create an extraction directory under $INSTALL_JDK_TARGET. Check its permissions and free space."
    return 1
  }
  tar -xzf "$ARCHIVEFILE" --directory "$STAGEDIR" || { ERRORMSG="Could not extract the JDK archive"; return 1; }

  #codex:deprecated Older private archives could be .bz files or executable .bin
  # installers. Current and retained legacy sources are verified tar.gz files;
  # executable installers cannot be safely staged and inspected before running.
  # if echo "$FILE" | grep -qai '.bz'; then
  #   tar -xjf "$FILE" --directory "$INSTALL_JDK_TARGET"
  # elif echo "$FILE" | grep -qai '.tar.gz'; then
  #   tar -xzf "$FILE" --directory "$INSTALL_JDK_TARGET"
  # elif echo "$FILE" | grep -qai '.bin'; then
  #   chmod +x "$FILE" && ./"$FILE"
  # fi
  staged_jdk="$STAGEDIR/$ARCHIVETOPDIR"
  if [ -x "$staged_jdk/Contents/Home/bin/java" ]; then
    JAVAHOME="$staged_jdk/Contents/Home"
  elif [ -x "$staged_jdk/bin/java" ]; then
    JAVAHOME="$staged_jdk"
  else
    ERRORMSG="The extracted archive does not contain an executable bin/java"
    return 1
  fi
  if [ "$PLATFORM" = linux ]; then
    local elf_header=()
    read -r -a elf_header < <(od -An -tx1 -N5 "$JAVAHOME/bin/java")
    # ELF magic followed by class 01 (32-bit) or 02 (64-bit).
    case "$PLATFORMARCH:${elf_header[*]}" in
      x86:'7f 45 4c 46 02'|x64:'7f 45 4c 46 01'|aarch64:'7f 45 4c 46 01')
        ERRORMSG="The archive's Java executable does not match the bitness of this Linux userspace."
        return 1
      ;;
    esac
  fi
  launcher_output=$("$JAVAHOME/bin/java" -version 2>&1) || {
    ERRORMSG="$JAVAHOME/bin/java -version failed on $PLATFORM-$PLATFORMARCH. Check the archive's runtime requirements."
    [ -z "$launcher_output" ] || ERRORMSG="$ERRORMSG Java reported: ${launcher_output%%$'\n'*}"
    return 1
  }

  destination="$INSTALL_JDK_TARGET/$ARCHIVETOPDIR"
  if [ -e "$destination" ]; then
    if ! $INSTALL_JDK_FORCE_INSTALL; then
      if $INSTALL_JDK_PROMPT; then
        read -r -p "$destination exists; replace it? [false] " answer || return 1
        [ "$(normalize_boolean_value "${answer:-false}")" = true ] || {
          detail "Keeping the existing installation"
          rm -rf "$STAGEDIR"
          STAGEDIR=
          [ -x "$destination/Contents/Home/bin/java" ] && JAVAHOME="$destination/Contents/Home" || JAVAHOME="$destination"
          return 0
        }
      else
        detail "$destination is already installed; use --force-install true to replace it"
        rm -rf "$STAGEDIR"
        STAGEDIR=
        [ -x "$destination/Contents/Home/bin/java" ] && JAVAHOME="$destination/Contents/Home" || JAVAHOME="$destination"
        return 0
      fi
    fi
    #codex:deprecated --force previously deleted the existing JDK directory
    # immediately. It is now renamed to a timestamped backup before activation
    # so a failed replacement can restore it.
    # echo "! Removing existing install of this version due to --force option"
    # rm -rf "$INSTALL_JDK_TARGET/$UNPACKDIR"
    backup_stamp=$(date +%Y%m%d%H%M%S)
    BACKUPDIR="$destination.old.$backup_stamp"
    mv "$destination" "$BACKUPDIR" || { ERRORMSG="Could not back up $destination"; return 1; }
  fi
  mv "$staged_jdk" "$destination" || {
    [ -n "$BACKUPDIR" ] && [ -d "$BACKUPDIR" ] && mv "$BACKUPDIR" "$destination"
    ERRORMSG="Could not activate $destination"
    return 1
  }
  ACTIVATEDDESTINATION="$destination"
  rmdir "$STAGEDIR" 2>/dev/null || true
  STAGEDIR=
  if [ -x "$destination/Contents/Home/bin/java" ]; then
    JAVAHOME="$destination/Contents/Home"
  else
    JAVAHOME="$destination"
  fi
}

function rollback_installation() {
  local failed_destination
  [ -n "$ACTIVATEDDESTINATION" ] && [ -e "$ACTIVATEDDESTINATION" ] || return 0
  failed_destination="$ACTIVATEDDESTINATION.failed.$(date +%Y%m%d%H%M%S)"
  mv "$ACTIVATEDDESTINATION" "$failed_destination" || return 1
  if [ -n "$BACKUPDIR" ] && [ -e "$BACKUPDIR" ]; then
    mv "$BACKUPDIR" "$ACTIVATEDDESTINATION" || return 1
  fi
  warn "Moved the failed installation to $failed_destination"
}

function write_managed_profile_source_block() {
  local file="$1"
  local temporary_file
  umask 077
  temporary_file=$(mktemp "${TMPDIR:-/tmp}/install-jdk-profile.XXXXXX") || return 1
  if [ -f "$file" ]; then
    awk '
      $0 == "# BEGIN installjava.sh managed Java source" {managed=1; next}
      $0 == "# END installjava.sh managed Java source" {managed=0; next}
      !managed {print}
    ' "$file" > "$temporary_file"
  fi
  {
    cat "$temporary_file"
    echo '# BEGIN installjava.sh managed Java source'
    echo "if [ -r \"\$HOME/.config/rimuhosting/java.sh\" ]; then"
    echo "  . \"\$HOME/.config/rimuhosting/java.sh\""
    echo 'fi'
    echo '# END installjava.sh managed Java source'
  } > "$file" || { rm -f "$temporary_file"; return 1; }
  rm -f "$temporary_file"
}

function configure_user_profile() {
  local rimu_directory="$PROFILEHOME/.config/rimuhosting" file
  umask 077
  mkdir -p "$rimu_directory" || { ERRORMSG="Could not create $rimu_directory"; return 1; }

  {
    echo '# BEGIN installjava.sh managed Java configuration'
    output_java_exports "$JAVAHOME"
    echo '# END installjava.sh managed Java configuration'
  } > "$PROFILECONFIGFILE" || { ERRORMSG="Could not write $PROFILECONFIGFILE"; return 1; }

  for file in "${PROFILEFILES[@]}"; do
    write_managed_profile_source_block "$file" || {
      ERRORMSG="Could not update $file"
      return 1
    }
  done
  detail "Configured $INSTALL_JDK_PROFILE_SHELL startup files for $PROFILEUSER"
}

function report_java_selection() {
  local selected resolved installed="$JAVAHOME/bin/java" diagnostic_home="$HOME"
  selected=$(type -P java) || selected=
  if [[ "$selected" -ef "$installed" || "$selected" -ef "$JAVAHOME/jre/bin/java" ]]; then
    detail "Java on this installer's PATH selects the installed JDK ($selected)."
  elif [ -n "$selected" ]; then
    resolved=$(readlink -f "$selected" 2>/dev/null) || resolved=$selected
    warn "The install shell resolves java to $resolved. The newly installed executable is $installed."
  else
    warn "The install shell could not find java on PATH. The new executable is $installed."
  fi
  if [ -n "${JAVA_HOME:-}" ] && [[ ! "$JAVA_HOME/bin/java" -ef "$installed" && ! "$JAVA_HOME/bin/java" -ef "$JAVAHOME/jre/bin/java" ]]; then
    warn "The inherited JAVA_HOME=$JAVA_HOME points elsewhere or has no executable java."
  elif [[ "$selected" -ef "$installed" || "$selected" -ef "$JAVAHOME/jre/bin/java" ]]; then
    return 0
  fi

  if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ]; then
    diagnostic_home=$(output_user_home "$SUDO_USER") || diagnostic_home=
  fi
  local file line
  local files=(/etc/profile /etc/bash.bashrc /etc/bashrc /etc/profile.d/*.sh)
  if [ -n "$diagnostic_home" ]; then
    files+=("$diagnostic_home"/.bashrc "$diagnostic_home"/.bash_profile
      "$diagnostic_home"/.bash_login "$diagnostic_home"/.profile
      "$diagnostic_home"/.zshenv "$diagnostic_home"/.zprofile "$diagnostic_home"/.zshrc
      "$diagnostic_home"/.config/rimuhosting/java.sh)
  fi
  for file in "${files[@]}"; do
    [[ -f "$file" && -r "$file" ]] || continue
    line=$(awk '
      !/^[[:space:]]*#/ && (/JAVA_HOME|\/usr\/libexec\/java_home/ || (/PATH/ && /(java|jdk|corretto|temurin|zulu)[^[:space:]]*\/bin/)) { print NR; exit }
    ' "$file") || continue
    if [ -n "$line" ]; then detail "Check Java settings in $file:$line."; fi
  done
  detail "In your shell, run 'type -a java' and 'java -version'. Services may set a separate JAVA_HOME."
}

function output_java_exports() {
  local path="$1"
  printf "export JAVA_HOME='%s'\n" "${path//\'/\'\\\'\'}"
  printf '%s\n' "export PATH=\"\$JAVA_HOME/bin:\$PATH\""
}

function preflight_system_profile() {
  [ "$INSTALL_JDK_ACTIVATE" = system-profile ] || return 0
  local profile=/etc/profile.d/java.sh
  if [ -e "$profile" ] || [ -L "$profile" ]; then
    # Accept the exact profile generated by this installer, including the old form.
    if [ -f "$profile" ] && [ ! -L "$profile" ] && {
      cmp -s "$profile" <(printf '%s\n' '#!/bin/sh'; output_java_exports "$INSTALL_JDK_TARGET/jdk") ||
      cmp -s "$profile" <(printf '%s\n' '#!/bin/sh' "export JAVA_HOME=\"$INSTALL_JDK_TARGET/jdk\"" "export PATH=\"\$JAVA_HOME/bin:\$PATH\"")
    }; then
      return 0
    fi
    ERRORMSG="$profile already exists with other settings. Review it before using --activate system-profile, or use --activate auto."
    return 1
  fi
}

function configure_java_activation() {
  case "$INSTALL_JDK_ACTIVATE" in
    user-profile) configure_user_profile ;;
    system-profile)
      local profile=/etc/profile.d/java.sh
      preflight_system_profile || return 1
      if [ ! -e "$profile" ]; then
        ERRORMSG="Could not create $profile"
        mkdir -p /etc/profile.d || return 1
        (umask 022; set -o noclobber; { printf '%s\n' '#!/bin/sh'; output_java_exports "$INSTALL_JDK_TARGET/jdk"; } > "$profile") || return 1
      fi
      detail "Login shells can use Java from $profile. Open a new login shell."
    ;;
  esac
}

function print_archive_instructions() {
  case "$INSTALL_JDK_ACTIVATE" in
    user-profile) detail "Open a new shell or source $PROFILECONFIGFILE to load the new Java settings." ;;
    auto)
      if ! [[ "$(type -P java)" -ef "$JAVAHOME/bin/java" ]]; then
        detail "To use this JDK in your current shell, run:"
        output_java_exports "$JAVAHOME" | while IFS= read -r line; do detail "  $line"; done
      fi
    ;;
  esac
}

function test_installation() {
  local reported_version
  $INSTALL_JDK_RUN_POST_INSTALL_TESTS || {
    detail "Skipped post-install java and javac checks because --run-post-install-tests is false."
    return 0
  }
  [ -x "$JAVAHOME/bin/java" ] || { ERRORMSG="$JAVAHOME/bin/java is not executable"; return 1; }
  [ -x "$JAVAHOME/bin/javac" ] || { ERRORMSG="$JAVAHOME/bin/javac is not executable"; return 1; }
  # Modern Java: openjdk version "26.0.2" 2026-07-21
  # Early access: openjdk version "28-ea"
  # Legacy Java: java version "1.8.0_462"
  reported_version=$("$JAVAHOME/bin/java" -version 2>&1 | head -n 1)
  printf '%s\n' "$reported_version" | grep -Eq "version \"(1\.)?$INSTALL_JDK_VERSION([.\"]|-ea\"|$)" || {
    ERRORMSG="Installed Java does not report requested major version $INSTALL_JDK_VERSION: $reported_version"
    return 1
  }
  "$JAVAHOME/bin/javac" -version >/dev/null 2>&1 || {
    ERRORMSG="$JAVAHOME/bin/javac -version failed. Run it directly to see the JVM error."
    return 1
  }
  detail "Validated java and javac under $JAVAHOME"
}

function main() {
  if ! parse_command_line "$@"; then
    error "$ERRORMSG"
    print_usage
    return 1
  fi
  apply_defaults_and_validate || { error "$ERRORMSG"; return 1; }
  initialize_output || { error "$ERRORMSG"; return 1; }
  # Refuse unmanaged profile conflicts before URL discovery, downloads, or host
  # installation changes so the user can reconcile them and safely rerun.
  preflight_user_profile || { error "$ERRORMSG"; return 1; }
  preflight_system_profile || { error "$ERRORMSG"; return 1; }
  explain_existing_archive
  if [ "$INSTALL_JDK_MODE" = archive ]; then
    section "Resolve the JDK $INSTALL_JDK_VERSION archive for $PLATFORM-$PLATFORMARCH"
    resolve_download || { error "$ERRORMSG"; return 1; }
  fi
  if $INSTALL_JDK_DRY_RUN; then
    print_install_plan
    return 0
  fi

  # codex:refactor The previous installer downloaded or reused archives in the
  # caller's current directory. Each run now uses an isolated temporary download.
  DOWNLOADDIR=$(mktemp -d "${TMPDIR:-/tmp}/install-jdk.XXXXXX") || {
    error "Could not create a download directory in ${TMPDIR:-/tmp}. Check its permissions and free space."
    return 1
  }
  trap cleanup EXIT
  trap 'exit 1' HUP INT TERM
  if [ "$INSTALL_JDK_MODE" = package ]; then
    section "Install $PACKAGENAME with $PACKAGEMANAGER"
    install_corretto_package || { error "$ERRORMSG"; return 1; }
    test_installation || { error "$ERRORMSG"; return 1; }
    if [ "$INSTALL_JDK_ACTIVATE" = alternatives ]; then
      set_package_default || { error "$ERRORMSG"; return 1; }
    fi
    if [ "$PACKAGEMANAGER" = apt-get ]; then
      configure_corretto_apt_updates
      if is_command_available needrestart; then
        detail "Check pending service restarts with 'sudo needrestart -r l'."
      fi
    else
      detail "DNF security-only updates may skip Corretto. Check the host's update policy."
      detail "Check pending service restarts with 'sudo dnf needs-restarting --services' if available."
    fi
    success "Corretto $INSTALL_JDK_VERSION is installed at $JAVAHOME"
    report_java_selection
    detail "For each service, set JAVA_HOME=$JAVAHOME in its service configuration."
    return 0
  fi
  section "Download and verify $ARCHIVE_VENDOR $INSTALL_JDK_VERSION"
  ARCHIVEFILE="$DOWNLOADDIR/$(basename "$INSTALL_JDK_DOWNLOAD_URL")"
  detail "Downloading $INSTALL_JDK_DOWNLOAD_URL"
  download_file "$INSTALL_JDK_DOWNLOAD_URL" "$ARCHIVEFILE" || { error "Failed downloading $INSTALL_JDK_DOWNLOAD_URL"; return 1; }
  [ -s "$ARCHIVEFILE" ] || { error "The archive from $INSTALL_JDK_DOWNLOAD_URL is empty. Check the URL and retry."; return 1; }
  verify_archive_checksum || { error "$ERRORMSG"; return 1; }
  validate_archive_paths || { error "$ERRORMSG"; return 1; }

  section "Install $ARCHIVE_VENDOR $INSTALL_JDK_VERSION"
  install_archive || { error "$ERRORMSG"; return 1; }
  test_installation || { rollback_installation; error "$ERRORMSG"; return 1; }
  if [ -n "$ACTIVATEDDESTINATION" ] && { [ "$PLATFORM" = linux ] || $ISNONPRIVILEGEDINSTALL; }; then
    ln -sfn "$ACTIVATEDDESTINATION" "$INSTALL_JDK_TARGET/jdk" || {
      rollback_installation
      error "Could not update $INSTALL_JDK_TARGET/jdk"
      return 1
    }
  fi
  configure_java_activation || { rollback_installation; error "$ERRORMSG"; return 1; }
  success "$ARCHIVE_VENDOR $INSTALL_JDK_VERSION is installed at $JAVAHOME"
  report_java_selection
  print_archive_instructions
  if [ -L "$INSTALL_JDK_TARGET/jdk" ] && [[ "$INSTALL_JDK_TARGET/jdk/bin/java" -ef "$JAVAHOME/bin/java" ]]; then
    detail "The $INSTALL_JDK_TARGET/jdk link selects this JDK now. Restart services that use the link to load the new Java."
  fi
  detail "If a service uses a different Java path, set JAVA_HOME=$JAVAHOME in its configuration before restarting it."
}

#codex:deprecated The old script guessed whether it was launched from an
# interactive Bash parent and printed a banner unless --noprompt was supplied.
# Output is now deterministic; --help prints usage and --quiet controls chatter.
# CALLER=$(ps ax | grep "^ *$PPID" | awk '{print $NF}')
# [[ -z $NOPROMPT && "$CALLER" == "-bash" ]] && version

main "$@"
