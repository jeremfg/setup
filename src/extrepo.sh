# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Helpers for extrepo

if [[ -z ${GUARD_EXTREPO_SH+x} ]]; then
  GUARD_EXTREPO_SH=1
else
  return 0
fi

# Install extrepo if missing
extrepo_install() {
  if command -v extrepo &>/dev/null; then
    logInfo "extrepo is already installed"
    return 0
  elif ! pkg_install extrepo; then
    logError "Failed to install extrepo"
    return 1
  fi

  return 0
}

# Enable a repository via extrepo
#
# Parameters:
#   $1: Repository name
extrepo_enable() {
  local repo="$1"
  if [[ -z "${repo}" ]]; then
    logError "Missing repo name for extrepo_enable"
    return 1
  elif ! sudo extrepo enable "${repo}"; then
    logError "Failed to enable extrepo repo: ${repo}"
    return 1
  fi

  return 0
}

# Update a repository via extrepo
#
# Parameters:
#   $1: Repository name
extrepo_update() {
  local repo="$1"
  if [[ -z "${repo}" ]]; then
    logError "Missing repo name for extrepo_update"
    return 1
  elif ! sudo extrepo update "${repo}"; then
    logError "Failed to update extrepo repo: ${repo}"
    return 1
  fi

  return 0
}

# Install extrepo and ensure a repository is enabled and updated
#
# Parameters:
#   $1: Repository name
extrepo_ensure_repo() {
  local repo="$1"
  if [[ -z "${repo}" ]]; then
    logError "Missing repo name for extrepo_ensure_repo"
    return 1
  elif ! extrepo_install; then
    return 1
  elif ! extrepo_enable "${repo}"; then
    return 1
  elif ! extrepo_update "${repo}"; then
    return 1
  fi

  return 0
}

# Install a package via extrepo (ensure repo, then install package)
#
# Parameters:
#   $1: Repository name
#   $2: Package name
extrepo_install_package() {
  local repo="$1"
  local package="$2"

  if [[ -z "${repo}" || -z "${package}" ]]; then
    logError "Missing repo/package for extrepo_install_package"
    return 1
  elif ! extrepo_ensure_repo "${repo}"; then
    return 1
  elif ! pkg_install "${package}"; then
    logError "Failed to install package via extrepo: ${package}"
    return 1
  fi

  return 0
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
ER_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${ER_SOURCE}" ]]; do # resolve $ER_SOURCE until the file is no longer a symlink
  ER_ROOT=$(cd -P "$(dirname "${ER_SOURCE}")" >/dev/null 2>&1 && pwd)
  ER_SOURCE=$(readlink "${ER_SOURCE}")
  [[ ${ER_SOURCE} != /* ]] && ER_SOURCE=${ER_ROOT}/${ER_SOURCE} # if $ER_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
ER_ROOT=$(cd -P "$(dirname "${ER_SOURCE}")" >/dev/null 2>&1 && pwd)
ER_ROOT=$(realpath "${ER_ROOT}/..")

# Determine BPKG's global prefix
if [[ -z "${PREFIX}" ]]; then
  if [[ $(id -u || true) -eq 0 ]]; then
    PREFIX="/usr/local"
  else
    PREFIX="${HOME}/.local"
  fi
fi

# Import dependencies
# shellcheck disable=SC1091
if ! source "${PREFIX}/lib/slf4.sh"; then
  echo "Failed to import slf4.sh"
  exit 1
elif ! source "${ER_ROOT}/src/pkg.sh"; then
  echo "Failed to import pkg.sh"
  exit 1
fi

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  logFatal "This script cannot be piped"
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  logFatal "This script cannot be executed"
fi
