#!/bin/env sh
# SPDX-License-Identifier: MIT
#
# Mounting drives specified by Active Directory

# Main entry point
ad_drive_mount() {
  # Validate dependencies

  # Data retrieval
  domain=$(realm list --name-only)
  sysvol="${SYSVOL_CACHE_DIR}/${domain}"

  # Validation
  if [ ! -d "${sysvol}" ]; then
    logError "Sysvol cache directory ${sysvol} does not exist."
    return 1
  fi

  # Main Logic
  # Iterate over all drive and folder mapping files
  find "${sysvol}" -type f \( -name 'Drives.xml' \) | while read -r drive_file; do
    logInfo "Processing drive mapping file: ${drive_file}"
  done
  find "${sysvol}" -type f \( -name 'Folders.xml' \) | while read -r folder_file; do
    logInfo "Processing folder mapping file: ${folder_file}"
  done
}

logError() {
  logger -t "${LOGGER_NAME}" "ERROR: ${*}"
}

logWarn() {
  logger -t "${LOGGER_NAME}" " WARN: ${*}"
}

logInfo() {
  logger -t "${LOGGER_NAME}" " INFO: ${*}"
}

logDebug() {
  logger -t "${LOGGER_NAME}" "DEBUG: ${*}"
}

# Global variables
LOGGER_NAME="ad_mount"
SYSVOL_CACHE_DIR="/var/cache/sysvol"

logger -t "${LOGGER_NAME}" "Starting AD Drive Mount for: ${USER}"
ad_drive_mount "${@}"
res="${?}"
logger -t "${LOGGER_NAME}" "Finished AD Drive Mount with status: ${res}"
exit ${res}
