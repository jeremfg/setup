#!/bin/env sh
# SPDX-License-Identifier: MIT
#
# Used to refresh the SYSVOL cache on login

sysvol_refresh() {
  __refresh_res=1

  if ! command -v klist > /dev/null 2>&1; then
    logError "klist command not found, please install krb5-user package"
    return 1
  fi

  # Wait for klist to complete
  for i in $(seq 1 10); do
    if klist -s; then
      logDebug "Kerberos ticket found, proceeding with SYSVOL refresh"
      break
    else
      logDebug "No Kerberos ticket found, waiting for klist to complete (attempt ${i}/5)"
      sleep 1
    fi
  done

  if ! klist -s; then
    logError "No Kerberos ticket found, please run kinit before running this script"
    return 1
  else
    logDebug "Kerberos ticket found, proceeding with SYSVOL refresh"
  fi

  if ! command -v ipcalc > /dev/null 2>&1; then
    logError "ipcalc command not found, please install ipcalc package"
    return 1
  fi

  if ! sysvol_mount; then
    logError "Failed to mount SYSVOL, cannot refresh cache"
    return 1
  elif ! sysvol_update_cache; then
    logError "Failed to update SYSVOL cache"
    __refresh_res=1
  else
    __refresh_res=0
  fi

  if ! sysvol_unmount; then
    logError "Failed to unmount SYSVOL, cannot refresh cache"
    return 1
  else
    logInfo "Successfully unmounted SYSVOL, cache refresh complete"
  fi

  return ${__refresh_res}
}

sysvol_update_cache() {
  # Get expect domain subdir
  if ! domain=$(realm list | awk '/domain-name/ {print $2}'); then
    logError "Failed to retrieve domain from realm list"
    return 1
  elif [ -z "${domain}" ]; then
    logError "Failed to retrieve domain from realm list: no output from realm command"
    return 1
  fi

  # Syncrhonize the cache
  if ! mkdir -p "${SYSVOL_CACHE_DIR}/${domain}"; then
    logError "Failed to create SYSVOL cache directory ${SYSVOL_CACHE_DIR}/${domain}"
    return 1
  elif [ ! -d "${SYSVOL_MOUNT_POINT}/${domain}" ]; then
    logError "SYSVOL does not contain expected directory ${domain}, cannot refresh cache"
    return 1
  elif ! rsync -a --delete --no-perms --no-times --no-owner --no-group \
    "${SYSVOL_MOUNT_POINT}/${domain}/" "${SYSVOL_CACHE_DIR}/${domain}/"; then
    logError "Failed to copy SYSVOL contents from ${SYSVOL_MOUNT_POINT}/${domain} to ${SYSVOL_CACHE_DIR}/${domain}"
    return 1
  else
    logInfo "Successfully copied SYSVOL contents from ${SYSVOL_MOUNT_POINT}/${domain} to ${SYSVOL_CACHE_DIR}/${domain}"
  fi

  return 0
}

sysvol_mount() {
  if ! sysvol_find_dc my_dc; then
    logError "Failed to find domain controller for SYSVOL mount"
    return 1
  else
    logInfo "Found domain controller ${my_dc} for SYSVOL mount"
  fi

  user=""
  if [ -n "${USER}" ]; then
    user="${USER}"
  elif [ -n "${PAM_USER}" ]; then
    user="${PAM_USER}"
  else
    logError "Failed to determine user for SYSVOL mount, USER and PAM_USER are both empty"
    return 1
  fi

  user_id="$(id -u "${user}")"
  if [ -z "${user_id}" ]; then
    logError "Failed to determine user ID for ${user}"
    return 1
  else
    logInfo "Determined user ID ${user_id} for ${user}"
  fi

  __res=1
  # Mount sysvol
  if ! sysvol_unmount; then
    logError "Failed to unmount existing SYSVOL mount, cannot proceed with refresh"
    return 1
  elif ! mkdir -p "${SYSVOL_MOUNT_POINT}"; then
    logError "Failed to create SYSVOL mount point ${SYSVOL_MOUNT_POINT}"
    return 1
  elif ! cd "${SYSVOL_MOUNT_POINT}" > /dev/null; then
    logError "Failed to change directory to ${SYSVOL_MOUNT_POINT}"
    return 1
  # --use-krb5-ccache=FILE:/tmp/krb5cc_${user_id}
  elif ! smbclient "//${my_dc}/SYSVOL" -D . -c "prompt OFF; recurse ON; mget *" \
    --use-kerberos=required -m SMB3 -d 0; then
    logError "Failed to copy SYSVOL contents from //${my_dc}/SYSVOL to ${SYSVOL_MOUNT_POINT}"
    __res=1
  else
    logInfo "Successfully copied SYSVOL contents from //${my_dc}/SYSVOL to ${SYSVOL_MOUNT_POINT}"
  fi

  if ! cd - > /dev/null; then
    logError "Failed to change directory back from ${SYSVOL_MOUNT_POINT}"
  else
    __res=0
  fi

  logInfo "Successfully mounted SYSVOL at ${SYSVOL_MOUNT_POINT}"
  return ${__res}
}

sysvol_unmount() {
  # Clean up the mount point directory
  if [ -d "${SYSVOL_MOUNT_POINT}" ]; then
    if ! rm -rf "${SYSVOL_MOUNT_POINT}"; then
      logError "Failed to remove mount point directory ${SYSVOL_MOUNT_POINT}"
      return 1
    else
      logInfo "Successfully removed mount point directory ${SYSVOL_MOUNT_POINT}"
    fi
  elif [ -e "${SYSVOL_MOUNT_POINT}" ]; then
    logError "Mount point ${SYSVOL_MOUNT_POINT} exists but is not a directory, please remove it before running this script"
    return 1
  else
    logInfo "Mount point directory ${SYSVOL_MOUNT_POINT} does not exist, skipping cleanup"
  fi

  return 0
}

# Select which DC to mount based on network proximity
# Parameters:
#   $1[out]: The selected DC (FQDN)
sysvol_find_dc() {
  __res_dc="${1}"

  # Get the current domain
  if ! domain=$(realm list | awk '/domain-name/ {print $2}'); then
    logError "Failed to retrieve domain from realm list"
    return 1
  elif [ -z "${domain}" ]; then
    logError "Failed to retrieve domain from realm list: no output from realm command"
    return 1
  else
    logInfo "Current domain: ${domain}"
  fi

  candidate_dc=""
  # Retrieve all DCs for the domain
  # host -t SRV _ldap._tcp.ad.jeremfg.com | awk '{print $8}' | sed 's/\.$//'
  for dc in $(host -t SRV _ldap._tcp.${domain} | awk '{print $8}' | sed 's/\.$//'); do
    logDebug "Assessing DC: ${dc}"
    # Filter-out a non-reachable server
    if ! ping -c 1 -W 1 "${dc}" > /dev/null 2>&1; then
      logWarn "DC ${dc} is not reachable, skipping"
      continue
    # Prefer a DC on the same subnet
    elif is_my_subnet "${dc}"; then
      logInfo "Selected ${dc} for being on the same subnet"
      candidate_dc="${dc}"
      continue
    elif [ -z "${candidate_dc}" ]; then
      logInfo "Selected ${dc} for being reachable"
      candidate_dc="${dc}"
      continue
    else
      logInfo "Ignoring ${dc}, prefering ${candidate_dc}"
      continue
    fi
  done

  if [ -z "${candidate_dc}" ]; then
    logError "Failed to find any reachable DCs for domain ${domain}"
    return 1
  else
    eval "${__res_dc}='${candidate_dc}'"
    logInfo "Selected DC ${__res_dc} for SYSVOL mount"
    return 0
  fi
}

is_my_subnet() {
  # Retrieve the primary IP interface
  if ! my_if=$(ip route get 1 | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1)}}}'); then
    logError "Failed to determine my network interface"
    return 1
  elif [ -z "${my_if}" ]; then
    logError "Interface not found in ip route output"
    return 1
  elif ! my_cidr=$(ip -o -f inet addr show dev "${my_if}" | awk '{print $4}'); then
    logError "Failed to determine my CIDR for interface ${my_if}"
    return 1
  elif [ -z "${my_cidr}" ]; then
    logError "Failed to determine my CIDR for interface ${my_if}: no output from ip command"
    return 1
  elif ! my_net=$(ipcalc -n "${my_cidr}" | awk -F: '/Network/ {print $2}' | awk '{print $1}'); then
    logError "Failed to validate CIDR ${my_cidr} for interface ${my_if}"
    return 1
  elif [ -z "${my_net}" ]; then
    logError "Failed to validate CIDR ${my_cidr} for interface ${my_if}: no output from ipcalc command"
    return 1
  else
    my_ip=${my_cidr%/*}
    my_msk=${my_cidr#*/}
    my_net=${my_net%/*}
    logDebug "Determined my network interface:"
    logDebug "  Interface : ${my_if}"
    logDebug "  IP CIDR   : ${my_cidr}"
    logDebug "  IP Address: ${my_ip}"
    logDebug "  IP Mask   : ${my_msk}"
    logDebug "  IP Network: ${my_net}"
  fi

  # Retrieve the IP address for the target DC
  for dc_ip in $(dig +short A "${1}"); do
    logDebug "Checking DC IP ${dc_ip} against my network ${my_net}/${my_msk}"
    if ! dc_cidr=$(ipcalc -n "${dc_ip}/${my_msk}" | awk -F: '/Network/ {print $2}' | awk '{print $1}'); then
      logError "Failed to validate DC IP ${dc_ip} with mask ${my_msk}"
      continue
    elif [ -z "${dc_cidr}" ]; then
      logError "Failed to validate DC IP ${dc_ip} with mask ${my_msk}: no output from ipcalc command"
      continue
    fi
    dc_net=${dc_cidr%/*}
    if [ "${dc_net}" = "${my_net}" ]; then
      logInfo "DC IP ${dc_ip} is on the same subnet as me (${my_net}/${my_msk})"
      return 0
    else
      logDebug "DC IP ${dc_ip} is NOT on the same subnet as me (${my_net}/${my_msk})"
      continue
    fi
  done

  return 1
}

logError() {
  logger -t "${LOGGER_NAME}" "ERROR: ${*}"
}

logWarn() {
  logger -t "${LOGGER_NAME}" "WARN: ${*}"
}

logInfo() {
  logger -t "${LOGGER_NAME}" "INFO: ${*}"
}

logDebug() {
  logger -t "${LOGGER_NAME}" "DEBUG: ${*}"
}

# Global variables
LOGGER_NAME="sysvol_refresh"
SYSVOL_CACHE_DIR="/var/cache/sysvol"
SYSVOL_MOUNT_POINT="/tmp/sysvol"

logger -t "${LOGGER_NAME}" "Starting SYSVOL refresh for: ${USER}"
sysvol_refresh "${@}"
res="${?}"
logger -t "${LOGGER_NAME}" "Finished SYSVOL refresh with status: ${res}"
exit ${res}
