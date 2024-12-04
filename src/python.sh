#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure python

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
    logTrace "Installing missing packages: ${missing_packages[@]}"
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

PY_ARGS=("$@")
PY_CWD=$(pwd)
PY_ME="$(basename "$0")"

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

# Import dependencies
source ${PY_ROOT}/src/slf4sh.sh
source ${PY_ROOT}/src/pkg.sh

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  echo "ERROR: This script cannot be piped"
  exit 1
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  echo "ERROR: This script cannot be exceuted"
  exit 1
fi