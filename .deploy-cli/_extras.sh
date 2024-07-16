#!/bin/bash

# Author: admin@xoren.io
# Script: _extras.sh
# Link https://github.com/xorenio/deploy-cli.sh
# Description: Functions script.

# Script variables
NOWDATESTAMP="${NOWDATESTAMP:-$(date "+%Y-%m-%d_%H-%M-%S")}"

SCRIPT_NAME="${SCRIPT_NAME:-$(basename "$(test -L "$0" && readlink "$0" || echo "$0")" | sed 's/\.[^.]*$//')}"
SCRIPT="${SCRIPT:-$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")}"
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
SCRIPT_DIR_NAME="${SCRIPT_DIR_NAME:-$(basename "$PWD")}"
SCRIPT_DEBUG=${SCRIPT_DEBUG:-false}

# Commandline arguments.
SCRIPT_CMD_ARG=${SCRIPT_CMD_ARG:-("${@:1}")}
FUNCTION_ARG=${FUNCTION_ARG:-("${@:2}")}

# Deployment environment
DEPLOYMENT_ENV=${DEPLOYMENT_ENV:-"production"}

# Git repo name
GIT_REPO_NAME="${GIT_REPO_NAME:-$(basename "$(git rev-parse --show-toplevel)")}"

# START - IMPORT FUNCTIONS
if [[ ! -n "$(type -t _registered)" ]]; then
    if [[ -f "${SCRIPT_DIR}/.${SCRIPT_NAME}/_functions.sh" ]]; then
        # shellcheck source=_functions.sh
        source "${SCRIPT_DIR}/.${SCRIPT_NAME}/_functions.sh"
    fi
fi
# END - IMPORT FUNCTIONS

# Function: _registered_extras
# Description: function to registered this file as imported as to not reimport this file.
# Parameters: None
# Returns: 0

_registered_extras() {
    return 0
}

# Function: __extras_options
# Description: function to manage extra script actions.
# Parameters: None
# Returns: 0

__extras_options() {
    local SCRIPT_CMD_ARG="$1"
    case "${SCRIPT_CMD_ARG[0]}" in
    "user:create")
        _create_user "${FUNCTION_ARG[@]}"
        _exit_script
        ;;
    "user:remove")
        _remove_user "${FUNCTION_ARG[@]}"
        _exit_script
        ;;
    esac
}

# Function: __display_info_extras
# Description: function to display extra actions info.
# Parameters: None
# Returns: 0

__display_info_extras() {
    cat <<EOF
user:create                                 Synchronised create user on cluster.
user:remove                                 Synchronised remove user on cluster.

EOF
}

# Function: _create_user
# Description: function to create/ensure a user on all VMs is cluster.
# Parameters: None
# Returns:

_create_user() {
    _log_info "Disabled atm, not seeting up user $1"
    return
}

# Function: _remove_user
# Description: function to remove a user on all VMs is cluster.
# Parameters: None
# Returns:

_remove_user() {
    _log_info "Remove user hasn't been setup, not seeting up user $1"
    return
}
