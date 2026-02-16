# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Hostname management utilities

if [[ -z ${GUARD_HOSTNAME_SH+x} ]]; then
  GUARD_HOSTNAME_SH=1
else
  return 0
fi

# Verify hostname matches expected name and set it if different
#
# Parameters:
#   $1[in]: Expected hostname
# Returns:
#   0: Hostname is correct or was successfully set
#   1: Failed to set hostname
hostname_configure() {
  local expected_name="$1"
  local current_hostname

  if [[ -z "${expected_name}" ]]; then
    logError "Expected hostname not provided"
    return 1
  fi

  current_hostname=$(hostname)

  if [[ "${current_hostname}" == "${expected_name}" ]]; then
    logInfo "Hostname already correct: ${current_hostname}"
    return 0
  fi

  logWarn "Hostname mismatch: expected '${expected_name}', but found '${current_hostname}'"
  logInfo "Setting hostname to: ${expected_name}"

  # Set the hostname temporarily
  if ! sudo hostnamectl set-hostname "${expected_name}"; then
    logError "Failed to set hostname"
    return 1
  fi

  # Verify the change
  current_hostname=$(hostname)
  if [[ "${current_hostname}" == "${expected_name}" ]]; then
    logInfo "Hostname successfully set to: ${current_hostname}"
    return 0
  else
    logError "Hostname verification failed after setting"
    return 1
  fi
}

# Get the current hostname
#
# Parameters:
#   $1[out]: Current hostname
# Returns:
#   0: Success
hostname_get() {
  local _hostname="$1"
  local current_hostname

  current_hostname=$(hostname)
  eval "${_hostname}='${current_hostname}'"
  return 0
}

###########################
###### Startup logic ######
###########################

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
