# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure python

if [[ -z ${GUARD_PYTHON_SH} ]]; then
  GUARD_PYTHON_SH=1
else
  return 0
fi

python_install() {
  if command -v pip3 &>/dev/null; then
    logInfo "pip is already installed"
    return 0
  else
    if ! pkg_install "python3" "python3-pip"; then
      logError "Failed to install python3 and python3-pip"
      return 1
    fi
  fi

  if ! command -v pip3 &>/dev/null; then
    logInfo "Could not detect pip"
    return 1
  fi

  return 0
}

# Install python modules
#
# Parameters:
#   $@: List of python modules to install
# Returns:
#   0: Success
#   1: Failure
pip_install() {
  python_install

  local package
  local name
  local version
  local res
  local missing_packages=()
  for package in "$@"; do
    name="${package%%==*}"
    version="${package##*==}"
    logTrace "Checking if ${name} is installed at version ${version}"
    if res=$(pip3 show "${name}"); then
      # Check if it's the proper version
      if [[ -n "${version}" ]]; then
        if echo "${res}" | grep "Version: ${version}" &>/dev/null; then
          logInfo "${name} is already installed at version ${version}"
        else
          logTrace <<EOF
Version mismatch for ${name}. Expected ${version}. Received:

${res}
EOF
          missing_packages+=("${package}")
        fi
      fi
    else
      logInfo "${name} is missing"
      missing_packages+=("${package}")
    fi
  done

  if [[ ${#missing_packages[@]} -gt 0 ]]; then
    logTrace "Installing missing packages: ${missing_packages[*]}"
    if ! pip3 install "${missing_packages[@]}"; then
      logError "Failed to install missing packages"
      return 1
    fi
  else
    logInfo "Nothing to install"
  fi

  return 0
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
PY_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${PY_SOURCE}" ]]; do # resolve $PY_SOURCE until the file is no longer a symlink
  PY_ROOT=$(cd -P "$(dirname "${PY_SOURCE}")" >/dev/null 2>&1 && pwd)
  PY_SOURCE=$(readlink "${PY_SOURCE}")
  [[ ${PY_SOURCE} != /* ]] && PY_SOURCE=${PY_ROOT}/${PY_SOURCE} # if $PY_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
PY_ROOT=$(cd -P "$(dirname "${PY_SOURCE}")" >/dev/null 2>&1 && pwd)
PY_ROOT=$(realpath "${PY_ROOT}/..")

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
fi
if ! source "${PY_ROOT}/src/pkg.sh"; then
  logFatal "Failed to import pkg.sh"
fi

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  logFatal "This script cannot be piped"
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  logFatal "This script cannot be exceuted"
fi
