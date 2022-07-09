#!/usr/bin/env bash

set -eo pipefail

[[ ! -z "${AWSECURE_CLI_AWS_BIN_FILEPATH}" ]] && declare -x AWSECURE_CLI_AWS_BIN_FILEPATH_TMP="${AWSECURE_CLI_AWS_BIN_FILEPATH}"
[[ ! -z "${AWSECURE_CLI_MUTED}" ]] && declare -lx AWSECURE_CLI_MUTED_TMP="${AWSECURE_CLI_MUTED}"
[[ ! -z "${AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS}" ]] && declare -lx AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS_TMP="${AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS}"
[[ ! -z "${AWSECURE_CLI_AUTOROTATE_PERIOD}" ]] && declare -lx AWSECURE_CLI_AUTOROTATE_PERIOD_TMP="${AWSECURE_CLI_AUTOROTATE_PERIOD}"
[[ ! -z "${AWSECURE_CLI_AUTOROTATE_CHECK}" ]] && declare -lx AWSECURE_CLI_AUTOROTATE_CHECK_TMP="${AWSECURE_CLI_AUTOROTATE_CHECK}"

. ~/.awsecure-cli

[[ ! -z "${AWSECURE_CLI_AWS_BIN_FILEPATH_TMP}" ]] && declare -gx AWSECURE_CLI_AWS_BIN_FILEPATH="${AWSECURE_CLI_AWS_BIN_FILEPATH_TMP:-$AWSECURE_CLI_AWS_BIN_FILEPATH}"
[[ ! -z "${AWSECURE_CLI_MUTED_TMP}" ]] && declare -glx AWSECURE_CLI_MUTED="${AWSECURE_CLI_MUTED_TMP:-$AWSECURE_CLI_MUTED}"
[[ ! -z "${AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS_TMP}" ]] && declare -glx AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS="${AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS_TMP:-$AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS}"
[[ ! -z "${AWSECURE_CLI_AUTOROTATE_PERIOD_TMP}" ]] && declare -glx AWSECURE_CLI_AUTOROTATE_PERIOD="${AWSECURE_CLI_AUTOROTATE_PERIOD_TMP:-$AWSECURE_CLI_AUTOROTATE_PERIOD}"
[[ ! -z "${AWSECURE_CLI_AUTOROTATE_CHECK_TMP}" ]] && declare -glx AWSECURE_CLI_AUTOROTATE_CHECK="${AWSECURE_CLI_AUTOROTATE_CHECK_TMP:-$AWSECURE_CLI_AUTOROTATE_CHECK}"

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

declare -lrx AWSECURE_CLI_OS_NAME="$(uname -s)"

function awsecure_cli_date_format() {
  date -u "${@}" +"%s"
}

function awsecure_cli_aws_access_keys_not_older_than() {
  case "${AWSECURE_CLI_OS_NAME// /}" in
  darwin)
    awsecure_cli_date_format -v "-${AWSECURE_CLI_AUTOROTATE_PERIOD// /}H"
    ;;
  linux)
    awsecure_cli_date_format -d "now - ${AWSECURE_CLI_AUTOROTATE_PERIOD// /} hours"
    ;;
  *)
    echo "Unknown OS"
    ;;
  esac
}

function awsecure_cli_get_aws_access_keys() {
  ${AWSECURE_CLI_AWS_BIN_FILEPATH} --output json iam list-access-keys
}

function awsecure_cli_get_aws_access_key_age() {
  jq -r '.AccessKeyMetadata[0].CreateDate' <<< ${AWSECURE_CLI_GET_AWS_ACCESS_KEYS} | sed 's/+.*//'
}

function awsecure_cli_get_aws_access_first_key_id() {
  jq -r '.AccessKeyMetadata[0].AccessKeyId' <<< ${AWSECURE_CLI_GET_AWS_ACCESS_KEYS}
}

function awsecure_cli_validate_aws_access_key() {
  : "${AWSECURE_CLI_CREATED_AWS_ACCESS_KEY:?"Variable not set or empty"}"
  
  jq -r '.AccessKey.Status' <<< "${AWSECURE_CLI_CREATED_AWS_ACCESS_KEY}" | grep "^Active$" &> /dev/null
  
  awsecure_cli_get_aws_access_keys | jq -r ".AccessKeyMetadata[] | select(.AccessKeyId == \"${AWSECURE_CLI_NEW_AWS_ACCESS_KEY_ID}\").Status" | grep "^Active$" &> /dev/null
}

function awsecure_cli_disable_old_access_key() {
  awsecure_cli_log_info "Disabling the old AWS key from AWS"
  sleep 10
  ${AWSECURE_CLI_AWS_BIN_FILEPATH} iam update-access-key --access-key-id "${AWSECURE_CLI_GET_CURRENT_AWS_ACCESS_KEY_ID// /}" --status Inactive
}

function awsecure_cli_remove_old_access_key() {
  awsecure_cli_log_info "Deleting the old AWS key from AWS"
  sleep 10
  ${AWSECURE_CLI_AWS_BIN_FILEPATH} iam delete-access-key --access-key-id "${AWSECURE_CLI_GET_CURRENT_AWS_ACCESS_KEY_ID// /}"
}

function awsecure_cli_change_aws_config_file() {
  awsecure_cli_log_info "Getting the AWS_ACCESS_KEY_ID in use"
  local -r AWSECURE_CLI_GET_CURRENT_AWS_ACCESS_KEY_ID="$(${AWSECURE_CLI_AWS_BIN_FILEPATH} configure get aws_access_key_id)"
  : "${AWSECURE_CLI_GET_CURRENT_AWS_ACCESS_KEY_ID:?"Variable not set or empty"}"

  awsecure_cli_log_info "Getting the AWS_SECRET_ACCESS_KEY in use"
  local -r AWSECURE_CLI_GET_CURRENT_AWS_SECRET_ACCESS_KEY="$(${AWSECURE_CLI_AWS_BIN_FILEPATH} configure get aws_secret_access_key | sed 's,\+,\\+,g')"
  : "${AWSECURE_CLI_GET_CURRENT_AWS_SECRET_ACCESS_KEY:?"Variable not set or empty"}"

  [[ ${AWSECURE_CLI_OS_NAME} == "darwin" ]] && local -r AWSECURE_CLI_SED_CMD=" "

  awsecure_cli_log_info "Setting the new AWS_ACCESS_KEY_ID and disabling the old AWS_ACCESS_KEY_ID in the AWS config file ${AWS_CONFIG_FILE}"
  sed -i${AWSECURE_CLI_SED_CMD}'' -E "s,(${AWSECURE_CLI_GET_CURRENT_AWS_ACCESS_KEY_ID}),${AWSECURE_CLI_NEW_AWS_ACCESS_KEY_ID}\n# AWS_ACCESS_KEY_ID = \\1," ${AWS_CONFIG_FILE}

  awsecure_cli_log_info "Setting the new AWS_SECRET_ACCESS_KEY and disabling the old AWS_SECRET_ACCESS_KEY in the AWS config file ${AWS_CONFIG_FILE}"
  sed -i${AWSECURE_CLI_SED_CMD}'' -E "s,(${AWSECURE_CLI_GET_CURRENT_AWS_SECRET_ACCESS_KEY}),${NEW_AWS_SECRET_ACCESS_KEY}\n# AWS_SECRET_ACCESS_KEY = \\1," ${AWS_CONFIG_FILE}

  awsecure_cli_disable_old_access_key
  awsecure_cli_remove_old_access_key
}

function awsecure_cli_rotate_aws_access_key() {
  awsecure_cli_log_info "Creating a new AWS keys"
  local -r AWSECURE_CLI_CREATED_AWS_ACCESS_KEY="$(${AWSECURE_CLI_AWS_BIN_FILEPATH} --output json iam create-access-key)"
  : "${AWSECURE_CLI_CREATED_AWS_ACCESS_KEY:?"Variable not set or empty"}"

  awsecure_cli_log_info "Getting the new AWS_ACCESS_KEY_ID"
  local -r AWSECURE_CLI_NEW_AWS_ACCESS_KEY_ID="$(jq -r '.AccessKey.AccessKeyId' <<< ${AWSECURE_CLI_CREATED_AWS_ACCESS_KEY})"
  : "${AWSECURE_CLI_NEW_AWS_ACCESS_KEY_ID:?"Variable not set or empty"}"

  awsecure_cli_log_info "Getting the new AWS_SECRET_ACCESS_KEY"
  local -r NEW_AWS_SECRET_ACCESS_KEY="$(jq -r '.AccessKey.SecretAccessKey' <<< ${AWSECURE_CLI_CREATED_AWS_ACCESS_KEY})"
  : "${NEW_AWS_SECRET_ACCESS_KEY:?"Variable not set or empty"}"

  awsecure_cli_log_info "Validating the new AWS_SECRET_ACCESS_KEY"
  awsecure_cli_validate_aws_access_key

  awsecure_cli_log_info "Changing your AWS_CONFIG_FILE"
  awsecure_cli_change_aws_config_file
}

function awsecure_cli_create_autorotate_state_file() {
  set -eo pipefail
  ${AWSECURE_CLI_STATE_FILE_OPTION} ${AWSECURE_CLI_AUTOROTATE_STATE_FILE// /} &> /dev/null
}

function awsecure_cli_autorotate_aws_access_keys() {
  . ${AWSECURE_CLI_SRC_DIRECTORY}/${AWSECURE_CLI_SH_INTERPRETER}/validate-prereqs.sh
  [[ "${SKIP_AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS}" = "true" ]] && return 0

  local -r AWS_CONFIG_FILE=${AWS_CONFIG_FILE:-~/.aws/credentials}

  local -r AWSECURE_CLI_AUTOROTATE_PERIOD="${AWSECURE_CLI_AUTOROTATE_PERIOD:-"168"}"
  local -r AWSECURE_CLI_AWS_ACCESS_KEYS_NOT_OLDER_THAN=$(awsecure_cli_aws_access_keys_not_older_than)
  : "${AWSECURE_CLI_AWS_ACCESS_KEYS_NOT_OLDER_THAN:?"Variable not set or empty"}"

  local -r AWSECURE_CLI_GET_AWS_ACCESS_KEYS="$(awsecure_cli_get_aws_access_keys)"
  : "${AWSECURE_CLI_GET_AWS_ACCESS_KEYS:?"Variable not set or empty"}"

  case "${AWSECURE_CLI_OS_NAME// /}" in
  darwin)
    local -r AWSECURE_CLI_FIRST_AWS_ACCESS_KEY_AGE="$(awsecure_cli_get_aws_access_key_age | xargs -I{} ${AWSECURE_CLI_SH_INTERPRETER} -c "$(declare -f awsecure_cli_date_format) ; awsecure_cli_date_format -jf%Y-%m-%dT%H:%M:%S {}")"
    : "${AWSECURE_CLI_FIRST_AWS_ACCESS_KEY_AGE:?"Variable not set or empty"}"
    ;;
  linux)
    local -r AWSECURE_CLI_FIRST_AWS_ACCESS_KEY_AGE="$(awsecure_cli_get_aws_access_key_age | xargs -I{} ${AWSECURE_CLI_SH_INTERPRETER} -c "$(declare -f awsecure_cli_date_format) ; awsecure_cli_date_format -d {}")"
    : "${AWSECURE_CLI_FIRST_AWS_ACCESS_KEY_AGE:?"Variable not set or empty"}"
    ;;
  *)
    echo "Unknown OS"
    ;;
  esac

  local -r AWSECURE_CLI_FIRST_ACCESS_KEY_ID="$(awsecure_cli_get_aws_access_first_key_id)"

  if [[ ${AWSECURE_CLI_AWS_ACCESS_KEYS_NOT_OLDER_THAN} -gt ${AWSECURE_CLI_FIRST_AWS_ACCESS_KEY_AGE} ]]; then
    awsecure_cli_log_info "Your key ${AWSECURE_CLI_FIRST_ACCESS_KEY_ID} is older than ${AWSECURE_CLI_AUTOROTATE_PERIOD// /} hours"
    awsecure_cli_log_info "Starting renewing your access key ${AWSECURE_CLI_FIRST_ACCESS_KEY_ID}"
    awsecure_cli_rotate_aws_access_key
  else
    awsecure_cli_log_info "No need to renew the access keys ${AWSECURE_CLI_FIRST_ACCESS_KEY_ID}, it's newer than ${AWSECURE_CLI_AUTOROTATE_PERIOD// /} hours"
  fi

  set +eo pipefail
  [[ ! -z "${AWSECURE_CLI_STATE_FILE_OPTION// /}" ]] && awsecure_cli_create_autorotate_state_file
  set -eo pipefail
}

function awsecure_cli_autorotate_check() {
  local -rl AWSECURE_CLI_AUTOROTATE_STATE_FILE=~/.awsecure-cli-state-file-${AWS_PROFILE// /}
  local -rl AWSECURE_CLI_AUTOROTATE_CHECK="${AWSECURE_CLI_AUTOROTATE_CHECK:-"daily"}"
  
  case "${AWSECURE_CLI_AUTOROTATE_CHECK// /}" in
  daily)
    local -r AWSECURE_CLI_STATE_FILE_OPTION="touch"
    set +eo pipefail
    local -r FIND_AWSECURE_CLI_AUTOROTATE_STATE_FILE_CMD="$(find ${AWSECURE_CLI_AUTOROTATE_STATE_FILE} -type f -ctime +24h 2> /dev/null | grep . > /dev/null 2>&1 ; echo $?)"
    set -eo pipefail
    if [[ ! -f ${AWSECURE_CLI_AUTOROTATE_STATE_FILE} ]]; then
      awsecure_cli_autorotate_aws_access_keys
    elif [[ ${FIND_AWSECURE_CLI_AUTOROTATE_STATE_FILE_CMD} -eq 0 ]]; then
      set -eo pipefail
      awsecure_cli_autorotate_aws_access_keys
    else
      awsecure_cli_log_info "AWS Access Keys autorotate was already checked in the last 24h"
    fi
    set -eo pipefail
    ;;
  on-reboot)
    local -r AWSECURE_CLI_STATE_FILE_OPTION="mktemp"
    [[ ! -f ${AWSECURE_CLI_AUTOROTATE_STATE_FILE} ]] && awsecure_cli_autorotate_aws_access_keys || awsecure_cli_log_info "AWS Access Keys autorotate was already checked since the last time you reboot the machine"
    ;;
  always)
    local -r AWSECURE_CLI_STATE_FILE_OPTION=""
    awsecure_cli_autorotate_aws_access_keys
    ;;
  *)
    awsecure_cli_log_info "The option ${AWSECURE_CLI_AUTOROTATE_CHECK} is unknown"
    ;;
  esac
}
awsecure_cli_autorotate_check
