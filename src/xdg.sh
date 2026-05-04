# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Helpers for XDG (freedesktop.org) configuration

if [[ -z ${GUARD_FILE_XDG+x} ]]; then
  GUARD_FILE_XDG=1
else
  return 0
fi

xdg_optical_autorun() {
  XDG_OPTICAL_AUTORUN_SRC="${XD_ROOT}/${XDG_OPTICAL_AUTORUN_SRC}"

  if [[ ! -f "${XDG_OPTICAL_AUTORUN_SRC}" ]]; then
    logError "Optical autorun script not found at ${XDG_OPTICAL_AUTORUN_SRC}"
    return 1
  fi

  # Install autorun for optical media
  if ! sudo install "${XDG_OPTICAL_AUTORUN_SRC}" "${XDG_OPTICAL_AUTORUN_DEST}"; then
    logError "Failed to install optical autorun script"
    return 1
  elif ! xdg_install_apps; then
    logError "Failed to install XDG desktop entry for optical autorun script"
    return 1
  elif ! xdg_register_mime; then
    logError "Failed to register MIME type for optical autorun script"
    return 1
  else
    logInfo "Successfully installed optical autorun script and registered it with the system"
  fi

  return 0
}

xdg_register_mime() {
  if ! file_ensure_ini; then
    logError "Failed to ensure crudini is available for MIME type registration"
    return 1
  elif ! xdg_register_mime2 "x-content/video-bluray" "$(basename "${XDG_BD_APP}")"; then
    logError "Failed to register MIME type for Blu-ray discs"
    return 1
  elif ! xdg_register_mime2 "x-content/video-dvd" "$(basename "${XDG_DVD_APP}")"; then
    logError "Failed to register MIME type for DVDs"
    return 1
  elif ! xdg_register_mime2 "x-content/audio-cdda" "$(basename "${XDG_CD_APP}")"; then
    logError "Failed to register MIME type for audio CDs"
    return 1
  else
    logInfo "Successfully registered MIME types for optical media"
  fi

  return 0
}

# Register an actual MIME type
# Parameters
#   $1: MIME type to register (e.g. "x-content/video-bluray")
#   $2: Desktop entry to handle the MIME type (e.g. "xdg-bluray-handler.desktop")
xdg_register_mime2() {
  local mime_type="$1"
  local desktop_entry="$2"

  if [[ -z "${mime_type}" ]] || [[ -z "${desktop_entry}" ]]; then
    logError "MIME type and desktop entry must be provided for MIME registration"
    return 1
  fi

  if ! xdg-mime default "${desktop_entry}" "${mime_type}"; then
    logError "Failed to set default application for MIME type ${mime_type} to ${desktop_entry}"
    return 1
  elif ! sudo crudini --set "${XDG_F_MIME}" "Default Applications" "${mime_type}" "${desktop_entry}"; then
    logError "Failed to register MIME type ${mime_type} with optical autorun script as default handler"
    return 1
  else
    logInfo "Successfully registered MIME type ${mime_type} with optical autorun script as default handler"
  fi

  return 0
}

xdg_install_apps() {
  local bd_hdl
  bd_hdl=$(
    cat <<EOF
[Desktop Entry]
Name=Play Blu-ray (VLC)
Exec=${XDG_OPTICAL_AUTORUN_DEST} %f
Type=Application
MimeType=x-content/video-bluray;
NoDisplay=true
EOF
  )
  local dvd_hdl
  dvd_hdl=$(
    cat <<EOF
[Desktop Entry]
Name=Play DVD (VLC)
Exec=${XDG_OPTICAL_AUTORUN_DEST} %f
Type=Application
MimeType=x-content/video-dvd;
NoDisplay=true
EOF
  )
  local cd_hdl
  cd_hdl=$(
    cat <<EOF
[Desktop Entry]
Name=Play Audio CD (VLC)
Exec=${XDG_OPTICAL_AUTORUN_DEST} %f
Type=Application
MimeType=x-content/audio-cdda;
NoDisplay=true
EOF
  )
  if ! echo "${bd_hdl}" | sudo tee "${XDG_BD_APP}" >/dev/null; then
    logError "Failed to install XDG desktop entry for Blu-ray handler"
    return 1
  elif ! sudo chmod 644 "${XDG_BD_APP}"; then
    logError "Failed to set permissions on XDG desktop entry for Blu-ray handler"
    return 1
  elif ! echo "${dvd_hdl}" | sudo tee "${XDG_DVD_APP}" >/dev/null; then
    logError "Failed to install XDG desktop entry for DVD handler"
    return 1
  elif ! sudo chmod 644 "${XDG_DVD_APP}"; then
    logError "Failed to set permissions on XDG desktop entry for DVD handler"
    return 1
  elif ! echo "${cd_hdl}" | sudo tee "${XDG_CD_APP}" >/dev/null; then
    logError "Failed to install XDG desktop entry for CD handler"
    return 1
  elif ! sudo chmod 644 "${XDG_CD_APP}"; then
    logError "Failed to set permissions on XDG desktop entry for CD handler"
    return 1
  elif ! sudo update-desktop-database; then
    logError "Failed to update desktop database after installing optical media handlers"
    return 1
  else
    logInfo "Successfully installed XDG desktop entries for optical media handlers"
  fi

  return 0
}

# Source script
XDG_OPTICAL_AUTORUN_SRC="data/play_optical_media"
XDG_OPTICAL_AUTORUN_DEST="/usr/local/bin/play_optical_media.sh"

# Application files
XDG_BD_APP="/usr/share/applications/xdg-bluray-handler.desktop"
XDG_DVD_APP="/usr/share/applications/xdg-dvd-handler.desktop"
XDG_CD_APP="/usr/share/applications/xdg-cd-handler.desktop"

# Default MIME
XDG_F_MIME="/etc/xdg/mimeapps.list"

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
XD_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${XD_SOURCE}" ]]; do # resolve $XD_SOURCE until the file is no longer a symlink
  XD_ROOT=$(cd -P "$(dirname "${XD_SOURCE}")" >/dev/null 2>&1 && pwd)
  XD_SOURCE=$(readlink "${XD_SOURCE}")
  [[ ${XD_SOURCE} != /* ]] && XD_SOURCE=${XD_ROOT}/${XD_SOURCE} # if $XD_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
XD_ROOT=$(cd -P "$(dirname "${XD_SOURCE}")" >/dev/null 2>&1 && pwd)
XD_ROOT=$(realpath "${XD_ROOT}/..")

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
elif ! source "${XD_ROOT}/src/file.sh"; then
  logFatal "Failed to import file.sh"
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
