#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This script is used to identify the OS

os() {
  local myvar
  local res
  os_identify myvar
  res=$?
  if [[ $res -eq 0 ]]; then
    echo "${myvar}"
  fi
  return $res
}

# Identify the current OS
#
# Parameters:
#   $1[out]: Current OS
os_identify(){
  local _os="$1"
  local file_os_release="/etc/os-release"
  logInfo "Performing OS identification..."

  if [[ -f "${file_os_release}" ]]; then
    logTrace "Sourcing: ${file_os_release}"
    var_backup
    source "${file_os_release}"
    # Print name and version
    if [[ -n "${NAME}" && -n "${VERSION}" ]]; then
      logInfo "Trying to identify ${NAME} Version ${VERSION}"
    fi

    # Iterate over all values in ID and ID_LIKE, in order
    local curId
    for curId in ${ID} ${ID_LIKE}; do
      case $curId in 
        centos)
          eval "$_os='centos'"
          logInfo "Identified centos"
          break
          ;;
        ubuntu)
          eval "$_os='ubuntu'"
          logInfo "Identified ubuntu"
          break
          ;;
        *)
          logWarn "Unknown OS: ${curId}"
          ;;
      esac
    done
    var_restore
    if [[ -z "${_os}" ]]; then
      return 1
    else
      return 0
    fi
  else
    local files_output
    local releaseFile

    for releaseFile in /etc/*release; do
        if [[ -f ${releaseFile} ]]; then
          files_output+="\n=== Contents of ${releaseFile} ===\n"
          files_output+=$(cat ${releaseFile})
        fi
    done
    logError "No OS information found. File '${file_os_release}' does not exist."
    logDebug <<EOF
======================================
=== Start of available information ===
======================================
=== uname -a ===
$(uname -a)

=== lsb_release -a ===
$(lsb_release -a)

=== /etc/*release files ===${files_output}
======================================
==== End of available information ====
======================================
EOF
  fi

  return 1
}

###########################
###### Startup logic ######
###########################
OS_ARGS=("$@")
OS_CWD=$(pwd)
OS_ME="$(basename "$0")"

# Get directory of this script
# https://stackoverflow.com/a/246128
OS_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${OS_SOURCE}" ]]; do # resolve $OS_SOURCE until the file is no longer a symlink
  OS_ROOT=$(cd -P "$(dirname "${OS_SOURCE}")" >/dev/null 2>&1 && pwd)
  OS_SOURCE=$(readlink "${OS_SOURCE}")
  [[ ${OS_SOURCE} != /* ]] && OS_SOURCE=${OS_ROOT}/${OS_SOURCE} # if $OS_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
OS_ROOT=$(cd -P "$(dirname "${OS_SOURCE}")" >/dev/null 2>&1 && pwd)
OS_ROOT=$(realpath "${OS_ROOT}/..")

# Import dependencies
source ${OS_ROOT}/src/slf4sh.sh
source ${OS_ROOT}/src/env.sh

if [[ -p /dev/stdin ]]; then
  # This script was piped
  echo "ERROR: This script cannot be piped"
  exit 1
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  LOG_CONSOLE=0 # Make sure logger is not outputting anything else on the console than what we want
  os "${@}"
  exit $?
fi
