#!/usr/bin/env bash

set -eo pipefail

[[ ! -z "${AWSECURE_CLI_AWS_BIN_FILEPATH}" ]] && declare -x AWSECURE_CLI_AWS_BIN_FILEPATH_TMP="${AWSECURE_CLI_AWS_BIN_FILEPATH}"
[[ ! -z "${AWSECURE_CLI_MUTED}" ]] && declare -lx AWSECURE_CLI_MUTED_TMP="${AWSECURE_CLI_MUTED}"

. ~/.awsecure-cli

[[ ! -z "${AWSECURE_CLI_AWS_BIN_FILEPATH_TMP}" ]] && declare -gx AWSECURE_CLI_AWS_BIN_FILEPATH="${AWSECURE_CLI_AWS_BIN_FILEPATH_TMP:-$AWSECURE_CLI_AWS_BIN_FILEPATH}"
[[ ! -z "${AWSECURE_CLI_MUTED_TMP}" ]] && declare -glx AWSECURE_CLI_MUTED="${AWSECURE_CLI_MUTED_TMP:-$AWSECURE_CLI_MUTED}"

if [[ $(type awsecure_cli_log_info 2> /dev/null) == "" || -z "${AWSECURE_CLI_SRC_DIRECTORY// /}" ]]; then
  [[ -L ${0} ]] && declare -gr AWSECURE_CLI_SRC_DIRECTORY="$(realpath $(readlink ${0}) | xargs dirname)/../../src" || declare -gr AWSECURE_CLI_SRC_DIRECTORY="$(realpath ${0} | xargs dirname)/../../src"
  . ${AWSECURE_CLI_SRC_DIRECTORY}/common/logging.shinc
fi

if [[ ! -z "${ZSH_NAME}" ]]; then
  declare -lr AWSECURE_CLI_SH_INTERPRETER="zsh"
elif [[ ! -z "${BASH}" ]]; then
  declare -lr AWSECURE_CLI_SH_INTERPRETER="bash"
else
  awsecure_cli_log_error "SH Interpreter not supported or not defined"
fi

function awsecure_cli_auto_get_first_mfa_device() {
  awsecure_cli_get_user
  ${AWSECURE_CLI_AWS_BIN_FILEPATH} iam list-mfa-devices --user-name "${AWSECURE_CLI_USERNAME}" | jq -r '.MFADevices[0].SerialNumber'
}

function awsecure_cli_get_user() {
  local -r AWSECURE_CLI_USER_ARN="$(${AWSECURE_CLI_AWS_BIN_FILEPATH} sts get-caller-identity | jq -r '.Arn')"
  local -rg AWSECURE_CLI_USERNAME="${AWSECURE_CLI_USER_ARN//*\/}"
}

function awsecure_cli_set_mfa_session_token() {
  local -r AWSECURE_CLI_MFA_TOKEN_FILE=~/.awsecure-cli-mfa-session-token-${AWS_PROFILE// /}
  local -i AWSECURE_CLI_MFA_TOKEN_DURATION_SECOND="${AWSECURE_CLI_MFA_TOKEN_DURATION_SECOND:-"900"}"

  awsecure_cli_mfa_check_session_age
  case "${AWSECURE_CLI_MFA_CHECK_SESSION_AGE// /}" in
  older|none)
    awsecure_cli_log_info "Your MFA session token is older than ${AWSECURE_CLI_MFA_TOKEN_DURATION_SECOND}, renewing it."
    echo "Please, inform your MFA code (e.g. 123 456): "
    read -r AWSECURE_CLI_MFA_CODE_TMP
    local -r AWSECURE_CLI_MFA_CODE="${AWSECURE_CLI_MFA_CODE_TMP// /}"

    local -r AWS_SESSION_TOKEN="$(${AWSECURE_CLI_AWS_BIN_FILEPATH} sts get-session-token --serial-number "${AWSECURE_CLI_MFA_AWS_ARN}" --token-code ${AWSECURE_CLI_MFA_CODE} --duration-second "${AWSECURE_CLI_MFA_TOKEN_DURATION_SECOND}" | jq -r '.Credentials.SessionToken')"
    : "${AWS_SESSION_TOKEN:?"Variable not set or empty"}"

    rm -f ${AWSECURE_CLI_MFA_TOKEN_FILE}
    echo "AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}" > ${AWSECURE_CLI_MFA_TOKEN_FILE}
    chmod 0400 ${AWSECURE_CLI_MFA_TOKEN_FILE}
    ;;
  newer)
    awsecure_cli_log_info "Your MFA session token is newer than ${AWSECURE_CLI_MFA_TOKEN_DURATION_SECOND}, reusing it."
    . ${AWSECURE_CLI_MFA_TOKEN_FILE}
    ;;
  esac
}

function awsecure_cli_mfa_check_session_age() {
  [[ -f ${AWSECURE_CLI_MFA_TOKEN_FILE} ]] && local -lrg AWSECURE_CLI_MFA_CHECK_SESSION_AGE="$(find ${AWSECURE_CLI_MFA_TOKEN_FILE} -type f -newermt "-${AWSECURE_CLI_MFA_TOKEN_DURATION_SECOND} seconds" | grep . > /dev/null 2>&1 && echo "newer" || echo "older")" || local -lrg AWSECURE_CLI_MFA_CHECK_SESSION_AGE="none"
}

function awsecure_cli_mfa_session_token() {
  awsecure_cli_mfa_check_session_age
}

function awsecure_cli_add_mfa_check() {
  local -r AWSECURE_CLI_MFA_AUTO_GET_DEVICE="${AWSECURE_CLI_MFA_AUTO_GET_DEVICE:-true}"
  
  case "${AWSECURE_CLI_MFA_AUTO_GET_DEVICE// /}-${AWSECURE_CLI_MFA_AWS_ARN// /}" in
  true-*)
    local -r AWSECURE_CLI_MFA_AWS_ARN="$(awsecure_cli_auto_get_first_mfa_device)"
    awsecure_cli_set_mfa_session_token
    ;;
  false-arn:aws:iam*)
    awsecure_cli_set_mfa_session_token
    ;;
  *)
    awsecure_cli_log_error "Invalid values for AWSECURE_CLI_MFA_AUTO_GET_DEVICE and/or AWSECURE_CLI_MFA_AWS_ARN"
    ;;
  esac
}
awsecure_cli_add_mfa_check
