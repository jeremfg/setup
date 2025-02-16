# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# IPMI utilities

# Prevent sourcing this script
if [[ -z ${GUARD_IPMI_SH} ]]; then
  GUARD_IPMI_SH=1
else
  logWarn "Re-sourcing ipmi.sh"
  return 0
fi

# Establish a remote IPMI connection
#
# Parameters:
#   $1[in]: Host of the IPMI
#   $2[in]: Username of the IPMI
#   $3[in]: Password of the IPMI
# Returns:
#   0: If the connection was successful
#   1: If an error occurred
ipmi_connect() {
  local __host="${1}"
  local __user="${2}"
  local __pwd="${3}"

  if [[ -z ${__host} ]]; then
    logError "Host not specified"
    return 1
  elif [[ -z ${__user} ]]; then
    logError "User not specified"
    return 1
  elif [[ -z ${__pwd} ]]; then
    logError "Password not specified"
    return 1
  fi

  if ! command -v ipmitool &>/dev/null; then
    logError "ipmitool not found"
    return 1
  fi

  local __cmd __res
  tmp_login=("-I" "lanplus" "-H" "${__host}" "-U" "${__user}" "-P" "${__pwd}")

  if ! __res=$(ipmitool "${tmp_login[@]}" "chassis" "status" 2>&1); then
    logError "Failed to connect to IPMI${IFS}${__res}"
    return 1
  else
    IPMI_LOGIN=("${tmp_login[@]}")
    logInfo "Connected to IPMI: ${__host}"
    return 0
  fi
}

# Disconnect from the IPMI
ipmi_disconnect() {
  IPMI_LOGIN=()
}

# Execute an IPMI command
#
# Parameters:
#   $1[out]: The variable to store the result
#   $@[in] : The command to execute
# Returns:
#   0: If the command was successfully executed
#   @: If an error occurred
ipmi_exec() {
  local __ipmi_result_stdout="${1}"
  shift

  if ! command -v ipmitool &>/dev/null; then
    logError "ipmitool not found"
    return 1
  fi

  local __actual_cmd __printable_cmd __result __return_code
  if [[ -z "${IPMI_LOGIN[*]}" ]]; then
    __actual_cmd=(ipmitool "${@}")
    __printable_cmd=(ipmitool "${@}")
  else
    __actual_cmd=(ipmitool "${IPMI_LOGIN[@]}" "${@}")
    __printable_cmd=(ipmitool "${IPMI_LOGIN[@]}" "${@}")
    __printable_cmd[8]="********"
  fi

  logTrace "Executing IPMI command: ${__printable_cmd[*]}"
  __result=$("${__actual_cmd[@]}" 2>&1)
  __return_code=$?

  if [[ ${__return_code} -ne 0 ]]; then
    logError <<EOF
Failed to Execute IPMI command: ${__printable_cmd[*]}

Return Code: ${__return_code}
Output:
${__result}
EOF
  else
    logTrace "IPMI command executed successfully${IFS}${__result}"
  fi

  eval "${__ipmi_result_stdout}='${__result}'"

  return "${__return_code}"
}

# Get the power status of the machine
#
# Parameters:
#   $0[out]: The power status. One of "on" or "off"
# Returns:
#   0: If the power status was retrieved
#   1: If an error occurred
ipmi_power_status() {
  local __result_status="${1}"

  local __read_result
  if ! ipmi_exec __read_result "power" "status"; then
    logError "Failed to get power status"
    return 1
  elif [[ "${__read_result}" == *"Chassis Power is on"* ]]; then
    eval "${__result_status}='on'"
    return 0
  elif [[ "${__read_result}" == *"Chassis Power is off"* ]]; then
    eval "${__result_status}='off'"
    return 0
  else
    logError "Unknown power status"
    return 1
  fi
}

# Power on the machine
#
# Returns:
#   0: If the machine was powered on
#   1: If an error occurred
ipmi_power_on() {

  local __result_status
  if ! ipmi_exec __result_status "power" "on"; then
    logError "Failed to power on machine"
    return 1
  elif [[ "${__result_status}" == *"Up/On"* ]]; then
    logInfo "Machine powered on"
  else
    logError "Failed to power on machine"
    return 1
  fi

  # Wait for the machine to report as powered on
  local end_time
  end_time=$(($(date +%s) + 10))
  while true; do
    sleep 1
    if ! ipmi_power_status __result_status; then
      logError "Failed to get power status"
      return 1
    elif [[ "${__result_status}" == "on" ]]; then
      logInfo "Machine powered on"
      return 0
    elif [[ $(date +%s || true) -gt ${end_time} ]]; then
      logError "Machine did not power on"
      return 1
    fi
  done
}

# Power off the machine
#
# Returns:
#   0: If the machine was signaled to power off
#   1: If an error occurred
ipmi_power_off() {

  local __result_status
  if ! ipmi_exec __result_status "power" "off"; then
    logError "Failed to power off machine"
    return 1
  elif [[ "${__result_status}" == *"Down/Off"* ]]; then
    logInfo "Machine powered off"
    return 0
  else
    logError "Failed to power off machine"
    return 1
  fi
}

# Wait for the machine to be off
#
# Parameters:
#   $0[in]: The maximum time to wait (in seconds)
# Returns:
#   0: If the machine is off
#   1: If an error occurred
ipmi_wait_off() {
  local __max_time="${1}"

  local __result_status end_time
  end_time=$(($(date +%s) + __max_time))
  while true; do
    if ! ipmi_power_status __result_status; then
      logError "Failed to get power status"
      return 1
    elif [[ "${__result_status}" == "off" ]]; then
      logInfo "Machine is off"
      return 0
    elif [[ $(date +%s || true) -gt ${end_time} ]]; then
      logError "Machine did not power off"
      return 1
    fi
    sleep 1
  done
}

# Global variables
if [[ -z ${IPMI_LOGIN} ]]; then IPMI_LOGIN=(); fi

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
IPMI_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${IPMI_SOURCE}" ]]; do # resolve $IPMI_SOURCE until the file is no longer a symlink
  IPMI_ROOT=$(cd -P "$(dirname "${IPMI_SOURCE}")" >/dev/null 2>&1 && pwd)
  IPMI_SOURCE=$(readlink "${IPMI_SOURCE}")
  [[ ${IPMI_SOURCE} != /* ]] && IPMI_SOURCE=${IPMI_ROOT}/${IPMI_SOURCE} # if $IPMI_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
IPMI_ROOT=$(cd -P "$(dirname "${IPMI_SOURCE}")" >/dev/null 2>&1 && pwd)
IPMI_ROOT=$(realpath "${IPMI_ROOT}/..")

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
