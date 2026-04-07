#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Script to handle the insertion of Optical Media (CD/DVD/Blu-ray)
# Installed by setup's xdg.sh

po_main() {
  mnt_point="$1"
  dev_path=""
  dev_info=""
  log_info "Optical media insertion script started"

  # Log all arguments received and environment variables for debugging purposes
  if [ $# -gt 0 ]; then
    msg_args="\nReceived arguments:"
    i=1
    while [ $i -le $# ]; do
      eval arg=\${$i}
      msg_args="$msg_args\n  - $i: $arg"
      i=$((i+1))
    done
  else
      msg_args="No arguments received"
  fi
  log_message="$(printf '%b' "$msg_args")\n\nEnvironment variables:\n$(env)"
  log_debug "$(printf '%b' "$log_message")"

  # Locate the device we will pass to VLC
  if [ -n "$mnt_point" ]; then
    log_info "Received open target argument: $mnt_point"
    dev_path=$(findmnt -no SOURCE --target "$mnt_point" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$dev_path" ]; then
      log_error "Failed to resolve mount point $mnt_point to a device"
      return 1
    else
      log_info "Resolved mount point $mnt_point to device: $dev_path"
    fi
  else
    log_info "No open target argument received. Locate a drive device to open"
    # Get all mounted rom devices
    rom_devices=$(lsblk -o NAME,TYPE,MOUNTPOINT | grep "rom" | awk '$3 != "" {print "/dev/" $1}')
    found_media=0
    for dev in $rom_devices; do
      if udevadm info --query=property --name="$dev" 2>/dev/null | grep -q "ID_CDROM_MEDIA=1"; then
        dev_path="$dev"
        found_media=1
        log_info "Located optical drive device with media: $dev_path"
        break
      else
        log_info "Device $dev does not have media inserted"
      fi
    done
    if [ $found_media -eq 0 ]; then
      log_error "No mounted optical drive with media found."
      return 1
    fi

    # Find mount point for that device
    mnt_point=$(findmnt -no TARGET "$dev_path" 2>/dev/null)
    if [ -z "$mnt_point" ]; then
      log_error "Failed to find mount point for device $dev_path"
      return 1
    else
      log_info "Found mount point $mnt_point for device $dev_path"
    fi
  fi

  # Read info about the device
  dev_info=$(udevadm info --query=property --name="$dev_path" 2>/dev/null)
  if [ $? -ne 0 ] || [ -z "$dev_info" ]; then
    log_error "Failed to query device information for $dev_path"
    return 1
  else
    log_info "$(printf '%b' "Queried device information for $dev_path:\n$dev_info")"
  fi

  # Main Logic handling the disc
  echo "$dev_info" | grep -q "ID_CDROM_MEDIA=1"
  if [ $? -eq 0 ]; then
    log_info "Media detected in drive $dev_path"
    echo "$dev_info" | grep -q "ID_CDROM_MEDIA_BD=1"
    if [ $? -eq 0 ]; then
      log_info "Media in drive $dev_path is a Blu-ray disc"
      # Check if it's a video Blu-ray by looking for the presence of the BDMV folder
      if [ -d "$mnt_point/BDMV" ]; then
        log_info "Blu-ray in drive $dev_path contains BDMV folder. Assuming it's a video Blu-ray."
        exec vlc "bluray://$dev_path" &
      else
        log_info "Blu-ray in drive $dev_path does not contain BDMV folder. Assuming it's a data Blu-ray."
      fi
    else
      echo "$dev_info" | grep -q "ID_CDROM_MEDIA_DVD=1"
      if [ $? -eq 0 ]; then
        log_info "Media in drive $dev_path is a DVD disc"
        # Check for the presence of VIDEO_TS to confirm it's a video DVD
        if [ -d "$mnt_point/VIDEO_TS" ]; then
          log_info "DVD in drive $dev_path contains VIDEO_TS folder. Assuming it's a video DVD."
          exec vlc "dvd://$dev_path" &
        else
          log_info "DVD in drive $dev_path does not contain VIDEO_TS folder. Assuming it's a data DVD."
        fi
      else
        echo "$dev_info" | grep -q "ID_CDROM_MEDIA_CD=1"
        if [ $? -eq 0 ]; then
          log_info "Media in drive $dev_path is a CD disc"
          # Extract number of tracks to determine if it's an audio CD
          echo "$dev_info" | grep -q "ID_CDROM_MEDIA_TRACK_COUNT_AUDIO="
          if [ $? -eq 0 ]; then
            track_count=$(echo "$dev_info" | grep "ID_CDROM_MEDIA_TRACK_COUNT_AUDIO=" | cut -d'=' -f2)
            if [ "$track_count" -gt 2 ]; then
              log_info "CD in drive $dev_path has $track_count audio tracks. Assuming it's an audio CD."
              exec vlc "cdda://$dev_path" &
            else
              log_info "CD in drive $dev_path has less than 3 ($track_count) audio tracks. Assuming it's a data CD."
            fi
          else
            log_info "CD in drive $dev_path does not have audio tracks. Assuming it's a data CD."
          fi
        else
          log_warn "$(printf '%b' "Media in drive $dev_path is an unknown type of optical disc\nDevice information:\n$dev_info")"
        fi
      fi
    fi
  else
    log_error "No media found in drive $dev_path"
  fi
}

# Logging wrappers using logger -t
log_info() {
  logger -t play_optical_media "INFO: $*"
}
log_debug() {
  logger -t play_optical_media "DEBUG: $*"
}
log_error() {
  logger -t play_optical_media "ERROR: $*"
}
log_warn() {
  logger -t play_optical_media "WARN: $*"
}

# Only allow execution, not sourcing or piping
case "$0" in
  *play_optical_media.sh)
    po_main "$@"
    exit $?
    ;;
  *)
    log_error "This script cannot be sourced or piped"
    exit 1
    ;;
esac
