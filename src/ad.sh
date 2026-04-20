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
  elif ! ad_fix_sssd_conf; then
    logError "Failed to fix SSSD configuration for AD login"
    return 1
  elif ! ad_fix_krb5_conf; then
    logError "Failed to fix KRB5 configuration for AD login"
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

  ad_sssd_restart

  return 0
}

ad_sssd_restart() {
  if [[ ${SSSD_RESTART} -eq 1 ]]; then
    logInfo "Restarting SSSD to apply changes"
    if ! sudo systemctl restart sssd; then
      logError "Failed to restart SSSD"
      return 1
    else
      SSD_RESTART=0
      logInfo "Successfully restarted SSSD"
    fi
  else
    logDebug "SSSD restart not required"
  fi
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

ad_fix_krb5_conf() {

  if ! ad_fix_krb5 "rdns" "false"; then
    return 1
  elif ! ad_fix_krb5 "dns_canonicalize_hostname" "false"; then
    return 1
  elif ! ad_fix_krb5 "default_ccache_name" "KCM:"; then
    return 1
  elif ! pkg_install "krb5-user"; then
    logError "krb5-user is required for AD login support scripts"
    return 1
  else
    logDebug "Successfully fixed KRB5 configuration for AD login"
  fi
  return 0
}

# Fix a setting in KRB5 configuration
# Parameters:
#   $1: Setting name
#   $2: Setting value
ad_fix_krb5() {
  local __setting="${1}"
  local __value="${2}"
  local krb5_conf="/etc/krb5.conf"

  if [[ -z "${__setting}" || -z "${__value}" ]]; then
    logError "Missing setting or value for ad_fix_krb5"
    return 1
  elif [[ -f "${krb5_conf}" ]]; then
    if ! file_ensure_ini; then
      logError "Failed to ensure INI format for KRB5 config file at ${krb5_conf}"
      return 1
    elif ! sudo crudini --set "${krb5_conf}" libdefaults "${__setting}" "${__value}"; then
      logError "Failed to set KRB5 config setting ${__setting} to ${__value} in file ${krb5_conf}"
      return 1
    else
      logInfo "Successfully set KRB5 config setting ${__setting}=${__value}"
    fi
  else
    logError "KRB5 config file not found at expected location: ${krb5_conf}"
    return 1
  fi
}

ad_fix_sssd_conf() {

  if ! ad_fix_sssd "ad_gpo_access_control" "permissive"; then
    return 1
  elif ! ad_fix_sssd "krb5_store_password_if_offline" "True"; then
    return 1
  elif ! ad_fix_sssd "cache_credentials" "True"; then
    return 1
  elif ! ad_fix_sssd "ldap_id_mapping" "True"; then
    return 1
  elif ! ad_fix_sssd "use_fully_qualified_names" "False"; then
    return 1
  elif ! ad_fix_sssd "krb5_auth_timeout" "15"; then
    return 1
  # elif ! ad_fix_sssd "krb5_ccachedir" "/tmp"; then
  #   return 1
  # elif ! ad_fix_sssd "krb5_ccname_template" "FILE:%d/krb5cc_%U"; then
  #   return 1
  elif ! ad_fix_sssd "krb5_use_kcm" "True"; then
    return 1
  elif ! ad_fix_sssd "krb5_auth" "True"; then
    return 1
  elif ! ad_fix_sssd "auth_provider" "krb5"; then
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
  local refresh_src="${AD_ROOT}/data/sysvol_refresh.sh"
  local refresh_dst="/usr/local/bin/$(basename "${refresh_src}")"
  local sysvol_cache="/var/cache/sysvol"
  local service_unit="/etc/systemd/user/${LOGON_SRV_NAME}.service"
  local path_unit="/etc/systemd/user/${LOGON_SRV_NAME}.path"
  local pam_wrapper="/usr/local/bin/${LOGON_SRV_NAME}_pamhook.sh"
  local user_wrapper="/usr/local/bin/${LOGON_SRV_NAME}_userhook.sh"
  local lock_file_rel=".local/state/${LOGON_SRV_NAME}.lock"
  local ready_file_rel=".local/state/${LOGON_SRV_NAME}_ready"

  local _domain

  # Check we have the dependencies we need
  if [ ! -f "${refresh_src}" ]; then
    logError "SYSVOL refresh script not found at ${refresh_src}"
    return 1
  elif ! ad_domain_fqdn _domain; then
    logError "Failed to retrieve AD domain FQDN for SYSVOL cache setup"
    return 1
  fi

  # Set-up the SYSVOL cache directory
  if [[ ! -e "${sysvol_cache}" || ! -d ${sysvol_cache} ]]; then
    if ! sudo rm -rf "${sysvol_cache}"; then
      logError "Failed to remove existing SYSVOL cache path at ${sysvol_cache}"
      return 1
    elif ! sudo mkdir -p "${sysvol_cache}"; then
      logError "Failed to create SYSVOL cache directory at ${sysvol_cache}"
      return 1
    elif ! sudo chown -R root:"domain users" "${sysvol_cache}"; then
      logError "Failed to set ownership of SYSVOL cache directory at ${sysvol_cache}"
      return 1
    elif ! sudo chmod -R 770 "${sysvol_cache}"; then
      logError "Failed to set permissions of SYSVOL cache directory at ${sysvol_cache}"
      return 1
    else
      logInfo "Successfully set up SYSVOL cache directory at ${sysvol_cache}"
    fi
  fi

  # Install the cache refresh script
  if ! sudo cp "${refresh_src}" "${refresh_dst}"; then
    logError "Failed to copy SYSVOL refresh script from ${refresh_src} to ${refresh_dst}"
    return 1
  elif ! sudo chown root:"domain users" "${refresh_dst}"; then
    logError "Failed to set ownership of SYSVOL refresh script at ${refresh_dst}"
    return 1
  elif ! sudo chmod 750 "${refresh_dst}"; then
    logError "Failed to set permissions of SYSVOL refresh script at ${refresh_dst}"
    return 1
  else
    logInfo "Successfully installed SYSVOL refresh script to ${refresh_dst} with cache directory at ${sysvol_cache}"
  fi

  # Create the hook script to be run by user services at login
  local user_content=$(cat <<EOF
#!/bin/env sh
# SPDX-License-Identifier: MIT
#
# User hook script run at login to apply SYSVOL GPOs
# Installed by setup's ad.sh

ENTRYPOINT="${sysvol_cache}/${_domain}/${LOGON_ENTRY_REL}"
LOGGER_NAME="${LOGON_SRV_NAME}"

on_login() {
  logger -t "\${LOGGER_NAME}" "Login event detected, running logon for \${USER}"

  # Run the actual scripting
  if [ -f "\${ENTRYPOINT}" ]; then
    logger -t "\${LOGGER_NAME}" "Executing SYSVOL logon script at \${ENTRYPOINT}"
    if ! \${ENTRYPOINT}; then
      logger -t "\${LOGGER_NAME}" "Error executing logon script"
      return 1
    else
      logger -t "\${LOGGER_NAME}" "Successfully executed logon script"
    fi
  else
    logger -t "\${LOGGER_NAME}" "No logon script found at \${ENTRYPOINT}, skipping"
  fi

  return 0
}

# Don't execute if ready file isn't there
if [ ! -f "\${HOME}/${ready_file_rel}" ]; then
  logger -t "\${LOGGER_NAME}" "Ready file \${HOME}/${ready_file_rel} not found. Exiting..."
  exit 0
fi

# Acquire Lock
exec 9>"\${HOME}/${lock_file_rel}"
flock -w 10 9 || {
  logger -t "\${LOGGER_NAME}" "Failed to acquire lock for logon script. Exiting."
  exit 0
}

result=0
on_login
result="\${?}"

if [ "\${result}" -ne 0 ]; then
  logger -t "\${LOGGER_NAME}" "Error executing AD logon hook script: \${result}"
  exit 0
else
  # Remove the ready file
  if ! rm -f "\${HOME}/${ready_file_rel}"; then
    logger -t "\${LOGGER_NAME}" "Failed to remove ready file at \${HOME}/${ready_file_rel}"
  else
    logger -t "\${LOGGER_NAME}" "Removed ready file at \${HOME}/${ready_file_rel}"
  fi
  logger -t "\${LOGGER_NAME}" "Successfully executed AD logon hook script"
  exit \${result}
fi

EOF
)
  if ! echo "${user_content}" | sudo tee "${user_wrapper}" >/dev/null; then
    logError "Failed to create AD logon hook script at ${user_wrapper}"
    return 1
  elif ! sudo chown root:"domain users" "${user_wrapper}"; then
    logError "Failed to set ownership of AD logon hook script at ${user_wrapper}"
    return 1
  elif ! sudo chmod 750 "${user_wrapper}"; then
    logError "Failed to set permissions of AD logon hook script at ${user_wrapper}"
    return 1
  else
    logInfo "Successfully created AD logon hook script at ${user_wrapper}"
  fi

  # Install user service to be run at login
  local service_content=$(cat <<EOF
[Unit]
Description=AD Logon Hook
After=default.target
ConditionUser=!root

[Service]
Type=oneshot
ExecStart=${user_wrapper}

[Install]
WantedBy=default.target
EOF
)

  if ! echo "${service_content}" | sudo tee "${service_unit}" >/dev/null; then
    logError "Failed to create systemd service for AD logon hook at ${service_unit}"
    return 1
  elif ! sudo chown root:root "${service_unit}"; then
    logError "Failed to set ownership of systemd service for AD logon hook at ${service_unit}"
    return 1
  elif ! sudo chmod 644 "${service_unit}"; then
    logError "Failed to set permissions of systemd service for AD logon hook at ${service_unit}"
    return 1
  else
    logInfo "Successfully created user service for future users"
  fi

# Install the path unit to trigger the user service on ready file creation in home directories
local path_content=$(cat <<EOF
[Unit]
Description=Path unit to trigger AD logon hook on home directory ready file creation
After=default.target

[Path]
PathExists=%h/${ready_file_rel}

[Install]
WantedBy=default.target
EOF
)

  if ! echo "${path_content}" | sudo tee "${path_unit}" >/dev/null; then
    logError "Failed to create systemd path unit for AD logon hook at ${path_unit}"
    return 1
  elif ! sudo chown root:root "${path_unit}"; then
    logError "Failed to set ownership of systemd path unit for AD logon hook at ${path_unit}"
    return 1
  elif ! sudo chmod 644 "${path_unit}"; then
    logError "Failed to set permissions of systemd path unit for AD logon hook at ${path_unit}"
    return 1
  else
    logInfo "Successfully created systemd path unit for AD logon hook"
  fi

  # Install PAM hook script
  local pam_content=$(cat <<EOF
#!/bin/env sh
# SPDX-License-Identifier: MIT
#
# PAM hook script on AD logon
# Installed by setup's ad.sh

LOGGER_NAME="${LOGON_SRV_NAME}"

# Get Username
ME_USER="\${USER}"
if [ -n "\${PAM_USER}" ]; then
  ME_USER="\${PAM_USER}"
  logger -t "\${LOGGER_NAME}" "PAM_USER is set to \${PAM_USER}"
fi
if [ -z "\${ME_USER}" ]; then
  logger -t "\${LOGGER_NAME}" "ME_USER is not set, skipping AD logon hook"
  exit 0
elif [ "\${ME_USER}" = "root" ]; then
  logger -t "\${LOGGER_NAME}" "ME_USER is root, skipping AD logon hook"
  exit 0
else
  logger -t "\${LOGGER_NAME}" "ME_USER is \${ME_USER}, proceeding with AD logon hook"
fi

# Get User Details
cur_id="\$(id -u "\${ME_USER}" 2>/dev/null)"
if [ -z "\${cur_id}" ]; then
  logger -t "\${LOGGER_NAME}" "Failed to retrieve user ID for \${ME_USER}"
  exit 0
fi
home_dir="\$(getent passwd "\${ME_USER}" | cut -d: -f6)"
if [ -z "\${home_dir}" ]; then
  logger -t "\${LOGGER_NAME}" "Failed to retrieve home directory for \${ME_USER}"
  exit 0
elif [ ! -d "\${home_dir}" ]; then
  logger -t "\${LOGGER_NAME}" "Home directory \${home_dir} does not exist for user \${ME_USER}"
  exit 0
elif ! mkdir -p "\${home_dir}/$(dirname "${ready_file_rel}")"; then
  logger -t "\${LOGGER_NAME}" "Failed to create state directory"
  exit 0
fi

# Check this is a login event
if [ -n "\${PAM_TYPE}" ]; then
  if [ "\${PAM_TYPE}" != "open_session" ]; then
    logger -t "\${LOGGER_NAME}" "PAM_TYPE is \${PAM_TYPE}, not a login event, skipping AD logon hook"
    exit 0
  else
    logger -t "\${LOGGER_NAME}" "PAM_TYPE is open_session, proceeding with AD logon hook"
  fi
else
  logger -t "\${LOGGER_NAME}" "PAM_TYPE is not set. Must be a manual execution. Proceeding..."
fi

# First Action? Make sure we remove a stale ready file
if [ -e "\${home_dir}/${ready_file_rel}" ]; then
  if ! rm -f "\${home_dir}/${ready_file_rel}"; then
    logger -t "\${LOGGER_NAME}" "Failed to cleanup stale ready file at \${home_dir}/${ready_file_rel}"
    exit 0
  else
    logger -t "\${LOGGER_NAME}" "Removed stale ready file at \${home_dir}/${ready_file_rel}"
  fi
fi

# Acquire Lock
exec 9>"\${home_dir}/${lock_file_rel}"
flock -n 9 || {
  logger -t "\${LOGGER_NAME}" "Failed to acquire lock for PAM hook. Exiting."
  exit 0
}

# Execute the rest as backgdound to avoid blocking the login

{
  # Refresh SYSVOL
  logger -t "\${LOGGER_NAME}" "Executing PAM hook $(basename ${refresh_dst}) for user \${PAM_USER}"
  $(command -v runuser) -u "\${ME_USER}" -- \
    env KRB5CCNAME="FILE:/tmp/krb5cc_\${cur_id}" "${refresh_dst}"
  ecode="\${?}"

  # Write Ready File
  if [ -f "\${home_dir}/${ready_file_rel}" ]; then
    logger -t "\${LOGGER_NAME}" "Ready file shouldn't exist. It did."
  else
    echo "\${ecode}" > "\${home_dir}/${ready_file_rel}"
  fi

  # Log Success/Failure and exit
  if [ "\${ecode}" -ne 0 ]; then
    logger -t "\${LOGGER_NAME}" "Error executing PAM hook: \${ecode}"
  else
    logger -t "\${LOGGER_NAME}" "Successfully executed PAM hook"
  fi
} &

EOF
)
  if ! echo "${pam_content}" | sudo tee "${pam_wrapper}" >/dev/null; then
    logError "Failed to create PAM hook script at ${pam_wrapper}"
    return 1
  elif ! sudo chown root:"domain users" "${pam_wrapper}"; then
    logError "Failed to set ownership of PAM hook script at ${pam_wrapper}"
    return 1
  elif ! sudo chmod 750 "${pam_wrapper}"; then
    logError "Failed to set permissions of PAM hook script at ${pam_wrapper}"
    return 1
  else
    logInfo "Successfully created PAM hook script at ${pam_wrapper}"
  fi

  # Add the PAM hook to common-session
  local pam_file="/etc/pam.d/common-session"
  local pam_line="session optional pam_exec.so seteuid ${pam_wrapper}"

  if ! sudo grep -F "${pam_line}" "${pam_file}" >/dev/null; then
    # Replace any line containing "pam_exec.so" with our line, if found
    if sudo grep "pam_exec.so" "${pam_file}" >/dev/null; then
      if ! sudo sed -i -E "s|^.*pam_exec.so.*$|${pam_line}|g" "${pam_file}"; then
        logError "Failed to update existing pam_exec line in ${pam_file} with AD logon hook"
        return 1
      else
        logInfo "Successfully updated existing pam_exec line in ${pam_file} with AD logon hook"
      fi
    else
      # Otherwise, append our line at the end of the file
      if ! echo "${pam_line}" | sudo tee -a "${pam_file}" >/dev/null; then
        logError "Failed to append PAM hook line to ${pam_file}"
        return 1
      else
        logInfo "Successfully appended PAM hook line to ${pam_file}"
      fi
    fi
  else
    logInfo "PAM hook already present in common-session file at ${pam_file}, skipping"
  fi

  # Reload daemone and enable the service for all users
  if ! systemctl --user daemon-reload; then
    logError "Failed to reload systemd user daemone after installing AD logon hook"
    return 1
  elif ! sudo systemctl --global enable "$(basename "${path_unit}")"; then
    logError "Failed to enable systemd path unit for AD logon hook"
    return 1
  else
    logInfo "Successfully enabled systemd path unit for AD logon hook and reloaded daemone"
  fi

  return 0
}

LOGON_SRV_NAME="ad_logon"
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
