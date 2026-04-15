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

ad_support_automount() {
  if ! pkg_install "ipcalc" "cifs-utils" "krb5-user"; then
    logError "Failed to install ipcalc for AD automount support"
    return 1
  else
    logDebug "Successfully installed ipcalc for AD automount support"
  fi
}

# Retrieve the local NetBIOS name
# Parameters:
#   $1[out]: The NetBIOS name
ad_netbios_name() {
  local __result_var="${1}"

  local output
  # Retrieve the NetBIOS name using testparm, suppressing errors and taking the last line
  if ! output=$(testparm -s --parameter-name="netbios name" 2>/dev/null | tail -n 1 | tr -d '[:space:]'); then
    logError "Failed to retrieve NetBIOS name using testparm"
    return 1
  elif [[ -z "${output}" ]]; then
    logError "NetBIOS name is empty"
    return 1
  fi

  # Return the result in the provided variable name
  eval "${__result_var}='${output}'"
  logInfo "Successfully retrieved NetBIOS name: ${output}"

  return 0
}

# Retrieve the local AD domain FQDN
# Parameters:
#   $1[out]: The AD domain FQDN
ad_domain_fqdn() {
  local __result_var="${1}"

  local output
  # Retrieve the domain FQDN using testparm, suppressing errors and taking the last line
  if ! output=$(realm list | awk '/domain-name/ {print $2}'); then
    logError "Failed to retrieve AD domain FQDN using testparm"
    return 1
  elif [[ -z "${output}" ]]; then
    logError "AD domain FQDN is empty"
    return 1
  fi

  # Return the result in the provided variable name
  eval "${__result_var}='${output}'"
  logInfo "Successfully retrieved AD domain FQDN: ${output}"

  return 0
}

ad_install_sysvol() {
  local _src="${AD_ROOT}/data/sysvol_refresh.sh"
  local _dst="/usr/local/bin/sysvol_refresh.sh"
  local _sysvol_cache="/var/cache/sysvol"
  local _ad_entry="/usr/local/bin/ad_pam_event.sh"
  local _domain

  # Check we have the dependencies we need
  if [ ! -f "${_src}" ]; then
    logError "SYSVOL refresh script not found at ${_src}"
    return 1
  elif ! ad_domain_fqdn _domain; then
    logError "Failed to retrieve AD domain FQDN for SYSVOL cache setup"
    return 1
  fi

  # Set-up the SYSVOL cache directory
  if [[ ! -e "${_sysvol_cache}" || ! -d ${_sysvol_cache} ]]; then
    if ! sudo rm -rf "${_sysvol_cache}"; then
      logError "Failed to remove existing SYSVOL cache path at ${_sysvol_cache}"
      return 1
    elif ! sudo mkdir -p "${_sysvol_cache}"; then
      logError "Failed to create SYSVOL cache directory at ${_sysvol_cache}"
      return 1
    elif ! sudo chown -R root:"domain users" "${_sysvol_cache}"; then
      logError "Failed to set ownership of SYSVOL cache directory at ${_sysvol_cache}"
      return 1
    elif ! sudo chmod -R 770 "${_sysvol_cache}"; then
      logError "Failed to set permissions of SYSVOL cache directory at ${_sysvol_cache}"
      return 1
    else
      logInfo "Successfully set up SYSVOL cache directory at ${_sysvol_cache}"
    fi
  fi

  # Install the cache refresh script
  if ! sudo cp "${_src}" "${_dst}"; then
    logError "Failed to copy SYSVOL refresh script from ${_src} to ${_dst}"
    return 1
  elif ! sudo chown root:"domain users" "${_dst}"; then
    logError "Failed to set ownership of SYSVOL refresh script at ${_dst}"
    return 1
  elif ! sudo chmod 750 "${_dst}"; then
    logError "Failed to set permissions of SYSVOL refresh script at ${_dst}"
    return 1
  else
    logInfo "Successfully installed SYSVOL refresh script to ${_dst} with cache directory at ${_sysvol_cache}"
  fi

  # Create the hook script to be run at login
  local hook_content=$(cat <<EOF
#!/bin/env sh
# SPDX-License-Identifier: MIT
#
# Script executed at logon to apply SYSVOL
# Installed by setup's ad.sh

ENTRYPOINT="${_sysvol_cache}/${_domain}/${LOGON_ENTRY_REL}"
LOGGER_NAME="ad-pam-event-hook"

on_login() {
  (
    logger -t "\${LOGGER_NAME}" "Login event detected, running logon for \${PAM_USER}"

    # Run the refresh script, suppressing all output
    if ! ${_dst}; then
      logger -t "\${LOGGER_NAME}" "Error executing SYSVOL refresh script at ${_dst}"
    fi

    # Run the actual scripting
    if [ -f "\${ENTRYPOINT}" ]; then
      if ! \${ENTRYPOINT}; then
        logger -t "\${LOGGER_NAME}" "Error executing logon script at \${ENTRYPOINT}"
      fi
    else
      logger -t "\${LOGGER_NAME}" "No logon script found at \${ENTRYPOINT}, skipping"
    fi
  ) &

  return 0
}

on_logout() {
  logger -t "\${LOGGER_NAME}" "Logout event detected for \${PAM_USER}"
  return 0
}

logger -t "\${LOGGER_NAME}" "User: \${USER}, User Id: \$(id -u), Group Id: \$(id -g)"
logger -t "\${LOGGER_NAME}" "PamUser: \${PAM_USER}, PamUserId: \${PAM_UID}, PamGroupId: \${PAM_GID}"

result=0
case "\${PAM_TYPE}" in
  "open_session")
    on_login
    result="\${?}"
    ;;
  "close_session")
    on_logout
    result="\${?}"
    ;;
  *)
    logger -t "\${LOGGER_NAME}" "Invalid argument received: \$1"
    result=1
    ;;
esac

if [ "\${result}" -ne 0 ]; then
  logger -t "\${LOGGER_NAME}" "Error executing AD logon hook script: \${result}"
else
  logger -t "\${LOGGER_NAME}" "Successfully executed AD logon hook script"
fi

EOF
)
  if ! echo "${hook_content}" | sudo tee "${_ad_entry}" >/dev/null; then
    logError "Failed to create AD logon hook script at ${_ad_entry}"
    return 1
  elif ! sudo chown root:"domain users" "${_ad_entry}"; then
    logError "Failed to set ownership of AD logon hook script at ${_ad_entry}"
    return 1
  elif ! sudo chmod 750 "${_ad_entry}"; then
    logError "Failed to set permissions of AD logon hook script at ${_ad_entry}"
    return 1
  else
    logInfo "Successfully created AD logon hook script at ${_ad_entry}"
  fi

  # Install the login hook
  local pam_file="/etc/pam.d/common-session"
  local pam_line="session optional pam_exec.so seteuid ${_ad_entry}"
  if ! sudo grep -F "${pam_line}" "${pam_file}" >/dev/null; then
    if ! echo "${pam_line}" | sudo tee -a "${pam_file}" >/dev/null; then
      logError "Failed to add AD logon hook to PAM configuration in ${pam_file}"
      return 1
    else
      logInfo "Successfully added AD logon hook to PAM configuration in ${pam_file}"
    fi
  else
    logDebug "AD logon hook already present in PAM configuration, skipping: ${pam_line}"
  fi

  return 0
}

LOGON_ENTRY_REL="scripts/logon.sh"
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
