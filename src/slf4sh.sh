#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Source this into any shell script you wish to add logging support.
# Inspired From: https://serverfault.com/a/103569

# LEVEL_ALL appears unused. Verify use (or export if used externally).
# LEVEL_OFF appears unused. Verify use (or export if used externally).
# shellcheck disable=2034

LEVEL_ALL=0    # Enable all possible logs.
LEVEL_TEST=1   # Only used by developers to temporarily add logs that should never get commited.
LEVEL_TRACE=2  # Low level tracing of very detailed specifc information.
LEVEL_DEBUG=3  # Might allow to investigate and resolve a bug.
LEVEL_INFO=4   # Default level. High level indications of the paths the code took.
LEVEL_WARN=5   # Unusual behavior that don't cause an issue to the current execution.
LEVEL_ERROR=6  # A recoverable error occured. The program is still executing properly but the user is not getting the desired outcome.
LEVEL_FATAL=7  # Unrecoverable error. Program is exiting immediately for safety as it wasn't designed to continue after this.
LEVEL_OFF=8    # Turns of all logs

# If no level is configured, start at INFO
if [[ -z "${LOG_LEVEL}" ]]; then
  LOG_LEVEL=${LEVEL_ALL}
fi

# By default do not print logs on the console but only in the log file
if [[ -z "${LOG_CONSOLE}" ]]; then
  LOG_CONSOLE=1             
fi
# Set the log level
#
# @parms[in] #1: The logging level to be used from now on, using one of the LEVEL_* values
logSetLevel() {
  LOG_LEVEL=$1
}

logFatal() {
  if [[ "${LOG_LEVEL}" -le ${LEVEL_FATAL} ]]; then
    log "FATAL " "$@"
  fi
    exit 1
}

logError() {
  if [[ "${LOG_LEVEL}" -le ${LEVEL_ERROR} ]]; then
    log "ERROR " "$@"
  fi
}

logWarn() {
  if [[ "${LOG_LEVEL}" -le ${LEVEL_WARN} ]]; then
    log "WARN  " "$@"
  fi
}

logInfo() {
  if [[ "${LOG_LEVEL}" -le ${LEVEL_INFO} ]]; then
    log "INFO  " "$@"
  fi
}

logDebug() {
  if [[ "${LOG_LEVEL}" -le ${LEVEL_DEBUG} ]]; then
    log "DEBUG " "$@"
  fi
}

logTrace() {
  if [[ "${LOG_LEVEL}" -le ${LEVEL_TRACE} ]]; then
    log "TRACE " "$@"
  fi
}

logTest() {
    if [[ "${LOG_LEVEL}" -le ${LEVEL_TEST} ]]; then
        log "TEST  " "$@"
  fi
}

log() {
  local date=0
  local time=0
  local full=0
  date=$(date +%F)
  time=$(date +%H:%M:%S)
  full="${date} ${time}"

  local level="$1"
  shift

  local out_line
  if [[ -z "$@" ]]; then
    local line
    out_line="(message from pipe follows below)"
    while IFS= read -r line; do
      out_line+="\n$line"
    done
  else
    out_line="$@"
  fi

  if [[ "${LOG_CONSOLE}" == 1 ]]; then
    echo -e "${full} $level$out_line"
  else
    echo -e "${full} $level$out_line" >> "${SL_LOGFILE}"
  fi
}

sl_init() {
  local start_date="$(date +%F)"
  local start_time="$(date +%H%M%S)"
  local start="${start_date}_${start_time}"
  local logDir="${SL_ROOT}"

  # If git is supported, try to find parent repository root
  if command -v git &> /dev/null; then
    local curDir
    curDir="$(cd "${logDir}" && git rev-parse --show-toplevel)"
    # Walk-up the tree to exit any potential git repository
    while true; do
      # Check if parent is inside a git repository
      if $(cd "${curDir}/.." && git rev-parse --is-inside-work-tree &> /dev/null); then
        curDir="$(cd "${curDir}/.." && git rev-parse --show-toplevel)"
        curDir="$(realpath ${curDir})"
      else
        logDir="${curDir}"
        break; # We've escaped outside of the git repo
      fi
    done
  fi

  # Path Configuration
  declare -g SL_LOGFILE
  SL_LOGFILE="${logDir}/.log/${SL_ME%.*}_${start}.log"

  # Setup logging
  mkdir -p "${logDir}/.log" # Create log directory
  exec 3>&1 4>&2 # Backup old descriptors
  trap 'exec 2>&4 1>&3' 0 1 2 3 # Restore in case of signals
  # shellcheck disable=2312
  exec &> >(tee -a "${SL_LOGFILE}") # Redirect output
}

###########################
###### Startup logic ######
###########################
SL_ARGS=("$@")
SL_CWD=$(pwd)
SL_ME="$(basename "$0")"

# Get directory of this script
# https://stackoverflow.com/a/246128
SL_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${SL_SOURCE}" ]]; do # resolve $SL_SOURCE until the file is no longer a symlink
  SL_ROOT=$(cd -P "$(dirname "${SL_SOURCE}")" >/dev/null 2>&1 && pwd)
  SL_SOURCE=$(readlink "${SL_SOURCE}")
  [[ ${SL_SOURCE} != /* ]] && SL_SOURCE=${SL_ROOT}/${SL_SOURCE} # if $SL_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SL_ROOT=$(cd -P "$(dirname "${SL_SOURCE}")" >/dev/null 2>&1 && pwd)
SL_ROOT=$(realpath "${SL_ROOT}/..")

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  echo "ERROR: This script cannot be piped"
  exit 1
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  if [[ -z "${SLF4SH_INCLUDED}" ]]; then
    SLF4SH_INCLUDED=1
    sl_init
  fi
else
  # This script was executed
  echo "ERROR: This script cannot be executed"
  exit 1
fi
