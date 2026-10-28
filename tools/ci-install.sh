#!/usr/bin/env bash
# Official installer interface: https://www.moonbitlang.com/download/
set -euo pipefail

: "${RUNNER_TEMP:?GitHub runner temporary directory is required}"
: "${MOONBIT_INSTALL_VERSION:?An explicit toolchain channel or version is required}"
export MOON_HOME="${RUNNER_TEMP}/dxf-moonbit"
export PATH="${MOON_HOME}/bin:${PATH}"
installer="${RUNNER_TEMP}/dxf-moonbit-install.sh"
curl --fail --silent --show-error --location \
  https://cli.moonbitlang.com/install/unix.sh --output "$installer"
printf '%s  %s\n' \
  46495f8cdc0050f79b6cb195d66478d101cb3601d68506568fbe377fcdf2a9fe \
  "$installer" | sha256sum --check -
bash "$installer" "$MOONBIT_INSTALL_VERSION"
printf 'MOON_HOME=%s\n' "$MOON_HOME" >> "$GITHUB_ENV"
printf '%s\n' "${MOON_HOME}/bin" >> "$GITHUB_PATH"
moon version --all
node --version
