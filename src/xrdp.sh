# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Helpers for xRDP configuration

if [[ -z ${GUARD_XRDP_SH+x} ]]; then
  GUARD_XRDP_SH=1
else
  return 0
fi

xrdp_for_cinnamon() {
  logInfo "Configuring xRDP for Cinnamon desktop"

  # Install xRDP
  if ! pkg_install "xrdp"; then
    logError "Failed to install xRDP"
    return 1
  elif ! sudo adduser xrdp ssl-cert; then
    logError "Failed to add xrdp user to ssl-cert group"
    return 1
  elif ! xrdp_override_start_file; then
    logError "Failed to override xRDP startwm.sh file to start Cinnamon session"
    return 1
  elif ! xrdp_firewall_allow; then
    logError "Failed to allow xRDP through the firewall"
    return 1
  elif ! xrdp_service_enable; then
    logError "Failed to enable and start xRDP service"
    return 1
  elif ! xrdp_configure; then
    logError "Failed to configure xRDP"
    return 1
  elif ! xrdp_fix_audio_pipewirel; then
    logError "Failed to fix xRDP audio redirection"
    return 1
  else
    logDebug "Successfully installed xRDP"
  fi
}

# Fixes audio redirection on Ubuntu Cinnamon 25.10 which doesn't work by default.
# See: https://github.com/neutrinolabs/xrdp/wiki/How-to-set-up-audio-redirection
xrdp_fix_audio_pipewirel() {
  if ! pkg_install "pipewire-module-xrdp"; then
    logError "Failed to install xrdp-pixma package for PipeWire audio redirection support"
    return 1
  else
    logInfo "Successfully installed xrdp-pixma package for PipeWire audio redirection support"
  fi
}

xrdp_firewall_allow() {
  logInfo "Allowing xRDP through the firewall"

  if ! sudo ufw allow 3389/tcp; then
    logError "Failed to allow xRDP through the firewall"
    return 1
  elif ! sudo ufw reload; then
    logError "Failed to reload firewall rules after allowing xRDP"
    return 1
  else
    logInfo "Successfully allowed xRDP through the firewall"
  fi

  return 0
}

xrdp_service_enable() {
  logInfo "Enabling xRDP service"

  if ! sudo systemctl enable xrdp; then
    logError "Failed to enable xRDP service"
    return 1
  elif ! sudo systemctl start xrdp; then
    logError "Failed to start xRDP service"
    return 1
  else
    logInfo "Successfully enabled and started xRDP service"
  fi

  return 0
}

xrdp_configure() {
  logDebug "Configuring xRDP..."

  if ! xrdp_edit_sesman_ini "KillDisconnected" "false"; then
    logError "Failed to set KillDisconnected=false in xRDP sesman.ini file"
    return 1
  elif ! xrdp_edit_sesman_ini "DisconnectedTimeLimit" "600"; then
    logError "Failed to set DisconnectedTimeLimit=0 in xRDP sesman.ini file"
    return 1
  elif ! xrdp_edit_sesman_ini "IdleTimeLimit" "3600"; then
    logError "Failed to set IdleTimeLimit=3600 in xRDP sesman.ini file"
    return 1
  else
    logInfo "Successfully configured xRDP"
  fi

  return 0
}

# Modify config values in /etc/xrdp/sesman.ini.
# Parameters:
#   $1: Setting name (e.g. "KillDisconnected")
#   $2: New value for the setting (e.g. "true")
xrdp_edit_sesman_ini() {
  local _setting="$1"
  local _value="$2"

  local cfg_file="/etc/xrdp/sesman.ini"
  if [[ ! -f "${cfg_file}" ]]; then
    logError "xRDP sesman.ini file not found at expected location: ${cfg_file}"
    return 1
  fi

  # Check if settings is already set to the desired value
  if grep -E "^${_setting}=${_value}$" "${cfg_file}" >/dev/null; then
    logInfo "xRDP sesman.ini already has ${_setting} set to ${_value}"
    return 0
  fi

  # Make sure the setting line exists, and only once
  if ! grep -E "^.*${_setting}=" "${cfg_file}" >/dev/null; then
    logError "Setting ${_setting} not found in xRDP sesman.ini file"
    return 1
  elif [[ $(grep -c -E "^.*${_setting}=" "${cfg_file}" || true) -gt 1 ]]; then
    logError "Multiple lines with setting ${_setting} found in xRDP sesman.ini file"
    return 1
  fi

  # Use sed to replace the line with the new value
  if ! sudo sed -i "s/^.*${_setting}=.*/${_setting}=${_value}/" "${cfg_file}"; then
    logError "Failed to update setting ${_setting} in xRDP sesman.ini file"
    return 1
  else
    logInfo "Successfully updated setting ${_setting} to ${_value} in xRDP sesman.ini file"
  fi

  # Confirm the line now exists with the new value
  if ! grep -E "^${_setting}=${_value}$" "${cfg_file}" >/dev/null; then
    logError "Failed to confirm setting ${_setting} was updated to ${_value} in xRDP sesman.ini file"
    return 1
  fi

  # Now we need to restart the service for the changes to take effect
  if ! sudo systemctl restart xrdp; then
    logError "Failed to restart xRDP service"
    return 1
  fi

  return 0
}

xrdp_override_start_file() {
  local start_file="/etc/xrdp/startwm.sh"

  if [[ ! -f "${start_file}" ]]; then
    logError "xRDP startwm.sh file not found at expected location: ${start_file}"
    return 1
  fi

  local orig_file_prologue
  orig_file_prologue=$(
    cat <<EOF
#!/bin/sh
# xrdp X session start script (c) 2015, 2017, 2021 mirabilos
# published under The MirOS Licence

# Rely on /etc/pam.d/xrdp-sesman using pam_env to load both
# /etc/environment and /etc/default/locale to initialise the
# locale and the user environment properly.

if test -r /etc/profile; then
  . /etc/profile
fi

if test -r ~/.profile; then
  . ~/.profile
fi
EOF
  )

  local file_additions
  file_additions=$(
    cat <<EOF

exec cinnamon-session
EOF
  )

  # If file starts with the expected prologue, replace it.
  # Otherwise, log a warning, backup and replace it.
  if [[ $(head -n "$(wc -l <<<"${orig_file_prologue}")" "${start_file}" || true) == "${orig_file_prologue}" ]]; then
    logInfo "xRDP startwm.sh file has expected prologue, replacing with new content"
  else
    logWarning <<EOF
xRDP startwm.sh file does not have expected prologue. Current file:
$(cat "${start_file}" || true)
EOF
    local bak_file
    if ! file_backup bak_file "${start_file}"; then
      logError "Failed to backup existing xRDP startwm.sh file"
      return 1
    else
      logInfo "Backed up existing xRDP startwm.sh file to: ${bak_file}"
    fi
  fi

  # Overwrite the file with the expected content
  if ! echo "${orig_file_prologue}" | sudo tee "${start_file}" >/dev/null; then
    logError "Failed to write new content to xRDP startwm.sh file"
    return 1
  # Now append the line to start Cinnamon
  elif ! echo "${file_additions}" | sudo tee -a "${start_file}" >/dev/null; then
    logError "Failed to append Cinnamon session start command to xRDP startwm.sh file"
    return 1
  else
    logInfo "Successfully wrote new content to xRDP startwm.sh file: ${start_file}"
  fi
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
XR_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${XR_SOURCE}" ]]; do # resolve $XR_SOURCE until the file is no longer a symlink
  XR_ROOT=$(cd -P "$(dirname "${XR_SOURCE}")" >/dev/null 2>&1 && pwd)
  XR_SOURCE=$(readlink "${XR_SOURCE}")
  [[ ${XR_SOURCE} != /* ]] && XR_SOURCE=${XR_ROOT}/${XR_SOURCE} # if $XR_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
XR_ROOT=$(cd -P "$(dirname "${XR_SOURCE}")" >/dev/null 2>&1 && pwd)
XR_ROOT=$(realpath "${XR_ROOT}/..")

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
  exit
elif ! source "${XR_ROOT}/src/pkg.sh"; then
  logFatal "Failed to import pkg.sh"
elif ! source "${XR_ROOT}/src/file.sh"; then
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
