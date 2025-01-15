# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# This script handles configuration of hard disks

if [[ -z ${GUARD_DISK_SH} ]]; then
  GUARD_DISK_SH=1
else
  return 0
fi

# Retrieves the root drive and partition
#
# Parameters:
#   $1[out]: The boot drive(s)
#   $2[out]: The boot partition
# Returns:
#   0: If the boot drive(s) and partition were successfully retrieved
#   1: If the boot drive(s) and partition could not be retrieved
disk_root_partition() {
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
    # shellcheck disable=SC2128
    _boot_partition="${_boot_drive}"
    # We will need to retrieve which drives are part of this array
    if ! res=$(mdadm --detail "/dev/${_boot_partition}" | grep 'Working Devices' | awk '{print $4}' || true); then
      logError "Failed to find boot drive"
      return 1
    else
      logTrace "Nb Raid members: ${res}"
    fi
    if [[ ${res} -ne 2 ]]; then
      logError "Only raid1 arrays of two drives are supported"
      return 1
    fi
    # shellcheck disable=SC2128
    if ! res=$(mdadm --detail "/dev/${_boot_partition}" | grep -Eo '/dev/[a-zA-Z0-9]+' | grep -v "/dev/${_boot_drive}" | sort | uniq || true); then
      logError "Failed to find boot drive"
      return 1
    else
      # Turn members into an array
      IFS=$'\n' read -r -d '' -a _boot_drive <<<"$(echo -e "${res}")"
      logTrace "Raid members: ${_boot_drive[*]}"
    fi
    ;;
  *)
    logError "Boot drive type not recognized"
    return 1
    ;;
  esac

  # Use indirect variable references to return the array and partition
  eval "${__result_boot_drive}=(\"\${_boot_drive[@]}\")"
  eval "${__result_boot_partition}='${_boot_partition}'"
  return 0
}

# Enumerates all loop devices
#
# Parameters:
#   $1[out]: An array of all the loop devices
# Returns:
#   0: If the loop devices were successfully enumerated
#   1: If the loop devices could not be enumerated
disk_list_loop() {
  local __result_loops="${1}"
  local res

  if [[ -z ${__result_loops} ]]; then
    logError "Variables not set"
    return 1
  fi

  if ! res=$(losetup -O NAME); then
    logError "Failed to list loop devices"
    return 1
  elif ! res=$(echo "${res}" | tail -n +2 | sed 's|/dev/||' || true); then
    logError "Failed to format loop devices"
    return 1
  fi

  # Turn members into an array
  IFS=$'\n' read -r -d '' -a _loops <<<"$(echo -e "${res}")"

  # Use indirect variable references to return the array
  eval "${__result_loops}=(\"\${_loops[@]}\")"
  return 0
}

# Retrieves the details of a loop device
#
# Parameters:
#   $1[out]: The device
#   $2[out]: The offset
#   $3[out]: The size
#   $4[in]: The loop device
# Returns:
#   0: If the loop device details were successfully retrieved
#   1: If the loop device details could not be retrieved
# Retrieves the details of a loop device
#
# Parameters:
#   $1[out]: The device
#   $2[out]: The offset
#   $3[out]: The size
#   $4[in]: The loop device
# Returns:
#   0: If the loop device details were successfully retrieved
#   1: If the loop device details could not be retrieved
disk_loop_details() {
  local __result_device="${1}"
  local __result_offset="${2}"
  local __result_size="${3}"
  local loop="${4}"

  if [[ -z ${__result_device} ]] || [[ -z ${__result_offset} ]] || [[ -z ${__result_size} ]] || [[ -z ${loop} ]]; then
    logError "Variables not set"
    return 1
  fi

  local __res1
  if ! __res1=$(losetup --list --output NAME,BACK-FILE,OFFSET,SIZELIMIT | grep "${loop} " || true); then
    logError "Failed to find loop device details: ${__res1}"
    return 1
  fi

  # Extract the details
  # shellcheck disable=SC2206 # We want to split the string into an array
  __res1=(${__res1})
  __res1[0]=${__res1[0]#/dev/}
  __res1[1]=${__res1[1]#/dev/}
  __res1[2]=$((__res1[2] / 512))
  __res1[3]=$((__res1[3] / 512))
  logTrace "Loop device ${__res1[0]}: Back File: ${__res1[1]}, Offset: ${__res1[2]}, Size: ${__res1[2]}"

  eval "${__result_device}='${__res1[1]}'"
  eval "${__result_offset}='${__res1[2]}'"
  eval "${__result_size}='${__res1[3]}'"

  return 0
}

# Enumerates all drives
#
# Parameters:
#   $1[out]: An array of all the drives
# Returns:
#   0: If the drives were successfully enumerated
#   1: If the drives could not be enumerated
disk_list_drives() {
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
  IFS=$'\n' read -r -d '' -a _drives <<<"$(echo -e "${res}")"

  # Use indirect variable references to return the array
  eval "${__result_drives}=(\"\${_drives[@]}\")"
  return 0
}

# Retrieves the size of a drive
#
# Parameters:
#   $1[out]: The number of sectors
#   $2[out]: The sector size
#   $3[in]: The physical sector size
#   $3[in]: The drive name
# Returns:
#   0: If the size was successfully retrieved
#   1: If the size could not be retrieved
disk_drive_size() {
  local __result_sec_cnt="${1}"
  local __result_sec_size="${2}"
  local __result_phys_size="${3}"
  local drive="${4}"

  local __res1
  local __res2
  local __res3

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

  eval "${__result_sec_cnt}='${__res1}'"
  eval "${__result_sec_size}='${__res2}'"

  if [[ -n ${__result_phys_size} ]]; then
    if ! __res3=$(blockdev --getpbsz "/dev/${drive}"); then
      logError "Failed to find physical sector size"
      return 1
    else
      logTrace "Physical sector size: ${__res3}"
      eval "${__result_phys_size}='${__res3}'"
    fi
  else
    __res3=0
    logWarn "Physical sector size not set"
  fi

  return 0
}

# Retrieves the available space on a drive
#
# Parameters:
#   $1[out]: The first unpartitioned sector
#   $2[out]: Total number of sectors
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

  # Print extra details about the disk
  if [[ ${LOG_LEVEL} -le ${LOG_LEVEL_TRACE} ]]; then
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
  fi

  # Get Total number of sectors
  if ! __res2=$(blockdev --getsz "/dev/${drive}"); then
    logError "Failed to get last sector"
    return 1
  fi

  # Check if drive contains boot_partition
  # shellcheck disable=SC2312
  if lsblk -no NAME "/dev/${drive}" | grep -q "${boot_partition}"; then
    logTrace "Drive ${drive} contains boot partition"
    # Read last usable sector
    if ! __res1=$(sgdisk -p "/dev/${drive}"); then
      logError "Failed to find last usable sector"
      return 1
    else
      __res1=$(echo "${__res1}" | grep "last usable sector is" | awk '{print $10}')
      __res1=$((__res1 + 34))

      # Sanity check, we should be on a 512-byte boundary
      if [[ $((__res1 % 512)) -ne 0 ]]; then
        logWarn "Drive ${drive} is not aligned (${__res1} % 512 != 0)"
      fi
    fi
  else
    __res1=0
    logTrace "Start sector [${drive}]: ${__res1}"
  fi

  eval "${__result_start_sector}='${__res1}'"
  eval "${__result_end_sector}='${__res2}'"
  return 0
}

# Creates a new partition on space left unused on a drive
#
# Parameters:
#   $1[out]: The creted loop device
#   $2[in]: The drive on which to create the partition
#   $3[in]: The start sector
#   $4[in]: The number of sectors
# Returns:
#   0: If the partition was successfully created
#   1: If the partition could not be created
disk_create_loop() {
  local __result_loop="${1}"
  local drive="${2}"
  local start_sector="${3}"
  local nb_sectors="${4}"

  local __res1

  if [[ -z ${__result_loop} ]] || [[ -z ${drive} ]] || [[ -z ${start_sector} ]] || [[ -z ${nb_sectors} ]]; then
    logError "Variables not set: loop=${__result_loop}, drive=${drive}, start_sector=${start_sector}, nb_sectors=${nb_sectors}"
    return 1
  fi

  if ! __res1=$(losetup --find --show --offset $((start_sector * 512)) --sizelimit $((nb_sectors * 512)) "/dev/${drive}"); then
    logError "Failed to create loop device"
    return 1
  else
    # Strip /dev/ from the loop device
    __res1=${__res1#/dev/}
  fi

  eval "${__result_loop}='${__res1}'"
  return 0
}

# Mirror two drives
#
# Parameters:
#   $1[in]: The drive name
#   $2[in]: The first drive
#   $3[in]: The second drive
# Returns:
#   0: If the drives were successfully mirrored
#   1: If the drives could not be mirrored
disk_create_raid1() {
  local drive="${1}"
  local drive1="${2}"
  local drive2="${3}"

  if [[ -z ${drive} ]] || [[ -z ${drive1} ]] || [[ -z ${drive2} ]]; then
    logError "Variables not set: drive=${drive}, drive1=${drive1}, drive2=${drive2}"
    return 1
  fi

  # shellcheck disable=SC2312
  if ! yes | mdadm --create "/dev/${drive}" --force --level=1 --raid-devices=2 "/dev/${drive1}" "/dev/${drive2}"; then
    logError "Failed to create raid1"
    return 1
  fi

  return 0
}

disk_assemble_radi1() {
  local drive="${1}"
  local drive1="${2}"
  local drive2="${3}"
  local __res1 __res2

  if [[ -z ${drive} ]] || [[ -z ${drive1} ]] || [[ -z ${drive2} ]]; then
    logError "Variables not set: drive=${drive}, drive1=${drive1}, drive2=${drive2}"
    return 1
  fi

  # First, check if the raid array is already assembled
  if __res1=$(mdadm --detail "/dev/${drive}"); then
    logInfo "/dev/${drive} already exists"

    # Confirm array state
    __res2=$(echo "${__res1}" | grep 'State :' | awk '{print $3}' || true)
    case ${__res2} in
    clean)
      logInfo "Array is clean"
      ;;
    inactive)
      logInfo "Array is inactive"
      __res2=$(echo "${__res1}" | grep 'Total Devices :' | awk '{print $4}' || true)
      if [[ ${__res2} -eq 1 ]]; then
        logInfo "Array has only 1 member device. Known situation. Stopping the array..."
        # This occurs when the OS automounts on startup.
        # while only one drive is available. A typical scneario in our use case, because the
        # loop device for DRIVE2 is not created until later. We just need to stop this array
        # and reassemble it ourselves.
        if ! mdadm --stop "/dev/${drive}"; then
          logError "Failed to stop raid1"
          return 1
        elif ! mdadm --assemble "/dev/${drive}" "/dev/${drive1}" "/dev/${drive2}"; then
          logError "Failed to assemble raid1"
          return 1
        else
          logInfo "Array was stopped and reassembled"
          return 0
        fi
      else
        logError "Array has ${__res2} members. This is unexpected"
        return 1
      fi
      ;;
    *)
      logWarn "Array is in an unkown state: ${__res2}"
      return 1
      ;;
    esac

    # Confirm RAID level
    __res2=$(echo "${__res1}" | grep 'Raid Level :' | awk '{print $4}' || true)
    if [[ "${__res2}" != "raid1" ]]; then
      logWarn "Array is not raid1, but \"${__res2}\""
      return 1
    else
      logTrace "Array is raid1 as expected"
    fi

    # Confirm RAID devices
    __res2=$(echo "${__res1}" | grep 'Working Devices :' | awk '{print $4}' || true)
    if [[ ${__res2} -ne 2 ]]; then
      logWarn "Array does not have 2 working devices"
      return 1
    else
      logTrace "Array has 2 members as expected"
    fi

    # Confirm RAID members
    local member member1 member2
    __res2=$(echo "${__res1}" | grep -Eo '/dev/[a-zA-Z0-9]+' | grep -v "/dev/${drive}" | sort | uniq || true)
    IFS=$'\n' read -r -d '' -a __res2 <<<"$(echo -e "${__res2}")"
    for member in "${__res2[@]}"; do
      if [[ "${member}" == "/dev/${drive1}" ]]; then
        member1="${member}"
        logTrace "Found member1: ${member1}"
      elif [[ "${member}" == "/dev/${drive2}" ]]; then
        member2="${member}"
        logTrace "Found member2: ${member2}"
      else
        logWarn "Unknown member: ${member}"
        return 1
      fi
    done
    if [[ -z ${member1} ]] || [[ -z ${member2} ]]; then
      logWarn "Missing members for RAID array ${drive}"
      return 1
    else
      logInfo "RAID array ${drive} is already assembled"
      return 0
    fi
  else
    if ! mdadm --assemble "/dev/${drive}" "/dev/${drive1}" "/dev/${drive2}"; then
      logError "Failed to assemble raid1"
      return 1
    else
      logInfo "/dev/${drive} did not exist and was assembled"
      return 0
    fi
  fi
}

# Formats a partition
#
# Parameters:
#   $1[in]: The partition to format
#   $2[in]: The filesystem to use
# Returns:
#   0: If the partition was successfully formatted
#   1: If the partition could not be formatted
disk_format() {
  local partition="${1}"
  local fs="${2}"

  if [[ -z ${partition} ]] || [[ -z ${fs} ]]; then
    logError "Variables not set: partition=${partition}, fs=${fs}"
    return 1
  fi

  if ! mkfs."${fs}" "/dev/${partition}"; then
    logError "Failed to format partition"
    return 1
  fi

  return 0
}

# Remove a loop device
#
# Parameters:
#   $1[in]: The loop device to remove
# Returns:
#   0: If the loop device was successfully removed
#   1: If the loop device could not be removed
disk_remove_loop() {
  local loop="${1}"
  local __res1

  if [[ -z ${loop} ]]; then
    logError "Variables not set: loop=${loop}"
    return 1
  fi

  # Check if loop device exists
  if __res=$(losetup --list --output NAME); then
    if ! echo "${__res}" | grep -q "${loop}"; then
      logInfo "Loop device ${loop} does not exist"
      return 0
    fi
  else
    logError "Failed to list loop devices: ${__res}"
  fi

  if ! losetup --detach "${loop}"; then
    logError "Failed to remove loop device"
    return 1
  else
    logInfo "Loop device ${loop} was removed succssfully"
  fi

  return 0
}

# Remove a raid array
#
# Parameters:
#   $1[in]: The raid array to remove
# Returns:
#   0: If the raid array was successfully removed
#   1: If the raid array could not be removed
disk_remove_raid() {
  local raid="${1}"

  if [[ -z ${raid} ]]; then
    logError "Variables not set: raid=${raid}"
    return 1
  fi

  if mdadm --detail "/dev/${raid}" &>/dev/null; then
    if ! mdadm --stop "/dev/${raid}"; then
      logError "Failed to remove raid array"
      return 1
    else
      logInfo "Raid array /dev/${raid} was removed"
    fi
  else
    logInfo "Raid array /dev/${raid} does not exist"
  fi

  return 0
}

# Variables loaded externally
if [[ -z "${LOG_LEVEL}" ]]; then LOG_LEVEL=""; fi
if [[ -z "${LOG_LEVEL_TRACE}" ]]; then LOG_LEVEL_TRACE=""; fi

###########################
###### Startup logic ######
###########################

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
