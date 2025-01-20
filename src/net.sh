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

# Upload a file to a URI
#
# Parameters:
#   $1[in]: File to upload
#   $2[in]: URI to upload to
#   $3[in]: Username to use
#   $4[in]: Password to use
# Returns:
#   0: If the file was uploaded
#   1: If an error occurred
nu_file_upload() {
  local __file="${1}"
  local __uri="${2}"
  local __user="${3}"
  local __pwd="${4}"

  if [[ -z ${__file} ]]; then
    logError "File not specified"
    return 1
  elif [[ -z ${__uri} ]]; then
    logError "URI not specified"
    return 1
  elif [[ ! -f "${__file}" ]]; then
    logError "File not found: ${__file}"
    return 1
  fi

  local uri_regex _scheme _usr _pwd _host _port _path _query _anchor _cmd _res _file _code
  if [[ ${__uri} =~ ${NU_URI_REGEX} ]]; then
    _scheme="${BASH_REMATCH[1]}"
    _usr="${BASH_REMATCH[3]}"
    _pwd="${BASH_REMATCH[5]}"
    _host="${BASH_REMATCH[6]}"
    _port="${BASH_REMATCH[9]}"
    _path="${BASH_REMATCH[11]}"
  else
    logError "Invalid URI: \"${__uri}\". Using regex:\n${uri_regex}"
    return 1
  fi

  _file=$(basename "${__file}")

  # URI credentials take precedence
  if [[ -n ${_usr} ]]; then
    logTrace "URI overrides the user"
    __user="${_usr}"
  fi
  if [[ -n ${_pwd} ]]; then
    logTrace "URI overrides the password"
    __pwd="${_pwd}"
  fi

  case "${_scheme}" in
  scp)
    # We're building the command first, so all the validations are performed
    if ! nu_scp_cmd _cmd "${__user}" "${__file}" "${_host}" "${_port}" "${_path}" "true"; then
      logError "Failed to generate SCP command"
      return 1
    fi

    # Test if the file is already on the remote host
    local test_cmd
    test_cmd=(test -e "/${_path}")
    nu_ssh_exec _res "${__user}" "${__pwd}" "${_host}" "${_port}" "${test_cmd[@]}"
    _code=$?
    case ${_code} in
    0)
      logError "File already present on remote\n${_res}"
      return 0
      ;;
    201)
      logInfo "File not present on remote\n${_res}"
      ;;
    255)
      logError "Host not reachable\n${_res}"
      return 1
      ;;
    5)
      logError "Permission denied\n${_res}"
      return 1
      ;;
    127)
      logError "Command not found\n${_res}"
      return 1
      ;;
    *)
      logError "Unknown return code: ${_code}\n${_res}"
      return 1
      ;;
    esac

    # If we reach here, we must upload the file
    if ! nu_scp_cmd _cmd "${__user}" "${__file}" "${_host}" "${_port}" "${_path}" "true"; then
      logError "Failed to generate SCP command"
      return 1
    fi
    nu_sshpass_exec _res "${__pwd}" "${_cmd[@]}"
    _code=$?
    case ${_code} in
    0)
      logInfo "File uploaded\n${_res}"
      return 0
      ;;
    5)
      logError "Permission denied\n${_res}"
      return 1
      ;;
    255)

      logError "Host not reachable\n${_res}"
      return 1
      ;;
    *)
      logError "Unknown return code: ${_code}\n${_res}"
      return 1
      ;;
    esac
    ;;
  file)
    logError "file:// not yet implemented"
    return 1

    # Code in comment is legacy to be used as reference when the time comes to
    # implement it. It for sure doesn't work as-is.

    # # We need to extract the first folder, and use it as share name
    # local path_regex='^(\/[^\/\n?]+)(\/([^\n?]+))*(.*)$'
    # if [[ "${path}" =~ ${path_regex} ]]; then
    #   local share=${BASH_REMATCH[1]}
    #   path=${BASH_REMATCH[3]}
    # else
    #   logFatal "Unable to differentiate share and path in: \"${path}\""
    # fi

    # # Build file check command
    # local uri="//${domain}${port}${share}"
    # local cmd="smbclient '${uri}' -U ${user}%${pwd} -c 'cd \"${path}\" ; ls ${name}'"

    # # Execute check
    # local not_found_regex="^NT_STATUS_NO_SUCH_FILE listing.*${name}$"
    # local found_regex="^${name}.* blocks of size .*$"
    # local res=0
    # res=$(eval "${cmd}")
    # res="$(echo "${res%$'\r'}" | xargs)"
    # local err=$?
    # if [[ ${err} -ne 0 ]]; then
    #   if [[ ${err} -eq 1 ]] && [[ "${res}" =~ ${not_found_regex} ]]; then
    #     logInfo "File does not exists. Proceed with upload..."
    #     logTrace "${res}"
    #   else
    #     logFatal "SMB Failed to list files in: ${uri}/${path} (${err}: ${res})"
    #   fi
    # elif [[ -z "${res}" ]]; then
    #   logFatal "We should not receive an empty response"
    # elif [[ "${res}" =~ ${found_regex} ]]; then
    #   logInfo "File already exists"
    #   logTrace "${res}"
    #   return 0
    # else
    #   echo "${res}"
    #   logFatal "Did we receive an error?"
    # fi

    # # Build upload command
    # local cmd="smbclient '${uri}' -U ${user}%${pwd} -c 'cd \"${path}\" ; put ${i} ${name}'"

    # # Perform the upload
    # logInfo "SMB upload \"$1\" to: ${uri}/${path}"
    # if ! eval "${cmd}"; then
    #   logFatal "SMB Failed to upload \"$1\" to: ${uri}/${path}"
    # else
    #   logInfo "Upload of $1 successful"
    # fi
    # ;;
    ;;
  *)
    logError "Unsupported protocol: ${_scheme}"
    return 1
    ;;
  esac
}

# Generate a valid SCP cmd that can be fed to scp
#
# Parameters:
#   $1[out]: The URI
#   $2[in]:  The username
#   $3[in]:  The local path
#   $4[in]:  The remote host
#   $5[in]:  The remote port
#   $6[in]:  The remote path
#   $7[in]:  is_upload
# Returns:
#   0: If the cmd was generated
#   1: If an error occurred
nu_scp_cmd() {
  local __scp_uri="${1}"
  local __scp_user="${2}"
  local __scp_local="${3}"
  local __scp_host="${4}"
  local __scp_port="${5}"
  local __scp_path="${6}"
  local __scp_upload="${7}"

  if [[ -z ${__scp_local} ]]; then
    logError "Local path not specified"
    return 1
  elif [[ -z ${__scp_host} ]]; then
    logError "Host not specified"
    return 1
  elif [[ -z ${__scp_path} ]]; then
    logError "Path not specified"
    return 1
  elif [[ ! ${__scp_host} =~ ^${NU_REGEX_HOST}$ ]]; then
    logError "Invalid hostname: ${__scp_host}"
    return 1
  elif [[ -n ${__scp_port} ]] && [[ ! "${__scp_port}" =~ ^[0-9]+$ ]]; then
    logError "Invalid port: ${__scp_port}"
    return 1
  elif [[ "${__scp_upload}" != "false" ]] && [[ "${__scp_upload}" != "true" ]]; then
    logError "Invalid upload flag: ${__scp_upload}"
    return 1
  elif [[ ! -f "${__scp_local}" ]] && [[ ! -d "${__scp_local}" ]]; then
    logError "Local file not found: ${__scp_local}"
    return 1
  fi

  local _scp_loc _scp_rem _scp_cmd _scp_res _scp_code
  _scp_loc="${__scp_local}"
  _scp_rem=""
  if [[ -n ${__scp_user} ]]; then
    _scp_rem+="${__scp_user}@"
  fi
  _scp_rem+="${__scp_host}"
  _scp_rem+=":/${__scp_path}"
  _scp_cmd=()
  _scp_cmd+=(scp -o "StrictHostKeyChecking=no" -v)
  if [[ -n ${__scp_port} ]]; then
    _scp_cmd+=(-P "${__scp_port}")
  fi
  if [[ "${__scp_upload}" == "true" ]]; then
    _scp_cmd+=("${_scp_loc}")
    _scp_cmd+=("${_scp_rem}")
  else
    _scp_cmd+=("${_scp_rem}")
    _scp_cmd+=("${_scp_loc}")
  fi

  eval "${__scp_uri}=(\"\${_scp_cmd[@]}\")"
}

# Execute a command on a remote host via SSH
#
# Parameters:
#   $1[out]: The command output
#   $2[in]:  The username
#   $3[in]:  The password
#   $4[in]:  The host
#   $5[in]:  The port
#   $@[in]:  The command to execute
# Returns:
#   1: If an error occured
#   $?: The return code of the command
nu_ssh_exec() {
  local __ssh_output="${1}"
  local __ssh_user="${2}"
  local __ssh_pwd="${3}"
  local __ssh_host="${4}"
  local __ssh_port="${5}"
  shift 5

  # Validate inputs
  if ! command -v ssh &>/dev/null; then
    logError "ssh tool not found"
    return 1
  elif [[ -z ${__ssh_host} ]]; then
    logError "Host not specified"
    return 1
  elif [[ ! "${__ssh_host}" =~ ^${NU_REGEX_HOST}$ ]]; then
    logError "Invalid hostname: ${__ssh_host}"
    return 1
  elif [[ -n ${__ssh_port} ]] && [[ ! "${__ssh_port}" =~ ^[0-9]+$ ]]; then
    logError "Invalid port: ${__ssh_port}"
    return 1
  fi

  # Build the SSH command
  local _ssh_uri _ssh_cmd _ssh_res _ssh_code
  _ssh_cmd=(ssh -o "StrictHostKeyChecking=no")
  if [[ -n ${__ssh_port} ]]; then
    _ssh_cmd+=(-P "${__ssh_port}")
  fi
  _ssh_uri=""
  if [[ -n ${__ssh_user} ]]; then
    _ssh_uri+="${__ssh_user}@"
  fi
  _ssh_uri+="${__ssh_host}"
  _ssh_cmd+=("${_ssh_uri}")
  _ssh_cmd+=("$@")

  nu_sshpass_exec _ssh_res "${__ssh_pwd}" "${_ssh_cmd[@]}"
  _ssh_code=$?

  # To distinguish between a failed command and a failed connection
  if [[ ${_ssh_code} -eq 201 ]]; then
    logWarn "It will be difficult to distinguish between a true error 201 and 1"
  elif [[ ${_ssh_code} -eq 1 ]]; then
    _ssh_code=201
  fi

  if [[ -n ${__ssh_output} ]]; then
    eval "${__ssh_output}='${_ssh_res}'"
  fi

  # shellcheck disable=SC2248
  return ${_ssh_code}
}

# Execute a command that may require a SSH password
#
# Parameters:
#   $1[out]: The result of executing the command
#   $2[in]:  The password to use
#   $@[in]:  The command to execute
# Returns:
#   1: If an error occured
#   $?: The return code of the command
nu_sshpass_exec() {
  local __sshpass_output="${1}"
  local __sshpass_pwd="${2}"
  shift 2

  if ! command -v sshpass &>/dev/null; then
    logError "sshpass tool not found"
    return 1
  fi

  local _pass_cmd _pass_cmd_p _pass_res _pass_code
  _pass_cmd=()
  _pass_cmd_p=()
  if [[ -n ${__sshpass_pwd} ]]; then
    _pass_cmd+=(sshpass -p "${__sshpass_pwd}")
    _pass_cmd_p+=(sshpass -p "********")
  fi
  _pass_cmd+=("$@")
  _pass_cmd_p+=("$@")

  logTrace "Executing command: ${_pass_cmd_p[*]}"
  _pass_res=$("${_pass_cmd[@]}" 2>&1)
  _pass_code=$?

  if [[ ${_pass_code} -ne 0 ]]; then
    logError <<EOF
Failed to Execute command: ${_pass_cmd_p[*]}

Return Code: ${_pass_code}
Output:
${_pass_res}
EOF
  else
    logTrace "Command executed successfully\n${_pass_res}"
  fi

  if [[ -n ${__sshpass_output} ]]; then
    eval "${__sshpass_output}='${_pass_res}'"
  fi

  # shellcheck disable=SC2248
  return ${_pass_code}
}

# Variables loaded externally

#########################
## URI parsing regexes ##
#########################
# == Capture Group ==      - Description
# ${BASH_REMATCH[0]}"      -
# ${BASH_REMATCH[1]}"      - Scheme
# ${BASH_REMATCH[2]}"      -
# ${BASH_REMATCH[3]}"      - User->User (Authority)
# ${BASH_REMATCH[4]}"      -
# ${BASH_REMATCH[5]}"      - User->Password (Authority)
# ${BASH_REMATCH[6]}"      - Host (Authority)
# ${BASH_REMATCH[7]}"      -
# ${BASH_REMATCH[8]}"      - :Port (Authority)
# ${BASH_REMATCH[9]}"      - Port (Authority)
# ${BASH_REMATCH[10]}"     - /Path
# ${BASH_REMATCH[11]}"     - Path
# ${BASH_REMATCH[12]}"     -
# ${BASH_REMATCH[13]}"     - ?Query
# ${BASH_REMATCH[14]}"     - Query
# ${BASH_REMATCH[15]}"     -
# ${BASH_REMATCH[16]}"     - #Fragment
# ${BASH_REMATCH[17]}"     - Fragment
NU_REGEX_SCHEME='([a-zA-Z0-9+.-]+):\/\/'
NU_REGEX_USER='(([a-zA-Z0-9._~!$&'\''()*+,;=/-]+)(:([a-zA-Z0-9._~!$&'\''()*+,;=/-]+))?@)'
NU_REGEX_HOST='(([a-zA-Z0-9._~!$&'\''()*+,;=-]|%[0-9A-F]{2})+)'
NU_REGEX_PORT='(:([0-9]+))'
NU_REGEX_PATH='(\/(([a-z0-9._~!$.&'\''()*+,;=:/@-]|%[0-9A-F]{2})+))'
NU_REGEX_QUERY='(\?(([a-z0-9._~!$&'\''()*+,;=:/?@-]|%[0-9A-F]{2})+))'
NU_REGEX_FRAGMENT='(#(([a-z0-9._~!$&'\''()*+,;=:/?@-]|%[0-9A-F]{2})+))'

# Full URI regex
NU_URI_REGEX="^${NU_REGEX_SCHEME}${NU_REGEX_USER}?${NU_REGEX_HOST}\
${NU_REGEX_PORT}?${NU_REGEX_PATH}?${NU_REGEX_QUERY}?${NU_REGEX_FRAGMENT}?$"

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
