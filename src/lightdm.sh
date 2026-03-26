# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Helpers for LightDM configuration

if [[ -z ${GUARD_LIGHTDM_SH+x} ]]; then
  GUARD_LIGHTDM_SH=1
else
  return 0
fi

dm_file="/etc/lightdm/lightdm.conf"

ldm_fix() {
  logInfo "Fixing LightDM configuration for AD login"

  local setting1="greeter-hide-users"
  local setting2="greeter-show-manual-login"

  if ! ldm_set_setting "${setting1}" "false"; then
    logError "Failed to set LightDM setting: ${setting1}"
    return 1
  elif ! ldm_set_setting "${setting2}" "true"; then
    logError "Failed to set LightDM setting: ${setting2}"
    return 1
  else
    logDebug "Successfully updated LightDM configuration"
  fi

  if [[ ${DM_RESTART} -eq 1 ]]; then
    logInfo "Restarting LightDM to apply changes"
    if ! sudo systemctl restart lightdm; then
      logError "Failed to restart LightDM"
      return 1
    else
      DM_RESTART=0
      logInfo "Successfully restarted LightDM"
    fi
  else
    logDebug "LightDM restart not required"
  fi

  return 0
}

# Fix a setting
# Parameters:
#   $1: Setting name (e.g. "greeter-hide-users")
#   $2: Setting value (e.g. "true")
ldm_set_setting() {
  local setting="$1"
  local value="$2"

  if [[ -z "${setting}" || -z "${value}" ]]; then
    logError "Missing setting or value for ldm_set_setting"
    return 1
  fi

  # Find the line that contains the setting, knowing it could be prefix with a "#".
  # Make sure that line is only present once in the file.
  if ! grep -E "^[#]?\s*${setting}=" "${dm_file}" >/dev/null; then
    logError "LightDM setting not found in config file: ${setting}"
    return 1
  elif [[ $(grep -E "^[#]?\s*${setting}=" "${dm_file}" | wc -l) -gt 1 ]]; then
    logError "Multiple lines found for LightDM setting: ${setting}"
    return 1
  fi

  # If we already have the exact line, don't do anything
  if grep -E "^${setting}=${value}$" "${dm_file}" >/dev/null; then
    logDebug "LightDM setting already set: ${setting}=${value}"
    return 0
  fi

  # Update the setting, and track if we need to restart LightDM
  if ! sudo sed -i "s/^[#]?\s*\(${setting}=\).*/\1${value}/" "${dm_file}"; then
    logError "Failed to set LightDM setting: ${setting}"
    return 1
  else
    logDebug "Set LightDM setting: ${setting}=${value}"
    DM_RESTART=1
  fi

  return 0
}

DM_RESTART=0

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
DM_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${DM_SOURCE}" ]]; do # resolve $DM_SOURCE until the file is no longer a symlink
  DM_ROOT=$(cd -P "$(dirname "${DM_SOURCE}")" >/dev/null 2>&1 && pwd)
  DM_SOURCE=$(readlink "${DM_SOURCE}")
  [[ ${DM_SOURCE} != /* ]] && DM_SOURCE=${DM_ROOT}/${DM_SOURCE} # if $DM_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DM_ROOT=$(cd -P "$(dirname "${DM_SOURCE}")" >/dev/null 2>&1 && pwd)
DM_ROOT=$(realpath "${DM_ROOT}/..")

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
