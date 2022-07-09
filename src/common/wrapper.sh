#!/usr/bin/env bash

if [[ $(type awsecure_cli_log_info 2> /dev/null) == "" || -z "${AWSECURE_CLI_SRC_DIRECTORY// /}" ]]; then
  [[ -L ${0} ]] && declare -gr AWSECURE_CLI_SRC_DIRECTORY="$(realpath $(readlink ${0}) | xargs dirname)/../../src" || declare -gr AWSECURE_CLI_SRC_DIRECTORY="$(realpath ${0} | xargs dirname)/../../src"
  . ${AWSECURE_CLI_SRC_DIRECTORY}/common/logging.shinc
fi

declare -g AWSECURE_CLI_AWS_BIN_FILEPATH=${AWSECURE_CLI_AWS_BIN_FILEPATH:-~/.asdf/shims/aws}

function awsecure_cli_get_aws_profile_set() {
  if grep -i '\-\-profile=' <<< "${@}" &> /dev/null; then
    local -r AWSECURE_CLI_AWS_PROFILE_SET="cli_equals"
  elif grep -i '\-\-profile ' <<< "${@}" &> /dev/null; then
    local -r AWSECURE_CLI_AWS_PROFILE_SET="cli_space"
  elif [[ ! -z ${AWS_PROFILE// /} ]]; then
    local -r AWSECURE_CLI_AWS_PROFILE_SET="var"
  fi

  case "${AWSECURE_CLI_AWS_PROFILE_SET// /}" in
  cli_space)
    echo "${@}" | tr ' ' '\n' | grep -A1 '\-\-profile' | tail -1
    ;;
  cli_equals)
    echo "${@}" | tr ' ' '\n' | grep '\-\-profile' | sed -E 's/.*profile=(.*)/\1/'
    ;;
  var)
    echo "${AWS_PROFILE}"
    ;;
  *)
    declare -rxg AWS_PROFILE="default"
    echo "${AWS_PROFILE}"
    ;;
  esac
}

awsecure_cli_log_info "Getting the AWS profile in use"
declare -rxg AWS_PROFILE="$(awsecure_cli_get_aws_profile_set "${@}")"
awsecure_cli_log_info "The AWS profile in use is the ${AWS_PROFILE}"

function awsecure_cli_autorotate_invoke() {
  local -l AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS="${AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS:-"true"}"
  case "${AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS// /}" in
  true)
    . ${AWSECURE_CLI_SRC_DIRECTORY}/common/autorotate_aws_keys.sh
    ;;
  *)
    awsecure_cli_log_info "The AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS is not set to true. Skiping the AWS Access Keys autorotation"
    ;;
  esac
}
awsecure_cli_autorotate_invoke

[[ -z "${AWSECURE_CLI_AUTOROTATE_ONLY// /}" || "${AWSECURE_CLI_AUTOROTATE_ONLY// /}" != "true" ]] && ${AWSECURE_CLI_AWS_BIN_FILEPATH} "${@}"
