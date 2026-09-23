#!/usr/bin/env bash
# Offline opt-in configuration regression: bash scripts/test_optional_setup.sh
set -euo pipefail
repo=$(cd -- "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "${scratch}"' EXIT
export HOME="${scratch}/home" XDG_CONFIG_HOME="${scratch}/home/.config"
export DEV_SETUP_DIR="${repo}/setup" TARGET=linux
export GIT_USER_NAME='Example User' GIT_USER_EMAIL='example@example.invalid'
mkdir -p "${XDG_CONFIG_HOME}"
# shellcheck source=/dev/null
source "${DEV_SETUP_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${DEV_SETUP_DIR}/lib/shell.sh"
# shellcheck source=/dev/null
source "${DEV_SETUP_DIR}/lib/tools.sh"
# shellcheck source=/dev/null
source "${DEV_SETUP_DIR}/lib/packages.sh"

# Disabled by default: no package-manager config, no gh credential helper.
render_git_config > "${scratch}/git-default"
! grep -q 'auth git-credential' "${scratch}/git-default"
configure_release_age_guards
[ ! -e "${HOME}/.npmrc" ]

export GH_CREDENTIAL_HELPER=true
render_git_config > "${scratch}/git-gh"
grep -q '\[credential "https://github.com"\]' "${scratch}/git-gh"
grep -q 'helper = !gh auth git-credential' "${scratch}/git-gh"

export RELEASE_AGE_GUARDS=true
export UV_EXCLUDE_NEWER='7 days'
export NPM_MIN_RELEASE_AGE=7
export BUN_MINIMUM_RELEASE_AGE=604800
export PNPM_MINIMUM_RELEASE_AGE=10080
configure_release_age_guards
configure_release_age_guards  # a second run must converge
[ "$(grep -c 'min-release-age=' "${HOME}/.npmrc")" -eq 1 ]
grep -q 'exclude-newer = "7 days"' "${XDG_CONFIG_HOME}/uv/uv.toml"
grep -q 'minimumReleaseAge = 604800' "${HOME}/.bunfig.toml"
grep -q 'minimum-release-age=10080' "${XDG_CONFIG_HOME}/pnpm/rc"

# The installer sources packages.sh BEFORE it loads profile.env. The opt-in
# must therefore be evaluated when step_packages runs, not at source time.
[[ "${APT_PACKAGES[*]}" != *docker.io* ]]
export INSTALL_DOCKER=true JOIN_DOCKER_GROUP=false
apt_install_base() { :; }       # no real apt operation in an offline test
install_release_binary() { :; } # no release downloads
have() { return 0; }
step_packages > /dev/null 2>&1
[[ " ${APT_PACKAGES[*]} " == *' docker.io docker-compose-v2 '* ]]
echo 'optional setup: ok'
