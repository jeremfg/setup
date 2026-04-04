# !/bin/env bash
# SPDX-License-Identifier: MIT
#
# Mounting drives for Active Directory configuration
# This script should have no dependencies beyond BPKG to run
# This script will mount every drive your security groups allows
# This script is typically installed automatically by ad.sh

ad_mount() {
  # Check we have a ticket
  if ! klist -s; then
    logError "No Kerberos ticket found, please run kinit before running this script"
    return 1
  else
    logDebug "Kerberos ticket found, proceeding with AD drive mounting"
  fi

  local my_dc
  # if ! select_dc my_dc; then
  #   logError "Failed to select domain controller"
  #   return 1
  # else
  #   logInfo "Selected domain controller ${my_dc}"
  # fi
  my_dc="dc1.ad.jeremfg.com"

  # Mount the SYSVOL
  if ! sysvol_mount "${my_dc}"; then
    logError "Failed to mount SYSVOL"
    return 1
  else
    logInfo "Successfully mounted SYSVOL"
  fi

  return 0
}

select_dc() {
  local __res_dc="${1}"

  # Retrieve DOMAIN from realm list
  local domain
  if ! domain=$(realm list | awk '/domain-name/ {print $2}'); then
    logError "Failed to retrieve domain from realm list"
    return 1
  elif [[ -z "${domain}" ]]; then
    logError "Failed to retrieve domain from realm list: no output from realm command"
    return 1
  else
    logInfo "Retrieved domain ${domain} from realm list"
  fi

  # Retrueve a list of domain controllers
  local -a dcs
  if ! readarray -t dcs < <(host -t SRV _ldap._tcp.${domain} | awk '{print $8}' | sed 's/\.$//'); then
    logError "Failed to query domain controllers for ${domain}"
    return 1
  elif [[ ${#dcs[@]} -eq 0 ]]; then
    logError "No domain controllers found for ${domain}"
    return 1
  else
    logInfo <<EOF
Found ${#dcs[@]} domain controllers for ${domain}:
$(printf '  - %s\n' "${dcs[@]}")
EOF
  fi

  if [[ ${#dcs[@]} -gt 1 ]]; then
    logInfo "Multiple domain controllers found, selecting the one with an IP matching our own"

    # Find my own subnet
    local my_if my_cidr my_ip my_msk my_net
    if ! my_if=$(ip route get 1 | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1)}}}'); then
      logError "Failed to determine my network interface"
      return 1
    elif [[ -z "${my_if}" ]]; then
      logError "Failed to determine my network interface: no output from ip command"
      return 1
    elif ! my_cidr=$(ip -o -f inet addr show dev "${my_if}" | awk '{print $4}'); then
      logError "Failed to determine my CIDR for interface ${my_if}"
      return 1
    elif [[ -z "${my_cidr}" ]]; then
      logError "Failed to determine my CIDR for interface ${my_if}: no output from ip command"
      return 1
    elif ! my_net=$(ipcalc -n "${my_cidr}" | awk -F: '/Network/ {print $2}' | awk '{print $1}'); then
      logError "Failed to validate CIDR ${my_cidr} for interface ${my_if}"
      return 1
    elif [[ -z "${my_net}" ]]; then
      logError "Failed to validate CIDR ${my_cidr} for interface ${my_if}: no output from ipcalc command"
      return 1
    else
      my_ip=${my_cidr%/*}
      my_msk=${my_cidr#*/}
      my_net=${my_net%/*}
      logDebug <<EOF
Determined my network interface:
  Interface : ${my_if}
  IP CIDR   : ${my_cidr}
  IP Address: ${my_ip}
  IP Mask   : ${my_msk}
  IP Network: ${my_net}
EOF
    fi

    local cur_dc selected
    selected=""
    for cur_dc in "${dcs[@]}"; do
      # Retrieve IP addresses for the current DC
      local -a dc_ips
      if ! readarray -t dc_ips < <(dig +short A ${cur_dc}); then
        logError "Failed to resolve IP for domain controller ${cur_dc}"
        continue
      elif [[ ${#dc_ips[@]} -lt 1 ]]; then
        logError "Failed to resolve IP for domain controller ${cur_dc}: no output from dig command"
        continue
      else
        logDebug "Resolved domain controller ${cur_dc} to IPs: ${dc_ips[*]}"
      fi

      # For each IP, calculate the network and see if it matches our own
      local dc_ip dc_cidr dc_net
      for dc_ip in "${dc_ips[@]}"; do
        if ! dc_cidr=$(ipcalc -n "${dc_ip}/${my_msk}" | awk -F: '/Network/ {print $2}' | awk '{print $1}'); then
          logError "Failed to calculate network for domain controller IP ${dc_ip}"
          continue
        elif [[ -z "${dc_cidr}" ]]; then
          logError "Failed to calculate network for domain controller IP ${dc_ip}: no output from ipcalc"
          continue
        else
          logDebug "Calculated network for domain controller IP ${dc_ip} is ${dc_cidr}"
        fi
        dc_net=${dc_cidr%/*}
        logDebug "Checking if network ${dc_net} is on the same subnet as us (${my_net})"
        if [[ "${dc_net}" == "${my_net}" ]]; then
          selected="${cur_dc}"
          logInfo "Selected domain controller ${cur_dc} with IP ${dc_ip} matching my subnet"
          break 2
        else
          logDebug "Domain controller ${cur_dc} with IP ${dc_ip} does not match my subnet, skipping"
        fi
      done
    done
    if [[ -z "${selected}" ]]; then
      logWarn "Failed to find a domain controller with an IP matching my subnet, selecting the first one (${dcs[0]})"
      selected="${dcs[0]}"
    fi
  else
    selected="${dcs[0]}"
    logInfo "Only one domain controller found, selecting: ${selected}"
  fi

  # Set the selected DC as the output variable
  eval "${__res_dc}='${selected}'"

  return 0
}

# Mount the SYSVOL share
# Parameters:
#   $1: Domain controller to mount SYSVOL from
sysvol_mount() {
  local dc="${1}"

  local sysvol
  sysvol="//${dc}/SYSVOL"
  logInfo "Mounting ${sysvol} to ${SYSVOL_DIR}"

  if ! sysvol_umount; then
    logError "Failed to cleanup any prior mounts"
    return 1
  elif [[ -e "${SYSVOL_DIR}" ]]; then
    logError "Drive directory ${SYSVOL_DIR} already exists. Please remove it before running this script."
    return 1
  else
    logDebug "Successfully prepared drive directory"
  fi

  # Mount SYSVOL
  if ! mkdir -p "${SYSVOL_DIR}"; then
    logError "Failed to create drive directory ${SYSVOL_DIR}"
    return 1
  elif ! sudo mount -t cifs "${sysvol}" "${SYSVOL_DIR}" -o "sec=krb5,cruid=$(id -u),multiuser"; then
    logError "Failed to mount SYSVOL"
    return 1
  else
    logDebug "Successfully created drive directory ${SYSVOL_DIR}"
  fi
}

sysvol_umount() {
  if mountpoint -q "${SYSVOL_DIR}"; then
    if ! sudo umount "${SYSVOL_DIR}"; then
      logError "Failed to unmount SYSVOL"
      return 1
    else
      logDebug "Successfully unmounted SYSVOL"
    fi
  else
    logDebug "SYSVOL is not mounted, skipping unmount"
  fi

  if ! rm -rf "${SYSVOL_DIR}"; then
    logError "Failed to remove drive directory ${SYSVOL_DIR}"
    return 1
  else
    logDebug "Successfully unmounted SYSVOL and removed drive directory ${SYSVOL_DIR}"
  fi
}

external_dependencies() {
  # Only use the global packages
  PREFIX="/usr/local"
  export PREFIX


  # Install BPKG
  if ! command -v bpkg &>/dev/null; then
    if ! command -v wget &>/dev/null; then
      echo "ERROR: wget is required to install bpkg but not found."
      return 1
    elif ! wget -qO- "${BPKG_DL_URL}" | bash; then
      echo "ERROR: Failed to install bpkg"
      return 1
    else
      echo "INFO: Successfully installed bpkg"
    fi
  fi

  # Install slf4.sh
  if [[ ! -f "${PREFIX}/lib/slf4.sh" ]]; then
    if ! bpkg install -g jeremfg/slf4.sh; then
      echo "Failed to install slf4.sh"
      return 1
    else
      echo "INFO: Successfully installed slf4.sh"
    fi
  fi

  # Configure SLF4.sh
  LOG_LEVEL=0
  LOG_CONSOLE=1

  # Load slf4.sh
  if ! source "${PREFIX}/lib/slf4.sh"; then
    echo "Failed to load slf4.sh"
    return 1
  else
    logInfo "Successfully loaded slf4.sh"
  fi

  return 0
}

MOUNT_BASE="/mnt"
SYSVOL_DIR="/tmp/sysvol"
# DRIVE_DIR="/tmp/gpo_drives"
# DOMAIN="ad.jeremfg.com"
# SYSVOL="//${DOMAIN}/SYSVOL"

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

if ! external_dependencies; then
  echo "Error: Failed to set up external dependencies"
  exit 1
fi

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  logFatal "This script cannot be piped"
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  logFatal "This script cannot be sourced"
else
  # This script was executed
  ad_mount "${@}"
fi
