# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Helpers for a Cinnamon desktop environment configuration

if [[ -z ${GUARD_FILE_CINNAMON+x} ]]; then
  GUARD_FILE_CINNAMON=1
else
  return 0
fi

# Configure Cinnamon to look more like Windows
cn_set_windows_look() {
  logInfo "Configuring Cinnamon to look and behave more like Windows"

  # Prologue
  if ! file_ensure_ini; then
    logError "Failed to ensure INI file support for dconf config files"
    return 1
  elif ! db_ensure_file "${w11_dconf}"; then
    logError "Failed to ensure dconf config files"
    return 1
  fi

  # -----------------------------
  # 🎨 THEME (Mint-L Dark baseline)
  # -----------------------------
  if ! cn_set "${w11_dconf}" "org.cinnamon.desktop.interface" "gtk-theme" "'Mint-L-Dark'" "false"; then
    logError "Failed to set Cinnamon gtk-theme setting"
    return 1
  elif ! cn_set "${w11_dconf}" "org.cinnamon.desktop.interface" "icon-theme" "'Mint-L'" "false"; then
    logError "Failed to set Cinnamon icon-theme setting"
    return 1
  elif ! cn_set "${w11_dconf}" "org.cinnamon.desktop.interface" "cursor-theme" "'DMZ-White'" "false"; then
    logError "Failed to set Cinnamon cursor-theme setting"
    return 1
  elif ! cn_set "${w11_dconf}" "org.cinnamon.desktop.wm.preferences" "theme" "'Mint-L-Dark'" "false"; then
    logError "Failed to set Cinnamon WM theme setting"
    return 1
  else
    logDebug "Successfully configured Cinnamon theme settings"
  fi

  # -----------------------------
  # 🧱 PANEL (taskbar)
  # -----------------------------
  if ! cn_set "${w11_dconf}" "org.cinnamon" "panels-enabled" "['1:0:bottom']" "false"; then
    logError "Failed to configure Cinnamon panels"
    return 1
  elif ! cn_set "${w11_dconf}" "org.cinnamon" "panels-autohide" "['1:false']" "false"; then
    logError "Failed to configure Cinnamon panels"
    return 1
  else
    logDebug "Successfully configured Cinnamon panel settings"
  fi

  # -----------------------------
  # 🪟 WINDOW BEHAVIOR
  # -----------------------------
  if ! cn_set "${w11_dconf}" "org.cinnamon.desktop.wm.preferences" "button-layout" "':minimize,maximize,close'" "false"; then
    logError "Failed to configure Cinnamon window button layout"
    return 1
  elif ! cn_set "${w11_dconf}" "org.cinnamon.desktop.wm.preferences" "focus-mode" "'click'" "false"; then
    logError "Failed to configure Cinnamon focus mode"
    return 1
  elif ! cn_set "${w11_dconf}" "org.cinnamon.desktop.wm.preferences" "raise-on-click" "true" "false"; then
    logError "Failed to configure Cinnamon raise-on-click setting"
    return 1
  else
    logDebug "Successfully configured Cinnamon window behavior settings"
  fi

  # -----------------------------
  # 🧲 WINDOW TILING (Windows-like snapping)
  # -----------------------------
  if ! cn_set "${w11_dconf}" "org.cinnamon.muffin" "edge-tiling" "true" "false"; then
    logError "Failed to configure Cinnamon Muffin edge tiling setting"
    return 1
  else
    logDebug "Successfully configured Cinnamon window tiling settings"
  fi

  # -----------------------------
  # 🖱️ USER INTERACTION
  # -----------------------------
  if ! cn_set "${w11_dconf}" "org.nemo.preferences" "click-policy" "'double'" "false"; then
    logError "Failed to configure Cinnamon click policy"
    return 1
  # elif ! cn_set "${w11_dconf}" "org.cinnamon.desktop" "enable-hot-corners" "false" "false"; then
  #   logError "Failed to disable Cinnamon hot corners"
  #   return 1
  else
    logDebug "Successfully configured Cinnamon user interaction settings"
  fi

  # -----------------------------
  # 🖥️ DESKTOP
  # -----------------------------
  if ! cn_set "${w11_dconf}" "org.nemo.desktop" "show-desktop-icons" "true" "false"; then
    logError "Failed to configure Cinnamon desktop icons setting"
    return 1
  else
    logDebug "Successfully configured Cinnamon desktop settings"
  fi

  # -----------------------------
  # 🎞️ EFFECTS (keep, don't remove)
  # -----------------------------
  if ! cn_set "${w11_dconf}" "org.cinnamon" "desktop-effects" "true" "false"; then
    logError "Failed to configure Cinnamon animations setting"
    return 1
  else
    logDebug "Successfully configured Cinnamon animations settings"
  fi

  # -----------------------------
  # ⌨️ KEYBINDINGS (Windows familiarity)
  # -----------------------------
  if ! cn_set "${w11_dconf}" "org.cinnamon.desktop.keybindings.wm" "show-desktop" "['<Super>d']" false; then
    logError "Failed to configure Cinnamon show-desktop keybinding"
    return 1
  # elif ! cn_set "${w11_dconf}" "org.cinnamon.desktop.keybindings.wm" "toggle-menu" "['Super_L']" true; then
  #   logError "Failed to configure Cinnamon toggle-menu keybinding"
  #   return 1
  else
    logDebug "Successfully configured Cinnamon keybindings"
  fi

  # -----------------------------
  # 🔄 ALT-TAB (modern but not restrictive)
  # -----------------------------
  if ! cn_set "${w11_dconf}" "org.cinnamon" "alttab-switcher-style" "'thumbnails'" false; then
    logError "Failed to configure Cinnamon ALT-TAB switcher style"
    return 1
  else
    logDebug "Successfully configured Cinnamon ALT-TAB switcher style"
  fi

  # -----------------------------
  # 🕒 CLOCK (Windows default style)
  # -----------------------------
  if ! cn_set "${w11_dconf}" "org.cinnamon.desktop.interface" "clock-use-24h" "true" false; then
    logError "Failed to configure Cinnamon clock style"
    return 1
  else
    logDebug "Successfully configured Cinnamon clock style"
  fi

  return 0
}

cm_no_sleep() {
  logInfo "Configuring Cinnamon to prevent sleep on idle"

  # Prologue
  if ! file_ensure_ini; then
    logError "Failed to ensure INI file support for dconf config files"
    return 1
  elif ! db_ensure_file "${sleep_dconf}"; then
    logError "Failed to ensure dconf config files"
    return 1
  fi

  # Configure sleep settings
  if ! cn_set "${sleep_dconf}" "org.cinnamon.desktop.session" "idle-delay" "uint32 0" "true"; then
    logError "Failed to set Cinnamon idle-delay setting"
    return 1
  elif ! cn_set "${sleep_dconf}" "org.cinnamon.desktop.screensaver" "lock-enabled" "false" "true"; then
    logError "Failed to set Cinnamon lock-enabled setting"
    return 1
  elif ! cn_set "${sleep_dconf}" "org.cinnamon.desktop.screensaver" "idle-activation-enabled" "false" "true"; then
    logError "Failed to set Cinnamon idle-activation-enabled setting"
    return 1
  elif ! cn_set "${sleep_dconf}" "org.cinnamon.settings-daemon.plugins.power" "sleep-display-ac" "0" "true"; then
    logError "Failed to set Cinnamon sleep-display-ac setting"
    return 1
  else
    logDebug "Successfully configured Cinnamon sleep settings"
  fi

  return 0
}

# Set a Cinnamon setting
# Parameters:
#   $1[in]: file
#   $2[in]: schema
#   $3[in]: key
#   $4[in]: value
#   $5[in]: lock (true/false)
cn_set() {
  local file="$1"
  local schema="$2"
  local key="$3"
  local value="$4"
  local lock="$5"

  if [[ -z "${file}" ]]; then
    logError "File cannot be empty"
    return 1
  elif [[ -z "${schema}" ]]; then
    logError "Schema cannot be empty"
    return 1
  elif [[ -z "${key}" ]]; then
    logError "Key cannot be empty"
    return 1
  elif [[ -z "${value}" ]]; then
    logError "Value cannot be empty"
    return 1
  elif [[ "${lock}" != "true" && "${lock}" != "false" ]]; then
    logError "Invalid value for lock parameter: ${lock}, expected true or false"
    return 1
  fi

  # Convert schema from setting format to db format
  local schema_path="${schema//./\/}"

  # Current user and session for applying local settings
  local cur_user
  cur_user=$(whoami)
  if [[ -z "${cur_user}" ]]; then
    logError "Failed to determine current user for LightDM dconf settings"
    return 1
  fi
  local sess
  sess="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "${cur_user}")/bus"

  # Read current value
  local value_pre value_res value_reload value_set
  value_pre=$(gsettings get "${schema}" "${key}" 2>/dev/null || true)

  # Reset and set the value
  if ! sudo -u "${cur_user}" "${sess}" dconf reset "/${schema_path}/${key}"; then
    logError "Failed to reset dconf setting ${schema}.${key} before applying new value"
    return 1
  elif ! value_res=$(gsettings get "${schema}" "${key}" 2>/dev/null || true); then
    logError "Failed to read back dconf setting ${schema}.${key} after reset"
    return 1
  elif ! db_set_config "${file}" "/${schema_path}/${key}" "${value}" "${lock}"; then
    logError "Failed to set dconf config for setting ${schema}.${key}"
    return 1
  elif ! sudo dconf update; then
    logError "Failed to update dconf database"
    return 1
  elif ! value_reload=$(gsettings get "${schema}" "${key}" 2>/dev/null || true); then
    logError "Failed to read back dconf setting ${schema}.${key} after database update"
    return 1
  elif ! sudo -u "${cur_user}" "${sess}" gsettings set "${schema}" "${key}" "${value}"; then
    logError "Failed to set dconf setting ${schema}.${key} to value ${value}"
    return 1
  elif ! value_set=$(gsettings get "${schema}" "${key}" 2>/dev/null || true); then
    logError "Failed to read back dconf setting ${schema}.${key} after setting new value"
    return 1
  else
    logDebug "Successfully reset dconf setting ${schema}.${key} to default value ${value_reload}"
  fi

  logInfo <<EOF
Configured dconf setting ${schema}.${key} with value ${value} (lock=${lock})
  Previous value before reset: ${value_pre}
  Value after reset: ${value_res}
  Value after database update: ${value_reload}
  Value after setting new value: ${value_set}
EOF

  # Make sure the final value is the correct one
  if [[ "${value_set}" != "${value}" ]]; then
    logError "dconf setting ${schema}.${key} value mismatch: expected ${value} but got ${value_set}"
    return 1
  fi

  return 0
}

# Configure dconf
# Parameters
#   $1[in]: Path to dconf config file
#   $2[in]: dconf setting to configure
#   $3[in]: dconf value to set
#   $4[in]: Whether to lock the setting (true/false)
db_set_config() {
  local file_path="$1"
  local setting="$2"
  local value="$3"
  local lock="$4"

  # Validate parameters
  if [[ ! -f "${file_path}" ]]; then
    logError "Dconf config file does not exist: ${file_path}"
    return 1
  elif [[ "${lock}" != "true" && "${lock}" != "false" ]]; then
    logError "Invalid value for lock parameter: ${lock}, expected true or false"
    return 1
  elif [[ -z "${setting}" ]]; then
    logError "Setting cannot be empty"
    return 1
  elif [[ -z "${value}" ]]; then
    logError "Value cannot be empty"
    return 1
  fi

  # Parse setting into schema and key
  local schema key
  if [[ "${setting}" =~ ^/(.+)/([^/]+)$ ]]; then
    schema="${BASH_REMATCH[1]}"
    key="${BASH_REMATCH[2]}"
  else
    logError "Invalid dconf setting format: ${setting}, expected schema/key"
    return 1
  fi

  logDebug "Configuring dconf setting: schema=${schema}, key=${key}, value=${value}, lock=${lock}"

  # Check if setting is already set to desired value
  local cur_value
  if ! cur_value=$(sudo crudini --get "${file_path}" "${schema}" "${key}" 2>/dev/null || true); then
    logError "Failed to read current value of dconf setting ${setting} from file ${file_path}"
    return 1
  elif [[ "${cur_value}" == "${value}" ]]; then
    logDebug "dconf setting ${setting} is already set to desired value ${value} in file ${file_path}"
  else
    # Set the value in the config file
    if ! sudo crudini --set "${file_path}" "${schema}" "${key}" "${value}"; then
      logError "Failed to set dconf setting ${setting} to value ${value} in file ${file_path}"
      return 1
    else
      logDebug "Successfully set dconf setting ${setting} to value ${value} in file ${file_path}"
    fi
  fi

  local lock_file
  if ! db_determine_lock_file lock_file "${file_path}"; then
    logError "Failed to determine lock file for dconf config file: ${file_path}"
    return 1
  fi

  # Handle lock
  if [[ "${lock}" == "true" ]]; then
    if ! sudo grep -q "^/${schema}/${key}$" "${lock_file}" 2>/dev/null; then
      logInfo "Locking dconf setting ${setting} by adding to lock file ${lock_file}"
      if ! echo "/${schema}/${key}" | sudo tee -a "${lock_file}" >/dev/null; then
        logError "Failed to add lock for dconf setting ${setting} to lock file ${lock_file}"
        return 1
      else
        logInfo "Successfully added lock for dconf setting ${setting} to lock file ${lock_file}"
      fi
    else
      logDebug "dconf setting ${setting} is already locked in file ${lock_file}"
    fi
  else
    # Remove lock if exists
    if sudo grep -q "^/${schema}/${key}$" "${lock_file}" 2>/dev/null; then
      logInfo "Unlocking dconf setting ${setting} by removing from lock file ${lock_file}"
      if ! sudo sed -i "\|^/${schema}/${key}$|d" "${lock_file}"; then
        logError "Failed to remove lock for dconf setting ${setting} from lock file ${lock_file}"
        return 1
      else
        logInfo "Successfully removed lock for dconf setting ${setting} from lock file ${lock_file}"
      fi
    else
      logDebug "dconf setting ${setting} is already unlocked in file ${lock_file}"
    fi
  fi

  return 0

}

# Determine lock file from dconf file
# Parameters:
#   $1[out]: Path to lock file
#   $2[in]: Path to dconf config file
db_determine_lock_file() {
  local __resultvar="$1"
  local file_path="$2"

  local name sname __lock_file
  name=$(basename "${file_path}")
  # Validate name, and extract without numbered prefix
  if [[ "${name}" =~ ^[0-9]+-(.+)$ ]]; then
    sname="${BASH_REMATCH[1]}"
  elif [[ "${name}" =~ ^([0-9]+)-.+$ ]]; then
    : # num="${BASH_REMATCH[1]}"
  else
    logError "Invalid dconf config file name: ${name}, expected format: NN-name"
    return 1
  fi

  # Lock file
  __lock_file="$(dirname "${file_path}")/locks/${sname}"
  eval "${__resultvar}='${__lock_file}'"

  return 0
}

# Ensure config file exists and have correct permissions for dconf settings
# Parameters:
#   $1[in]: Path to dconf config file
db_ensure_file() {
  local file_path="$1"

  local lock_file
  if ! db_determine_lock_file lock_file "${file_path}"; then
    logError "Failed to determine lock file for dconf config file: ${file_path}"
    return 1
  fi

  if [[ ! -f "${file_path}" ]]; then
    logInfo "Creating dconf config file: ${file_path}"
    if ! sudo mkdir -p "$(dirname "${file_path}")"; then
      logError "Failed to create directory for dconf config file: $(dirname "${file_path}")"
      return 1
    elif ! sudo touch "${file_path}"; then
      logError "Failed to create dconf config file: ${file_path}"
      return 1
    elif ! sudo chown root:root "${file_path}"; then
      logError "Failed to set ownership of dconf config file: ${file_path}"
      return 1
    elif ! sudo chmod 644 "${file_path}"; then
      logError "Failed to set permissions of dconf config file: ${file_path}"
      return 1
    else
      logDebug "Successfully created dconf config file: ${file_path}"
    fi
  fi

  if [[ ! -f "${lock_file}" ]]; then
    logInfo "Creating dconf lock file: ${lock_file}"
    if ! sudo mkdir -p "$(dirname "${lock_file}")"; then
      logError "Failed to create directory for dconf lock file: $(dirname "${lock_file}")"
      return 1
    elif ! sudo touch "${lock_file}"; then
      logError "Failed to create dconf lock file: ${lock_file}"
      return 1
    elif ! sudo chown root:root "${lock_file}"; then
      logError "Failed to set ownership of dconf lock file: ${lock_file}"
      return 1
    elif ! sudo chmod 644 "${lock_file}"; then
      logError "Failed to set permissions of dconf lock file: ${lock_file}"
      return 1
    else
      logDebug "Successfully created dconf lock file: ${lock_file}"
    fi
  fi
}

sleep_dconf="/etc/dconf/db/local.d/00-htpc"
w11_dconf="/etc/dconf/db/local.d/01-w11"

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
CN_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${CN_SOURCE}" ]]; do # resolve $CN_SOURCE until the file is no longer a symlink
  CN_ROOT=$(cd -P "$(dirname "${CN_SOURCE}")" >/dev/null 2>&1 && pwd)
  CN_SOURCE=$(readlink "${CN_SOURCE}")
  [[ ${CN_SOURCE} != /* ]] && CN_SOURCE=${CN_ROOT}/${CN_SOURCE} # if $CN_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
CN_ROOT=$(cd -P "$(dirname "${CN_SOURCE}")" >/dev/null 2>&1 && pwd)
CN_ROOT=$(realpath "${CN_ROOT}/..")

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
elif ! source "${CN_ROOT}/src/file.sh"; then
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
