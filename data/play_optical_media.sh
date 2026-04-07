# !/bin/env bash
# SPDX-License-Identifier: MIT
#
# Script to handle the insertion of Optical Media (CD/DVD/Blu-ray)
# Installed by setup's xdg.sh

po_main() {
  local mnt_point dev_path dev_info
  mnt_point="${1}"
  logInfo "Optical media insertion script started"

  # Log all arguments received and environment variables for debugging purposes
  local msg_args=""
  if [[ $# -gt 0 ]]; then
    msg_args=$(cat <<EOF
Received arguments:
$(for i in $(seq 1 $#); do echo "  - $i: ${!i}"; done)
EOF
)
  else
    msg_args="No arguments received"
  fi
  logDebug <<EOF
${msg_args}

Environment variables:
$(env)
EOF

  # Locate the device we will pass to VLC
  if [[ -n "${mnt_point}" ]]; then
    logInfo "Received open target argument: ${mnt_point}"
    if ! dev_path=$(findmnt -no SOURCE --target "${mnt_point}" 2>/dev/null); then
      logError "Failed to resolve mount point ${mnt_point} to a device"
      return 1
    elif [[ -z "${dev_path}" ]]; then
      logError "Failed to resolve mount point ${mnt_point}: no output from findmnt command"
      return 1
    else
      logInfo "Resolved mount point ${mnt_point} to device: ${dev_path}"
    fi
  else
    logInfo "No open target argument received. Locate a drive device to open"
    if ! dev_path=$(lsblk -o NAME,TYPE,MOUNTPOINT | grep "rom" | awk '$3 != "" {print "/dev/" $1; exit}'); then
      logError "Failed to locate optical drive device"
      return 1
    elif [[ -z "${dev_path}" ]]; then
      logError "Failed to locate optical drive device: no output from lsblk command"
      return 1
    else
      logInfo "Located optical drive device: ${dev_path}"
    fi

    # Find mount point for that device
    if ! mnt_point=$(findmnt -no TARGET "${dev_path}" 2>/dev/null); then
      logError "Failed to find mount point for device ${dev_path}"
      return 1
    elif [[ -z "${mnt_point}" ]]; then
      logError "Failed to find mount point for device ${dev_path}: no output from findmnt command"
      return 1
    else
      logInfo "Found mount point ${mnt_point} for device ${dev_path}"
    fi
  fi

  # Read info about the device
  if ! dev_info=$(udevadm info --query=property --name="${dev_path}" 2>/dev/null); then
    logError "Failed to query device information for ${dev_path}"
    return 1
  elif [[ -z "${dev_info}" ]]; then
    logError "Failed to query device information: no output from udevadm command"
    return 1
  else
    logInfo "Queried device information for ${dev_path}:\n${dev_info}"
  fi

  # Main Logic handling the disc
  if echo "${dev_info}" | grep -q "ID_CDROM_MEDIA=1"; then
    logInfo "Media detected in drive ${dev_path}"
    if echo "${dev_info}" | grep -q "ID_CDROM_MEDIA_BD=1"; then
      logInfo "Media in drive ${dev_path} is a Blu-ray disc"
      # Check if it's a video Blu-ray by looking for the presence of the BDMV folder
      if [[ -d "${mnt_point}/BDMV" ]]; then
        logInfo "Blu-ray in drive ${dev_path} contains BDMV folder. Assuming it's a video Blu-ray."
        exec vlc "bluray://${dev_path}"
      else
        logInfo "Blu-ray in drive ${dev_path} does not contain BDMV folder. Assuming it's a data Blu-ray."
      fi
    elif echo "${dev_info}" | grep -q "ID_CDROM_MEDIA_DVD=1"; then
      logInfo "Media in drive ${dev_path} is a DVD disc"
      # Check for the presence of VIDEO_TS to confirm it's a video DVD
      if [[ -d "${mnt_point}/VIDEO_TS" ]]; then
        logInfo "DVD in drive ${dev_path} contains VIDEO_TS folder. Assuming it's a video DVD."
        exec vlc "dvd://${dev_path}"
      else
        logInfo "DVD in drive ${dev_path} does not contain VIDEO_TS folder. Assuming it's a data DVD."
      fi
    elif echo "${dev_info}" | grep -q "ID_CDROM_MEDIA_CD=1"; then
      logInfo "Media in drive ${dev_path} is a CD disc"
      # Extract number of tracks to determine if it's an audio CD
      if echo "${dev_info}" | grep -q "ID_CDROM_MEDIA_TRACK_COUNT_AUDIO="; then
        local track_count
        track_count=$(echo "${dev_info}" | grep "ID_CDROM_MEDIA_TRACK_COUNT_AUDIO=" | cut -d'=' -f2)
        if [[ "${track_count}" -gt 2 ]]; then
          logInfo "CD in drive ${dev_path} has ${track_count} audio tracks. Assuming it's an audio CD."
          exec vlc "cdda://${dev_path}"
        else
          logInfo "CD in drive ${dev_path} has less than 3 (${track_count}) audio tracks. Assuming it's a data CD."
        fi
      else
        logInfo "CD in drive ${dev_path} does not have audio tracks. Assuming it's a data CD."
      fi
    else
      logWarn "Media in drive ${dev_path} is an unknown type of optical disc\nDevice information:\n${dev_info}"
    fi
  else
    logError "No media found in drive ${dev_path}"
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


###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
PO_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${PO_SOURCE}" ]]; do # resolve $PO_SOURCE until the file is no longer a symlink
  PO_ROOT=$(cd -P "$(dirname "${PO_SOURCE}")" >/dev/null 2>&1 && pwd)
  PO_SOURCE=$(readlink "${PO_SOURCE}")
  [[ ${PO_SOURCE} != /* ]] && PO_SOURCE=${PO_ROOT}/${PO_SOURCE} # if $PO_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
PO_ROOT=$(cd -P "$(dirname "${PO_SOURCE}")" >/dev/null 2>&1 && pwd)

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
  po_main "${@}"
  exit $?
fi
