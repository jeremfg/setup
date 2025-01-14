# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Network utilities

if [[ -z ${GUARD_NETUTILS_SH} ]]; then
  GUARD_NETUTILS_SH=1
else
  return 0
fi

# Wait until DNS is answering for a specific domain
#
# Parameters:
#   $1[in]: Domain to wait for
#   $2[in]: DNS server to query
#   $3[in]: Timeout in seconds
# Returns:
#   0: If DNS is answering
#   1: If DNS is not answering
nu_wait_dns() {
  local domain="${1}"
  local dns_server="${2}"
  local timeout="${3}"

  local cmd end_time res
  if command -v nslookup &>/dev/null; then
    cmd="nslookup"
  elif command -v dig &>/dev/null; then
    cmd="dig"
  else
    logError "No DNS tool found"
    return 1
  fi

  end_time=$(($(date +%s) + timeout))
  while true; do
    case "${cmd}" in
    nslookup)
      if res=$(nslookup "${domain}" "${dns_server}"); then
        break
      else
        logTrace "No DNS answer: ${res}"
      fi
      ;;
    *)
      logError "Unknown DNS tool"
      return 1
      ;;
    esac

    if [[ $(date +%s || true) -lt ${end_time} ]]; then
      logError "Timeout reached while waiting for a DNS answer about ${domain}"
      return 1
    else
      sleep 1
    fi
  done

  logInfo "DNS is answering: ${res}"
  return 0
}

# Wait until a host is reachable
#
# Parameters:
#   $1[in]: Host to wait for
#   $2[in]: Timeout in seconds
# Returns:
#   0: If host is reachable
#   1: If host is not reachable
nu_wait_ping() {
  local host="${1}"
  local timeout="${2}"

  local end_time
  end_time=$(($(date +%s) + timeout))
  while true; do
    if ping -c 1 -w 1 "${host}" &>/dev/null; then
      break
    fi

    if [[ $(date +%s || true) -lt ${end_time} ]]; then
      logError "Timeout reached while waiting for ${host}"
      return 1
    else
      sleep 1
    fi
  done

  logInfo "Host is reachable: ${host}"
  return 0
}

# Variables loaded externally

# Constants

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
NU_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${NU_SOURCE}" ]]; do # resolve $NU_SOURCE until the file is no longer a symlink
  NU_ROOT=$(cd -P "$(dirname "${NU_SOURCE}")" >/dev/null 2>&1 && pwd)
  NU_SOURCE=$(readlink "${NU_SOURCE}")
  [[ ${NU_SOURCE} != /* ]] && NU_SOURCE=${NU_ROOT}/${NU_SOURCE} # if $NU_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
NU_ROOT=$(cd -P "$(dirname "${NU_SOURCE}")" >/dev/null 2>&1 && pwd)
NU_ROOT=$(realpath "${NU_ROOT}/..")

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
