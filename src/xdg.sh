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
  local setting_prefix="org.cinnamon.desktop.media-handling"

  if ! file_ensure_ini; then
    logError "Failed to ensure crudini is available for MIME type registration"
    return 1
  elif ! db_ensure_file "${XDG_DCONF}"; then
    logError "Failed to ensure dconf database file for Cinnamon media-handling settings"
    return 1
  elif ! cn_set "${XDG_DCONF}" "${setting_prefix}" "automount" "true" "false"; then
    logError "Failed to enable Cinnamon automount"
    return 1
  elif ! cn_set "${XDG_DCONF}" "${setting_prefix}" "automount-open" "true" "false"; then
    logError "Failed to enable Cinnamon automount-open"
    return 1
  elif ! cn_set "${XDG_DCONF}" "${setting_prefix}" "autorun-never" "false" "false"; then
    logError "Failed to disable Cinnamon autorun-never"
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

# Register an actual MIME type and configure Cinnamon autorun for it.
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

  # Configure Cinnamon autorun for this MIME type globally via dconf
  if command -v gsettings >/dev/null 2>&1; then
    local setting_prefix="org.cinnamon.desktop.media-handling"
    local current_ignore new_ignore current_start new_start

    # Remove from ignore list (user may have picked "do nothing" previously)
    if ! current_ignore=$(gsettings get "${setting_prefix}" autorun-x-content-ignore 2>/dev/null); then
      logWarn "Failed to read ${setting_prefix} autorun-x-content-ignore"
    else
      new_ignore=$(CURRENT="${current_ignore}" MIME="${mime_type}" python3 -c "
import os, ast
raw = os.environ['CURRENT'].strip()
lst = [] if raw == '@as []' else ast.literal_eval(raw)
lst = [x for x in lst if x != os.environ['MIME']]
print('@as []' if not lst else '[' + ', '.join(repr(x) for x in lst) + ']')
")
      if ! cn_set "${XDG_DCONF}" "${setting_prefix}" "autorun-x-content-ignore" "${new_ignore}" "false"; then
        logError "Failed to remove ${mime_type} from ${setting_prefix} autorun-x-content-ignore"
        return 1
      fi
    fi

    # Ensure in start-app list
    if ! current_start=$(gsettings get "${setting_prefix}" autorun-x-content-start-app 2>/dev/null); then
      logWarn "Failed to read ${setting_prefix} autorun-x-content-start-app"
    else
      new_start=$(CURRENT="${current_start}" MIME="${mime_type}" python3 -c "
import os, ast
raw = os.environ['CURRENT'].strip()
lst = [] if raw == '@as []' else ast.literal_eval(raw)
if os.environ['MIME'] not in lst:
    lst.append(os.environ['MIME'])
print('@as []' if not lst else '[' + ', '.join(repr(x) for x in lst) + ']')
")
      if ! cn_set "${XDG_DCONF}" "${setting_prefix}" "autorun-x-content-start-app" "${new_start}" "false"; then
        logError "Failed to add ${mime_type} to ${setting_prefix} autorun-x-content-start-app"
        return 1
      fi
    fi

    logDebug "Configured Cinnamon autorun for ${mime_type}"
  else
    logWarn "gsettings not found, skipping Cinnamon autorun configuration for ${mime_type}"
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

# dconf database for global Cinnamon media-handling settings
XDG_DCONF="/etc/dconf/db/local.d/02-optical"

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
elif ! source "${XD_ROOT}/src/cinnamon.sh"; then
  logFatal "Failed to import cinnamon.sh"
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
