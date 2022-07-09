#!/usr/bin/env bash

set -eo pipefail

function awsecure_cli_validate_commands() {
  local -rl AWSECURE_CLI_VALIDATE_COMMANDS="jq ${AWSECURE_CLI_AWS_BIN_FILEPATH} ${AWSECURE_CLI_SH_INTERPRETER}"
  for cmd in ${AWSECURE_CLI_VALIDATE_COMMANDS}; do
    awsecure_cli_log_info "Testing if ${cmd} is installed"
    ${cmd} --version &> /dev/null || awsecure_cli_log_error "The ${cmd} is not installed or not in the PATH environment variable"
  done
}

case "${AWSECURE_CLI_OS_NAME// /}" in
darwin)
  true
  ;;
linux)
  true
  ;;
*)
  awsecure_cli_log_error "OS not supported"
  ;;
esac

awsecure_cli_validate_commands

set +eo pipefail
${AWSECURE_CLI_AWS_BIN_FILEPATH} configure get aws_access_key_id > /dev/null 2>&1
[[ $? -ne 0 ]] && { awsecure_cli_log_info "The profile ${AWS_PROFILE} is not using an AWS access key, skipping AWS access key rotation" ; SKIP_AWSECURE_CLI_AUTOROTATE_AWS_ACCESS_KEYS=true ; }
set -eo pipefail
