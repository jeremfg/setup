# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# File operation utilities

if [[ -z ${GUARD_FILE_SH+x} ]]; then
  GUARD_FILE_SH=1
else
  return 0
fi

# Ensure a directory exists, creating it if necessary
#
# Parameters:
#   $1[in]: Directory path
# Returns:
#   0: Directory exists or was created successfully
#   1: Directory path not provided or creation failed
file_ensure_dir() {
  local dir_path="${1}"

  if [[ -z "${dir_path}" ]]; then
    logError "Directory path not provided"
    return 1
  elif [[ -d "${dir_path}" ]]; then
    return 0
  elif ! mkdir -p "${dir_path}"; then
    logError "Failed to create directory: ${dir_path}"
    return 1
  fi

  return 0
}

# Make a file executable
#
# Parameters:
#   $1[in]: File path
# Returns:
#   0: Success
#   1: File not found or failed to set permissions
file_executable() {
  local file="${1}"

  if [[ ! -f "${file}" ]]; then
    logError "File not found: ${file}"
    return 1
  elif ! chmod +x "${file}"; then
    logError "Failed to make file executable: ${file}"
    return 1
  fi

  return 0
}

# Set secure file permissions (600)
#
# Parameters:
#   $1[in]: File path
# Returns:
#   0: Success
#   1: File not found or failed to set permissions
file_secure() {
  local file="${1}"

  if [[ ! -f "${file}" ]]; then
    logError "File not found: ${file}"
    return 1
  elif ! chmod 600 "${file}"; then
    logError "Failed to secure file: ${file}"
    return 1
  fi

  return 0
}

# Create a symbolic link (always forces with ln -sf)
#
# Parameters:
#   $1[in]: Source file/directory
#   $2[in]: Link path
# Returns:
#   0: Success
#   1: Source not found or failed to create symlink
file_symlink() {
  local source="${1}"
  local link="${2}"

  if [[ ! -e "${source}" ]]; then
    logError "Source not found: ${source}"
    return 1
  elif ! ln -sf "${source}" "${link}"; then
    logError "Failed to create symlink: ${link} -> ${source}"
    return 1
  fi

  return 0
}

#+#+#+#+---------------------------------------------------------------------
# Get next available filename in numbered sequence (PRIVATE)
#
# Parameters:
#   $1[out]: New filename
#   $2[in]: Desired filename (no suffix)
#   $3[in]: Optional suffix to append after numbering (e.g., ".bak")
# Returns:
#   0: Success
# Note: Creates sequence: file.ext.bak, file.ext.bak.0, file.ext.bak.1, ...
_file_get_next_numbered() {
  local _new="$1"
  local _desired="$2"
  local suffix="${3:-.bak}"
  local -i nb
  local candidate

  candidate="${_desired}${suffix}"
  if [[ ! -f "${candidate}" ]]; then
    eval "${_new}='${candidate}'"
    return 0
  fi

  nb=0
  while :; do
    candidate="${_desired}${suffix}.${nb}"
    if [[ ! -f "${candidate}" ]]; then
      break
    fi
    nb=$((nb + 1))
  done

  eval "${_new}='${candidate}'"
  return 0
}

# Add a configuration line to a file (only if not already present)
#
# Parameters:
#   $1[in]: Configuration file path
#   $2[in]: Configuration line to add
# Returns:
#   0: Success
#   1: Empty line provided or failed to add
file_config_add() {
  local cfg_file="$1"
  local cfg_line="$2"

  if [[ -z "${cfg_line}" ]]; then
    logError "Cannot configure an empty line"
    return 1
  elif [[ -f "${cfg_file}" ]]; then
    if ! grep -q "^${cfg_line}\$" "${cfg_file}"; then
      # Configuration line is absent. Add it
      if ! echo "${cfg_line}" >>"${cfg_file}"; then
        logError "Failed to insert line in configuration: ${cfg_line}"
        return 1
      fi
    else
      logInfo "Configuration line already present: ${cfg_line}"
    fi
  else
    echo "${cfg_line}" >"${cfg_file}"
    logInfo "Created configuration file: ${cfg_file} and added line: ${cfg_line}"
  fi

  return 0
}

# Remove a configuration line from a file
#
# Parameters:
#   $1[in]: Configuration file path
#   $2[in]: Configuration line to remove
# Returns:
#   0: Success
#   1: Empty line provided or failed to remove
file_config_remove() {
  local cfg_file="$1"
  local cfg_line="$2"

  if [[ -z "${cfg_line}" ]]; then
    logError "Cannot remove an empty line"
    return 1
  elif [[ -f "${cfg_file}" ]]; then
    if grep -q "^${cfg_line}\$" "${cfg_file}"; then
      # Configuration line is present. Remove it
      if ! sed -i "/^${cfg_line}$/d" "${cfg_file}"; then
        logError "Failed to remove line in configuration: ${cfg_line}"
        return 1
      fi
    else
      logInfo "Configuration line not present: ${cfg_line}"
    fi
  else
    logWarn "Configuration file not found: ${cfg_file}"
  fi

  return 0
}

# Backup a file (creates numbered backup in stack)
#
# Parameters:
#   $1[out]: Variable to store backup filename
#   $2[in]: File path
#   $3[in]: Backup suffix (optional, default: ".bak")
# Returns:
#   0: Backup created successfully
#   1: File not found or failed to create backup
file_backup() {
  local __result="${1}"
  local file="${2}"
  local suffix="${3:-.bak}"

  if [[ ! -f "${file}" ]]; then
    logError "File not found: ${file}"
    return 1
  fi

  # Get next available filename in sequence (file.txt.bak, file.txt.bak.0, file.txt.bak.1, ...)
  local backup
  if ! _file_get_next_numbered backup "${file}" "${suffix}"; then
    logError "Failed to get backup filename for ${file}"
    return 1
  elif ! cp "${file}" "${backup}"; then
    logError "Failed to backup file: ${file}"
    return 1
  fi

  logInfo "Created backup: ${backup}"
  eval "${__result}='${backup}'"
  return 0
}

# Find the highest numbered backup in the stack (PRIVATE)
#
# Parameters:
#   $1[out]: Variable to store highest backup filename (empty if none found)
#   $2[in]: Original file path
#   $3[in]: Backup suffix (optional, default: ".bak")
# Returns:
#   0: Found backup or no backups exist
_file_backup_find_latest() {
  local __result="${1}"
  local file="${2}"
  local suffix="${3:-.bak}"

  local latest=""
  local -i i=0

  # First check if base backup exists (e.g., file.txt.bak)
  if [[ -f "${file}${suffix}" ]]; then
    latest="${file}${suffix}"
  fi

  # Check for numbered backups (e.g., file.txt.bak.0, file.txt.bak.1, ...)
  while [[ -f "${file}${suffix}.${i}" ]]; do
    latest="${file}${suffix}.${i}"
    ((i++))
  done

  eval "${__result}='${latest}'"
  return 0
}

# Restore a file from the highest numbered backup and remove that backup
#
# Parameters:
#   $1[in]: File path
#   $2[in]: Backup suffix (optional, default: ".bak")
# Returns:
#   0: File restored successfully
#   1: No backup found or restore failed
file_restore() {
  local file="${1}"
  local suffix="${2:-.bak}"

  local backup
  if ! _file_backup_find_latest backup "${file}" "${suffix}"; then
    return 1
  elif [[ -z "${backup}" ]]; then
    logError "No backup found for: ${file}"
    return 1
  elif ! cp "${backup}" "${file}"; then
    logError "Failed to restore from backup: ${backup}"
    return 1
  elif ! rm "${backup}"; then
    logWarn "Restored ${file} but failed to delete backup: ${backup}"
    return 0
  fi

  logInfo "Restored ${file} from backup: ${backup}"
  return 0
}

# Delete the highest numbered backup without restoring (commit changes)
#
# Parameters:
#   $1[in]: File path
#   $2[in]: Backup suffix (optional, default: ".bak")
# Returns:
#   0: Backup deleted successfully
#   1: No backup found or delete failed
file_backup_delete() {
  local file="${1}"
  local suffix="${2:-.bak}"

  local backup
  if ! _file_backup_find_latest backup "${file}" "${suffix}"; then
    return 1
  elif [[ -z "${backup}" ]]; then
    logTrace "No backup found for: ${file}"
    return 0
  elif ! rm "${backup}"; then
    logError "Failed to delete backup: ${backup}"
    return 1
  fi

  logInfo "Deleted backup: ${backup}"
  return 0
}

# Copy a file with error handling (ensures destination directory exists)
#
# Parameters:
#   $1[in]: Source file
#   $2[in]: Destination file/directory
# Returns:
#   0: Success
#   1: Source not found, destination directory creation failed, or copy failed
file_copy() {
  local source="${1}"
  local dest="${2}"

  if [[ ! -f "${source}" ]]; then
    logError "Source file not found: ${source}"
    return 1
  fi

  # Ensure destination directory exists
  local dest_dir
  dest_dir=$(dirname "${dest}")
  if ! file_ensure_dir "${dest_dir}"; then
    return 1
  elif ! cp "${source}" "${dest}"; then
    logError "Failed to copy: ${source} -> ${dest}"
    return 1
  fi

  return 0
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
FL_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${FL_SOURCE}" ]]; do # resolve $FL_SOURCE until the file is no longer a symlink
  FL_ROOT=$(cd -P "$(dirname "${FL_SOURCE}")" >/dev/null 2>&1 && pwd)
  FL_SOURCE=$(readlink "${FL_SOURCE}")
  [[ ${FL_SOURCE} != /* ]] && FL_SOURCE=${FL_ROOT}/${FL_SOURCE} # if $FL_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
FL_ROOT=$(cd -P "$(dirname "${FL_SOURCE}")" >/dev/null 2>&1 && pwd)
FL_ROOT=$(realpath "${FL_ROOT}/..")

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
elif ! source "${FL_ROOT}/src/constants.sh"; then
  logFatal "Failed to import constants.sh"
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
