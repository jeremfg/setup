# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure NUT (Network UPS Tools)
# This was developed to support the following:
# - Cyberpower CP1500PFCLCD

if [[ -z ${GUARD_NUT_SH} ]]; then
  GUARD_NUT_SH=1
else
  return 0
fi

# Configure the NUT package
#
# Parameters:
#   $1[in]: NUT MODE
#   $2[in]: Name of variable containing the UPS driver definition (server only)
#   $3[in]: Name of variable containing the daemon definition (server only)
#   $4[in]: Name of variable containing the user definition (server only)
#   $5[in]: Name of variable containing the monitoring definition
#   $6[in]: Name of variable containing the scheduler definition
nut_setup() {
  local _nut_mode="${1}"
  local _nut_driver="${2}"
  local _nut_daemon="${3}"
  local _nut_user="${4}"
  local _nut_monitor="${5}"
  local _nut_scheduler="${6}"

  # Validate parameters
  case ${_nut_mode} in
  none)
    logInfo "NUT disabled"
    ;;
  standalone | netserver)
    if [[ -z ${_nut_driver} ]]; then
      logError "UPS driver not specified"
      return 1
    fi
    if [[ -z ${_nut_daemon} ]]; then
      logError "NUT daemon not specified"
      return 1
    fi
    if [[ -z ${_nut_user} ]]; then
      logError "NUT user not specified"
      return 1
    fi
    if [[ -z "${!_nut_driver}" ]]; then
      logError "UPS driver not defined"
      return 1
    fi
    if [[ -z "${!_nut_daemon}" ]]; then
      logError "NUT daemon not defined"
      return 1
    fi
    if [[ -z "${!_nut_user}" ]]; then
      logError "NUT user not defined"
      return 1
    fi
    ;& # Fallthrough
  netclient)
    if [[ -z ${_nut_monitor} ]]; then
      logError "NUT monitor not specified"
      return 1
    fi
    if [[ -z ${_nut_scheduler} ]]; then
      logError "NUT scheduler not specified"
      return 1
    fi
    if [[ -z "${!_nut_monitor}" ]]; then
      logError "NUT monitor not defined"
      return 1
    fi
    if [[ -z "${!_nut_scheduler}" ]]; then
      logError "NUT scheduler not defined"
      return 1
    fi
    ;;
  *)
    logError "NUT mode not supported: ${_nut_mode}"
    return 1
    ;;
  esac

  # Install packages
  local req_pkgs=("nut-client")
  if [[ "${_nut_mode}" == "netserver" ]] || [[ "${_nut_mode}" == "standalone" ]]; then
    req_pkgs+=("nut")
  fi
  if ! pkg_install_from epel "${req_pkgs[@]}"; then
    logError "Failed to install NUT"
    return 1
  fi

  # Configure NUT according to selected mode
  if ! nut_set_mode "${_nut_mode}"; then
    logError "Failed to configure NUT as ${_nut_mode}"
    return 1
  fi

  if [[ "${_nut_mode}" == "none" ]]; then
    if ! nut_restart; then
      return 1
    fi
    return 0
  fi

  if [[ "${_nut_mode}" == "netserver" ]] || [[ "${_nut_mode}" == "standalone" ]]; then
    if ! nut_configure_server "${_nut_driver}" "${_nut_daemon}" "${_nut_user}"; then
      return 1
    fi
  fi

  if ! nut_configure_monitor "${_nut_monitor}" "${_nut_scheduler}"; then
    return 1
  fi

  if ! nut_restart; then
    return 1
  fi

  # Make sure NUT is enabled at bootup
  if ! systemctl enable nut.target nut-driver.target; then
    logError "Failed to enable NUT at bootup"
    return 1
  fi

  return 0
}

# Set NUT mode of operation
#
# Parameters:<
#   $1: Mode of operation (netserver)
# Returns:
#   0: Success
#   1: Failure
nut_set_mode() {
  local MODE=$1

  if [[ -z ${MODE} ]]; then
    logError "Mode not specified"
    return 1
  fi

  case ${MODE} in
  none | standalone | netserver | netclient) ;;
  *)
    logError "Mode not supported: ${MODE}"
    return 1
    ;;
  esac

  local nut_cfg="/etc/ups/nut.conf"
  if [[ ! -f ${nut_cfg} ]]; then
    logError "NUT configuration file not found: ${nut_cfg}"
    return 1
  fi

  # Read current mode
  local current_mode
  current_mode=$(grep -E "^MODE=" "${nut_cfg}" | cut -d'=' -f2 || true)
  if [[ -z ${current_mode} ]]; then
    logError "Failed to read current mode"
    return 1
  fi

  if [[ "${current_mode}" == "${MODE}" ]]; then
    logInfo "NUT mode already set to: ${MODE}"
    return 0
  fi

  # Create backup of configuration file
  local backup_file
  if ! os_get_next_filename backup_file "${nut_cfg}.bak"; then
    logError "Failed to get backup filename for ${nut_cfg}"
    return 1
  fi

  if ! cp "${nut_cfg}" "${backup_file}"; then
    logError "Failed to backup NUT configuration"
    return 1
  fi

  # Update mode
  if ! sed -i "s/^MODE=.*/MODE=${MODE}/" "${nut_cfg}"; then
    logError "Failed to update NUT mode"
    return 1
  else
    logInfo "NUT mode updated to: ${MODE}"
  fi

  NUT_RESTART_REQUIRED=1
  return 0
}

nut_configure_server() {
  local driver="${1}"
  local daemon="${2}"
  local user="${3}"

  if ! nut_configure_file "/etc/ups/ups.conf" "${driver}"; then
    return 1
  fi

  if ! nut_configure_file "/etc/ups/upsd.conf" "${daemon}"; then
    return 1
  fi

  if ! nut_configure_file "/etc/ups/upsd.users" "${user}"; then
    return 1
  fi

  logInfo "NUT server configured successfully"
  return 0
}

nut_configure_monitor() {
  local monitor="${1}"
  local scheduler="${2}"

  if ! nut_configure_file "/etc/ups/upsmon.conf" "${monitor}"; then
    return 1
  fi

  if ! nut_configure_file "/etc/ups/upssched.conf" "${scheduler}"; then
    return 1
  fi

  logInfo "NUT monitor configured successfully"
  return 0
}

nut_configure_file() {
  local file="${1}"
  local file_content_var="${2}"

  if [[ -z ${file} ]]; then
    logError "File not specified"
    return 1
  fi
  if [[ -z ${file_content_var} ]]; then
    logError "File content variable not specified"
    return 1
  fi
  if [[ -z "${!file_content_var}" ]]; then
    logError "File content not defined"
    return 1
  fi

  if [[ -f "${file}" ]]; then
    # Compare file content, see if it needs updating
    if ! diff -q <(echo "${!file_content_var}") "${file}" >/dev/null; then
      logInfo "File ${file} needs updating"

      # Backup current configuration
      local backup_file
      if ! os_get_next_filename backup_file "${file}.bak"; then
        logError "Failed to get backup filename for ${file}"
        return 1
      fi
      if ! cp "${file}" "${backup_file}"; then
        logError "Failed to backup NUT configuration file: ${file}"
        return 1
      fi

      # Write new configuration
      if ! echo "${!file_content_var}" >"${file}"; then
        logError "Failed to update ${file}"
        return 1
      fi

      NUT_RESTART_REQUIRED=1
      logInfo "Updated ${file} succesfully"
    else
      logInfo "File ${file} is up-to-date"
    fi
  else
    # File does not exist, create it
    logWarn "Unexpectedly, File ${file} did not exist. Creating one..."
    if ! echo "${!file_content_var}" >"${file}"; then
      logError "Failed to create ${file}"
      return 1
    fi

    NUT_RESTART_REQUIRED=1
    logInfo "Created ${file} succesfully"
  fi

  # shellcheck disable=SC2312
  return 0
}

# Restart services if needed
nut_restart() {
  if [[ ${NUT_RESTART_REQUIRED} -eq 1 ]]; then
    local services=("nut-monitor")
    # Check if nut-server.service exists
    # shellcheck disable=SC2312
    if systemctl list-unit-files | grep -q "nut-server.service"; then
      # NUT server is also installed
      services+=("nut-server" "nut-driver-enumerator")
    fi

    # Make sure those services are enabled
    if ! systemctl enable "${services[@]}"; then
      logError "Failed to enable NUT services: ${services[*]}"
      return 1
    fi

    # Restart services
    if ! systemctl restart "${services[@]}"; then
      logError "Failed to restart NUT service: ${services[*]}"
      return 1
    fi

    logInfo "Restarted NUT services successfully"
  fi
  return 0
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
NU_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${NU_SOURCE}" ]]; do # resolve $NU_SOURCE until the file is no longer a symlink
  NU_ROOT=$(cd -P "$(dirname "${NU_SOURCE}")" >/dev/null 2>&1 && pwd)
  NU_SOURCE=$(readlink "${NU_SOURCE}")
  [[ ${NU_SOURCE} != /* ]] && NU_SOURCE=${NU_ROOT}/${NU_SOURCE} # if $NU_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
NU_ROOT=$(cd -P "$(dirname "${NU_SOURCE}")" >/dev/null 2>&1 && pwd)
NU_ROOT=$(realpath "${NU_ROOT}/..")

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
if ! source "${NU_ROOT}/src/pkg.sh"; then
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
