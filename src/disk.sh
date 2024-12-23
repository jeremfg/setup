#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This script handles configuration of hard disks

if [[ -z ${GUARD_DISK_SH} ]]; then
  GUARD_DISK_SH=1
else
  return 0
fi

# Retrieves the boot drive and partition
#
# Parameters:
#   $1[out]: The boot drive
#   $2[out]: The boot partition
# Returns:
#   0: If the boot drive and partition were successfully retrieved
#   1: If the boot drive and partition could not be retrieved
disk_boot_partition() {
  local __result_boot_drive="${1}"
  local __result_boot_partition="${2}"
  local res

  if [[ -z ${__result_boot_drive} ]] || [[ -z ${__result_boot_partition} ]]; then
    logError "Variables not set"
    return 1
  fi

  local _boot_drive
  local _boot_drive_type
  local _boot_partition
  if ! _boot_partition=$(findmnt -n -o SOURCE /); then
    logError "Failed to find boot partition"
    return 1
  else
    logTrace "Boot partition: ${_boot_partition}"
  fi

  if ! _boot_drive=$(lsblk -dno PKNAME "${_boot_partition}"); then
      logError "Failed to find boot drive"
      return 1
  else
    logTrace "Boot drive: ${_boot_drive}"
  fi

  # Check type
  if ! boot_drive_type=$(lsblk -dno TYPE "/dev/${_boot_drive}"); then
    logError "Failed to find boot drive type"
    return 1
  else
    logTrace "Boot drive type: ${boot_drive_type}"
  fi
  case ${boot_drive_type} in
  disk)
    _boot_drive=("${_boot_drive}")
    ;;
  raid1)
    _boot_partition="${_boot_drive}"
    # We will need to retrieve which drives are part of this array
    if ! res=$(mdadm --detail "/dev/${_boot_drive}" | grep 'Active Devices' | awk '{print $4}'); then
      logError "Failed to find boot drive"
      return 1
    else
      logTrace "Nb Raid members: ${res}"
    fi
    if [[ ${res} -ne 2 ]]; then
      logError "Only raid1 arrays of two drives are supported"
      return 1
    fi
    if ! res=$(mdadm --detail "/dev/${_boot_drive}" | grep -Eo '/dev/[a-zA-Z0-9]+' | grep -v "/dev/${_boot_drive}" | sort | uniq); then
      logError "Failed to find boot drive"
      return 1
    else
      # Turn members into an array
      IFS=$'\n' read -r -d '' -a _boot_drive <<< "$(echo -e "${res}")"
      logTrace "Raid members: ${_boot_drive[*]}"
    fi
    ;;
  *)
    logError "Boot drive type not recognized"
    return 1
    ;;
  esac

  # Use indirect variable references to return the array and partition
  eval "$__result_boot_drive=(\"\${_boot_drive[@]}\")"
  eval "$__result_boot_partition='${_boot_partition}'"
  return 0
}

# Enumerates all drives
#
# Parameters:
#   $1[out]: An array of all the drives
# Returns:
#   0: If the drives were successfully enumerated
#   1: If the drives could not be enumerated
disk_get_drives() {
  local __result_drives="${1}"
  local res

  if [[ -z ${__result_drives} ]]; then
    logError "Variables not set"
    return 1
  fi

  if ! res=$(lsblk -dno NAME); then
    logError "Failed to list drives"
    return 1
  fi

  # Turn members into an array
  IFS=$'\n' read -r -d '' -a _drives <<< "$(echo -e "${res}")"

  # Use indirect variable references to return the array
  eval "$__result_drives=(\"\${_drives[@]}\")"
  return 0
}

# Retrieves the size of a drive
#
# Parameters:
#   $1[out]: The number of sectors
#   $2[out]: The sector size
#   $3[in]: The drive name
# Returns:
#   0: If the size was successfully retrieved
#   1: If the size could not be retrieved
disk_drive_size() {
  local __result_sec_cnt="${1}"
  local __result_sec_size="${2}"
  local drive="${3}"

  local __res1
  local __res2

  if [[ -z ${__result_sec_cnt} ]] || [[ -z ${__result_sec_size} ]] || [[ -z ${drive} ]]; then
    logError "Variables not set"
    return 1
  fi

  if ! __res1=$(blockdev --getsz "/dev/${drive}"); then
    logError "Failed to find drive size in sectors"
    return 1
  else
    logTrace "Drive size in sectors: ${__res1}"
  fi

  if ! __res2=$(blockdev --getss "/dev/${drive}"); then
    logError "Failed to find sector size"
    return 1
  else
    logTrace "Sector size: ${__res2}"
  fi

  eval "$__result_sec_cnt='${__res1}'"
  eval "$__result_sec_size='${__res2}'"
  return 0
}

# Retrieves the available space on a drive
#
# Parameters:
#   $1[out]: The start sector
#   $2[out]: The end sector
#   $3[in]: The boot partition to avoid
#   $4[in]: The drive name
# Returns:
#   0: If the available space was successfully retrieved
#   1: If the available space could not be retrieved
disk_get_available() {
  local __result_start_sector="${1}"
  local __result_end_sector="${2}"
  local boot_partition="${3}"
  local drive="${4}"

  local __res1
  local __res2

  if [[ -z ${__result_start_sector} ]] || [[ -z ${__result_end_sector} ]] || [[ -z ${boot_partition} ]] || [[ -z ${drive} ]]; then
    logError "Variables not set"
    return 1
  fi

  # Get block size
  local __psize
  local __lsize
  local __bsize
  if ! __psize=$(blockdev --getpbsz "/dev/${drive}"); then
    logError "Failed to get physical block size"
    return 1
  else
    logTrace "Physical block size [${drive}]: ${__psize}"
  fi
  if ! __bsize=$(blockdev --getbsz "/dev/${drive}"); then
    logError "Failed to get block size"
    return 1
  else
    logTrace "Block size [${drive}]: ${__bsize}"
  fi
  if ! __lsize=$(blockdev --getss "/dev/${drive}"); then
    logError "Failed to get logical block size"
    return 1
  else
    logTrace "Logical block size [${drive}]: ${__lsize}"
  fi

  # Get Last sector
  if ! __res2=$(blockdev --getsz "/dev/${drive}"); then
    logError "Failed to get last sector"
    return 1
  else
    # Align to the default GPT 512 block size
    logTrace "Last sector [${drive}]: ${__res2}"
    __res2=$(( (__res2 / __lsize) * __lsize ))
    logTrace "Last sector [${drive}] (aligned): ${__res2}"
  fi

  # Check if drive contains boot_partition
  if lsblk -no NAME "/dev/${drive}" | grep -q "${boot_partition}"; then
    logTrace "Drive ${drive} contains boot partition"
    # Read last usable sector
    if ! __res1=$(sgdisk -p /dev/${drive} | grep "last usable sector is" | awk '{print $10}'); then
      logError "Failed to find last usable sector"
      return 1
    else
      local palign
      palign=$(( (__res1 + __lsize) / __lsize * __lsize ))
      if [[ ${palign} -eq $(( __res1 + 34 )) ]]; then
        logTrace "Drive ${drive} is already aligned"
      else
        logWarn "Drive ${drive} is not aligned (${__res1} + 34 != ${palign})"
        __res1=$(( __res1 - 34 ))
      fi

      # Align to next 2048 boundary
      logTrace "Start sector [${drive}]: ${__res1}"
      __res1=${palign}
      logTrace "Start sector [${drive}] (aligned): ${__res1}"
    fi
  else
    __res1=0
    logTrace "Start sector [${drive}]: ${__res1}"
  fi

  eval "$__result_start_sector='${__res1}'"
  eval "$__result_end_sector='${__res2}'"
  return 0
}

###########################
###### Startup logic ######
###########################

DK_ARGS=("$@")
DK_CWD=$(pwd)
DK_ME="$(basename "${BASH_SOURCE[0]}")"

# Get directory of this script
# https://stackoverflow.com/a/246128
DK_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${DK_SOURCE}" ]]; do # resolve $DK_SOURCE until the file is no longer a symlink
  DK_ROOT=$(cd -P "$(dirname "${DK_SOURCE}")" >/dev/null 2>&1 && pwd)
  DK_SOURCE=$(readlink "${DK_SOURCE}")
  [[ ${DK_SOURCE} != /* ]] && DK_SOURCE=${DK_ROOT}/${DK_SOURCE} # if $DK_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DK_ROOT=$(cd -P "$(dirname "${DK_SOURCE}")" >/dev/null 2>&1 && pwd)
DK_ROOT=$(realpath "${DK_ROOT}/..")

# Import dependencies
if ! source "${PREFIX:-/usr/local}/lib/slf4.sh"; then
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
  logFatal "This script cannot be exceuted"
fi