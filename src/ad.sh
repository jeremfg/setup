# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Helpers for Active Directory configuration

if [[ -z ${GUARD_AD_SH+x} ]]; then
  GUARD_AD_SH=1
else
  return 0
fi

sssd_conf="/etc/sssd/sssd.conf"

ad_ubuntu_cinnamon_fix() {
  logInfo "Fixing Ubuntu Cinnamon configuration for AD login"

  if ! ad_fix_services; then
    logError "Failed to fix AD related services for AD login"
    return 1
  elif ! ad_fix_config; then
    logError "Failed to fix SSSD configuration for AD login"
    return 1
  elif ! ad_fix_sudoers; then
    logError "Failed to fix sudoers configuration for AD login"
    return 1
  elif ! ldm_fix; then
    logError "Failed to fix LightDM configuration for AD login"
    return 1
  else
    logDebug "Successfully fixed Ubuntu Cinnamon configuration for AD login"
  fi

  if [[ ${SSSD_RESTART} -eq 1 ]]; then
    logInfo "Restarting SSSD to apply changes"
    if ! sudo systemctl restart sssd; then
      logError "Failed to restart SSSD"
      return 1
    else
      logInfo "Successfully restarted SSSD"
    fi
  else
    logDebug "SSSD restart not required"
  fi

  return 0
}

ad_fix_sudoers() {
  local sudoers_file="/etc/sudoers.d/ad-sudoers"

  local file_content=$(cat <<EOF
# Allow members of the "Domain Admins" group to have sudo access
"%domain admins" ALL=(ALL:ALL) ALL

# Allow members of the "admins" group to have sudo access
"%admins" ALL=(ALL:ALL) ALL
EOF
)

  # Write the file
  if ! echo "${file_content}" | sudo tee "${sudoers_file}" >/dev/null; then
    logError "Failed to write AD sudoers file: ${sudoers_file}"
    return 1
  else
    logInfo "Successfully wrote AD sudoers file: ${sudoers_file}"
  fi

  return 0
}


ad_fix_config() {
  local cfg1="ad_gpo_access_control"
  local val1="permissive"
  local cfg2="krb5_store_password_if_offline"
  local val2="True"
  local cfg3="cache_credentials"
  local val3="True"
  local cfg4="ldap_id_mapping"
  local val4="True"
  local cfg5="use_fully_qualified_names"
  local val5="False"

  if ! ad_fix_sssd "${cfg1}" "${val1}"; then
    return 1
  elif ! ad_fix_sssd "${cfg2}" "${val2}"; then
    return 1
  elif ! ad_fix_sssd "${cfg3}" "${val3}"; then
    return 1
  elif ! ad_fix_sssd "${cfg4}" "${val4}"; then
    return 1
  elif ! ad_fix_sssd "${cfg5}" "${val5}"; then
    return 1
  else
    logDebug "Successfully fixed SSSD configuration for AD login"
  fi
}

# Fix a setting in SSSD configuration
# Parameters:
#   $1: Setting name
#   $2: Setting value
ad_fix_sssd() {
  local setting="$1"
  local value="$2"

  if [[ -z "${setting}" || -z "${value}" ]]; then
    logError "Missing setting or value for ad_fix_sssd"
    return 1
  fi

  # Find the setting in the config, knowing it could be prefixed with anything.
  if ! sudo grep -E "^.*${setting}\s*=" "${sssd_conf}" >/dev/null; then
    logError "SSSD setting not found in config file: ${setting}"
    # Append the config at the end of the file
    if ! echo -e "\n${setting} = ${value}" | sudo tee -a "${sssd_conf}" >/dev/null; then
      logError "Failed to append SSSD setting to config file: ${setting}"
      return 1
    else
      SSSD_RESTART=1
      logInfo "Successfully appended SSSD setting to config file: ${setting}"
    fi
  # Make sure the setting is only present once in the file
  elif ! sudo grep -E "^.*${setting}\s*=" "${sssd_conf}" | wc -l | grep -E "^\s*1\s*$" >/dev/null; then
    logError "SSSD setting is present multiple times in config file: ${setting}"
    return 1
  fi

  # If we already have the exact line, don't do anything
  if sudo grep -E "^${setting} = ${value}$" "${sssd_conf}" >/dev/null; then
    logDebug "SSSD setting already has the desired value, skipping: ${setting}"
  else
    # Replace the line with the new value, keeping any prefix (e.g. "#")
    if ! sudo sed -i -E "s|^.*${setting}\s*=.*$|${setting} = ${value}|g" "${sssd_conf}"; then
      logError "Failed to update SSSD setting in config file: ${setting}"
      return 1
    else
      SSSD_RESTART=1
      logInfo "Successfully updated SSSD setting in config file: ${setting}"
    fi
  fi

  return 0
}

ad_fix_services() {
  local srv1="sssd-nss.socket"
  local srv2="sssd-pam.socket"
  local srv3="sssd-pac.socket"
  if ! ad_end_service "${srv1}"; then
    logError "Failed to end service: ${srv1}"
    return 1
  elif ! ad_end_service "${srv2}"; then
    logError "Failed to end service: ${srv2}"
    return 1
  elif ! ad_end_service "${srv3}"; then
    logError "Failed to end service: ${srv3}"
    return 1
  else
    logDebug "Successfully ended AD related services"
  fi

  return 0
}

# Disable and stop the given AD service
# Parameters:
#   $1: Service name
ad_end_service() {
  local srv="$1"
  logInfo "Ending AD related service: ${srv}"

  # 1. Check if service is enabled, if so disable it
  # 2. Check if service is active, if so stop it
  if [[ -z "${srv}" ]]; then
    logError "Missing service name for ad_end_service"
    return 1
  elif sudo systemctl is-enabled "${srv}" &>/dev/null; then
    logDebug "Disabling service: ${srv}"
    if ! sudo systemctl disable "${srv}"; then
      logError "Failed to disable service: ${srv}"
      return 1
    else
      logInfo "Successfully disabled service: ${srv}"
    fi
  else
    logDebug "Service is not enabled, skipping disable: ${srv}"
  fi

  if sudo systemctl is-active "${srv}" &>/dev/null; then
    logDebug "Stopping service: ${srv}"
    if ! sudo systemctl stop "${srv}"; then
      logError "Failed to stop service: ${srv}"
      return 1
    else
      SSSD_RESTART=1
      logInfo "Successfully stopped service: ${srv}"
    fi
  else
    logDebug "Service is not active, skipping stop: ${srv}"
  fi

  return 0
}

SSSD_RESTART=0

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
AD_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${AD_SOURCE}" ]]; do # resolve $AD_SOURCE until the file is no longer a symlink
  AD_ROOT=$(cd -P "$(dirname "${AD_SOURCE}")" >/dev/null 2>&1 && pwd)
  AD_SOURCE=$(readlink "${AD_SOURCE}")
  [[ ${AD_SOURCE} != /* ]] && AD_SOURCE=${AD_ROOT}/${AD_SOURCE} # if $AD_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
AD_ROOT=$(cd -P "$(dirname "${AD_SOURCE}")" >/dev/null 2>&1 && pwd)
AD_ROOT=$(realpath "${AD_ROOT}/..")

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
elif ! source "${AD_ROOT}/src/lightdm.sh"; then
  logFatal "Failed to import lightdm.sh"
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
