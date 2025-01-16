# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Web crawling utilities

# Prevent sourcing this script
if [[ -z ${GUARD_WEB_SH} ]]; then
  GUARD_WEB_SH=1
else
  logWarn "Re-sourcing web.sh"
  return 0
fi

# Retrieves the latest version of TrueNAS SCALE
#
# Parameters:
#   $1[out]: The variable to store the latest version
# Returns:
#   0: If the latest version was successfully retrieved
#   1: If an error occurred
truenas_scale_latest_url() {
  local __result_url="${1}"

  if ! command -v curl &>/dev/null; then
    logError "curl not found"
    return 1
  fi

  local url regex_a html_content res
  url="https://www.truenas.com/download-truenas-scale/"
  regex_a='<a([^<]+)href="([^"]+)"[^<]+Download STABLE</a>'

  if ! html_content=$(curl -s "${url}"); then
    logError "Failed to retrieve TrueNAS SCALE download page"
    return 1
  elif [[ "${html_content}" =~ ${regex_a} ]]; then
    res="${BASH_REMATCH[2]}"
    # Make sure the URL is of the form https://...
    if [[ ! ${res} =~ ^https:// ]]; then
      logError "Invalid URL: ${res}"
      return 1
    fi
    logInfo "Latest TrueNAS SCALE URL: ${res}"
    eval "${__result_url}='${res}'"
    return 0
  else
    logError "Failed to parse TrueNAS SCALE download page"
    return 1
  fi
}

# Download the specifided URL
#
# Parameters:
#   $1[out]: The file that was downloaded
#   $1[in]: The URL to download
#   $2[in]: The output directory
# Returns:
#   0: If the file is available locally
#   1: If an error occurred
web_download() {
  local __result_file="${1}"
  local url="${2}"
  local output_dir="${3}"

  if ! command -v curl &>/dev/null; then
    logError "curl not found"
    return 1
  fi

  if [[ -z ${url} ]]; then
    logError "URL not specified"
    return 1
  elif [[ -z ${output_dir} ]]; then
    logError "Output directory not specified"
    return 1
  fi

  if [[ ! -d ${output_dir} ]]; then
    logWarn "Output directory does not exist: ${output_dir}"
    if ! mkdir -p "${output_dir}"; then
      logError "Failed to create output directory: ${output_dir}"
      return 1
    fi
  fi

  local file
  file=$(basename "${url}")
  if [[ -f "${output_dir}/${file}" ]]; then
    logInfo "File already downloaded: ${output_dir}/${file}"
    eval "${__result_file}='${output_dir}/${file}'"
    return 0
  fi

  logInfo "Downloading: ${url}"
  if ! curl -Lo "${output_dir}/${file}" "${url}"; then
    logError "Failed to download: ${url}"
    return 1
  fi

  logInfo "Downloaded: ${output_dir}/${file}"
  eval "${__result_file}='${output_dir}/${file}'"
  return 0
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
WEB_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${WEB_SOURCE}" ]]; do # resolve $WEB_SOURCE until the file is no longer a symlink
  WEB_ROOT=$(cd -P "$(dirname "${WEB_SOURCE}")" >/dev/null 2>&1 && pwd)
  WEB_SOURCE=$(readlink "${WEB_SOURCE}")
  [[ ${WEB_SOURCE} != /* ]] && WEB_SOURCE=${WEB_ROOT}/${WEB_SOURCE} # if $WEB_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
WEB_ROOT=$(cd -P "$(dirname "${WEB_SOURCE}")" >/dev/null 2>&1 && pwd)
WEB_ROOT=$(realpath "${WEB_ROOT}/..")

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
  logFatal "This script cannot be executed"
fi
