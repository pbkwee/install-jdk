# install-jdk

Install a Java Development Kit (JDK) on Linux or macOS through signed system
packages or checksum-verified archives. The installer uses Amazon Corretto for
stable releases and OpenJDK for early access.

## Get started

Download [install-jdk.sh](install-jdk.sh) and preview an install.

```bash
bash install-jdk.sh --jdk-version 21 --dry-run
```

Run the command without `--dry-run` to install. Run as your own user for a
personal install, or with `sudo` to install system-wide. See
`bash install-jdk.sh --help` for supported versions, install and activation
modes, and `INSTALL_JDK_` environment overrides.

For a personal install, use `--activate user-profile` to load the JDK
automatically in new Bash or Zsh login and interactive shells. To load the
settings in an open shell, run `. "$HOME/.config/rimuhosting/java.sh"`.

[MIT licence](LICENSE)
