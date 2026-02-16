# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Shared constants for setup scripts

if [[ -z ${GUARD_CONSTANTS_SH} ]]; then
  GUARD_CONSTANTS_SH=1
else
  return 0
fi

# Standard Linux paths
export SETUP_LOCAL_BIN="${HOME}/.local/bin"
export SETUP_LOCAL_OPT="${HOME}/.local/opt"
export SETUP_TMP_DIR="/tmp"
export SETUP_APT_KEYRING_DIR="/etc/apt/keyrings"
export SETUP_APT_SOURCES_DIR="/etc/apt/sources.list.d"
export SETUP_FSTAB_PATH="/etc/fstab"

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
CN_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${CN_SOURCE}" ]]; do # resolve $CN_SOURCE until the file is no longer a symlink
  CN_ROOT=$(cd -P "$(dirname "${CN_SOURCE}")" >/dev/null 2>&1 && pwd)
  CN_SOURCE=$(readlink "${CN_SOURCE}")
  [[ ${CN_SOURCE} != /* ]] && CN_SOURCE=${CN_ROOT}/${CN_SOURCE} # if $CN_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
CN_ROOT=$(cd -P "$(dirname "${CN_SOURCE}")" >/dev/null 2>&1 && pwd)

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  echo "This script cannot be piped"
  return 1 2>/dev/null || exit 1
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  echo "This script cannot be executed"
  exit 1
fi


