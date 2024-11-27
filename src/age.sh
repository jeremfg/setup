#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure AGE

# Install AGE (if not already installed)
#
# Parameters:
age_install() {
  if command -v age &>/dev/null; then
    logInfo "AGE is already installed"
    return 0
  fi

  local url="${AGE_URL}"
  local installer="$(basename ${url})"
  local location
  local bindir
  if git_find_root location "${AG_ROOT}"; then
    bindir="${location}/bin"
    location="${bindir}/downloads/${installer}"
    if [[ ! -f "${location}" ]]; then
      if ! mkdir -p "$(dirname ${location})"; then
        logError "Failed to create directory for AGE archive"
        return 1
      fi
      logTrace "Downloading into ${location} from ${url}"
      if ! curl -sSL -o "${location}" "${url}"; then
        logError "Failed to download age archive"
        return 1
      fi
    fi
    if ! tar -xvf "${location}" -C "${bindir}"; then
      logFatal "Failed to extract age"
    fi

    # For all binary files create a simlink in the bin directory
    local binfile
    for binfile in "${bindir}/age"/*; do
      if [[ -x "${binfile}" ]]; then
        local sim_file="${HOME}/bin/$(basename ${binfile})"
        if ! mkdir -p "${HOME}/bin"; then
          logError "Failed to create directory for binaries"
          return 1
        fi
        if [[ ! -L "${sim_file}" ]]; then
          logTrace "Creating symlink: ${sim_file}"
          if ! ln -s "${binfile}" "${sim_file}"; then
            logError "Failed to create symlink"
            return 1
          fi
        fi
      fi
    done

    # Confirm age is working
    if ! command -v age &>/dev/null; then
      logError "Failed to install AGE"
      return 1
    else
      logInfo "AGE installation detected"
      return 0
    fi
  else
    logError "Failed to find the root of the repository"
    return 1
  fi
}

# Constants

AGE_VERSION="1.2.0"
AGE_URL="https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz"

###########################
###### Startup logic ######
###########################

AG_ARGS=("$@")
AG_CWD=$(pwd)
AG_ME="$(basename "$0")"

# Get directory of this script
# https://stackoverflow.com/a/246128
AG_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${AG_SOURCE}" ]]; do # resolve $AG_SOURCE until the file is no longer a symlink
  AG_ROOT=$(cd -P "$(dirname "${AG_SOURCE}")" >/dev/null 2>&1 && pwd)
  AG_SOURCE=$(readlink "${AG_SOURCE}")
  [[ ${AG_SOURCE} != /* ]] && AG_SOURCE=${AG_ROOT}/${AG_SOURCE} # if $AG_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
AG_ROOT=$(cd -P "$(dirname "${AG_SOURCE}")" >/dev/null 2>&1 && pwd)
AG_ROOT=$(realpath "${AG_ROOT}/..")

# Import dependencies
source ${AG_ROOT}/src/slf4sh.sh
source ${AG_ROOT}/src/git.sh
source ${AG_ROOT}/src/env.sh

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  echo "ERROR: This script cannot be piped"
  exit 1
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  age_install "${@}"
  exit $?
fi