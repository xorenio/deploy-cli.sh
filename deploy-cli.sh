#!/bin/bash

#######################################################################
# Server Deployment Script
#######################################################################
#
# This script is designed to management the deployment on a linux server.
# handling various configurations and checks based on environment
# variables and dependencies.
#
# Usage:
#   ./deploy-cli.sh <action>
#
# Authors:
#   - <John J> admin@xoren.io
#
# Links:
#   - https://github.com/xorenio/deploy-cli.sh
#
#######################################################################

# START - Script setup and configs

# Defaulting variables
NOWDATESTAMP=$(date "+%Y-%m-%d_%H-%M-%S")

# This script variables
SCRIPT_NAME=$(basename "$(test -L "$0" && readlink "$0" || echo "$0")" | sed 's/\.[^.]*$//')
SCRIPT=$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR_NAME="$(basename "$PWD")"
SCRIPT_DEBUG=false        # true AKA echo to console | false echo to log file
SCRIPT_CMD_ARG=("${@:1}") # Assign command line arguments to array
FUNCTION_ARG=("${@:2}")   # Assign command line arguments to array

# Terminal starting directory
STARTING_LOCATION="$(pwd)"
cd "$SCRIPT_DIR" || exit

# Deployment environment
DEPLOYMENT_ENV="production"

# Enable location targeted deployment
DEPLOYMENT_ENV_LOCATION=false

# Deployment location
ISOLOCATION="GB"    ## DEFAULT US
ISOSTATELOCATION="" ## DEFAULT EMPTY

# Git repo name
GIT_REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")

# if using GitHub, Github Details if not ignore
GITHUB_REPO_OWNER=$(git remote get-url origin | sed -n 's/.*github.com:\([^/]*\)\/.*/\1/p')
GITHUB_REPO_URL="https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GIT_REPO_NAME}/commits"

SCRIPT_LOG_FILE="${SCRIPT_DIR}/${SCRIPT_NAME}.log"
SCRIPT_LOG_EMAIL_FILE=${SCRIPT_LOG_EMAIL_FILE:-"$HOME/${SCRIPT_NAME}.mail.log"}
JSON_FILE_NAME="${SCRIPT_DIR}/${SCRIPT_NAME}_${NOWDATESTAMP}.json"
SCRIPT_RUNNING_FILE="$HOME/${GIT_REPO_NAME}_running.txt"

# Working Schedule
# This is referenced in the update check function and will exclude updating in given time frames, or false to disable
# Define a single string with time ranges, where ranges can be specified like 1-5:07:00-16:00
# Format: 1: Monday - 7: Sunday - day(s):start_time-end_time|...
# e.g., "1-5:07:00-16:00|6:09:00-15:00|7:09:00-15:00"
# WORKING_SCHEDULE="1-5:07:00-16:00|7:20:00-23:59"
WORKING_SCHEDULE=false

# END - Script setup and configs

# START - IMPORT FUNCTIONS
if [[ -f "${SCRIPT_DIR}/.${SCRIPT_NAME}/_functions.sh" ]]; then
    # shellcheck source=.deploy-cli/_functions.sh
    source "${SCRIPT_DIR}/.${SCRIPT_NAME}/_functions.sh"
else
    echo "[ERROR] Missing _functions.sh"
    exit
fi

# END - IMPORT FUNCTIONS

# START - SCRIPT PRE-CONFIGURE

## SET LOGGING TO TTY OR TO deployment.log
if [[ "$(_interactive_shell)" = "1" ]]; then
    if [ "$APT_IS_PRESENT" ]; then
        export DEBIAN_FRONTEND=noninteractive
    fi
    SCRIPT_DEBUG=false
else
    SCRIPT_DEBUG=true
fi

if [[ "$DEBIAN_FRONTEND" != "noninteractive" ]]; then
    if [[ "$(_is_present curl)" != "1" ]]; then
        _log_error "Please install curl."
        exit
    fi

    if [[ "$(_is_present jq)" != "1" ]]; then
        _log_error "Please install jq."
        exit
    fi
fi

# if [[ "$DEPLOYMENT_ENV_LOCATION" = "true" && "$(_is_present whois)" != "1" ]]; then
#     _log_error "Please install whois."
#     exit
# fi

## CHECK IF SCRIPT IS ALREADY RUNNING
_check_running_file

## CHECK IF BACKGROUND TASKS ARE STILL RUNNING
# if [[ $SCREEN_IS_PRESENT == true ]]; then

# _log_info "Script screen check."
# if screen -list | grep -q "${SCRIPT_DIR_NAME}_deployment"; then
#     _log_error "${SCRIPT_DIR_NAME}_deployment screen still running."
#     exit;
# fi
# fi

## ECHO STARTTIME TO DEPLOYMENT LOG FILE
_create_running_file

## CHECK FOR PROJECT VAR FILE
if [[ "$DEBIAN_FRONTEND" != "noninteractive" ]]; then
    _check_project_secrets
fi
## SET DEPLOY ENV VAR TO LOCATION
if [[ "$DEPLOYMENT_ENV_LOCATION" = "true" ]]; then
    _set_location_var
    DEPLOYMENT_ENV="$ISOLOCATION"
fi

## CHECK .env FILE
if [[ ! -f "$HOME"/"${GIT_REPO_NAME}"/.env ]]; then

    cp "$HOME"/"${GIT_REPO_NAME}"/.env."${DEPLOYMENT_ENV}" "$HOME"/"${GIT_REPO_NAME}"/.env
fi

## LOAD .env VARS
# shellcheck disable=SC1090
source "$HOME"/"${GIT_REPO_NAME}"/.env

## SECRETS
_load_project_secrets

# END - SCRIPT PRE-CONFIGURE

__display_info() {
    cat <<EOF
USAGE: ${SCRIPT} [option]

Options:

setup                                       Setup steps and update cron.

version:check                               Check deployment for updates.
version:info                                Print version of this repo.
version:update                              Manually start an update.

replace:env                                 Replace env file vars from secrets.

write:secrets                               Create secrets file outside of repo.
write:token:github                          To setup the local GitHub token.
write:token:onedev                          To setup the local Onedev token.
EOF
}

# START - SCRIPT RUNTIME

## Command line argument
if [[ ${#SCRIPT_CMD_ARG} -ge 1 ]]; then
    case "${SCRIPT_CMD_ARG[0]}" in
    "setup")
        _setup
        ;;
    "install:linux")
        _install_linux_dep
        ;;

    "version:check" | "v:check" | "check")
        LATEST_PROJECT_SHA="$(_set_latest_sha true)"

        _log_info "Local version: $DEPLOYMENT_VERSION"
        _log_info "Remote version: $LATEST_PROJECT_SHA"
        _check_update
        ;;
    "version:info" | "v:info" | "info")
        LATEST_PROJECT_SHA="$(_set_latest_sha true)"

        _log_info "Local version: $DEPLOYMENT_VERSION"
        _log_info "Remote version: $LATEST_PROJECT_SHA"
        ;;
    "version:update" | "v:update" | "update")
        _set_latest_sha
        # _log_info ""
        # _log_info "======================="
        # _log_info "\/ Manual re-install \/"
        # _log_info "======================="
        _update "${FUNCTION_ARG[@]}"
        ;;
    "replace:env")
        _replace_env_project_secrets
        ;;
    "write:secrets" | "w:secrets")
        _write_secrets_file
        ;;
    "write:token:github" | "w:token:github")
        if [[ ${#SCRIPT_CMD_ARG} -ge 2 ]]; then
            _write_github_token "${FUNCTION_ARG[@]}"
        else
            _write_github_token
        fi
        ;;
    "write:token:onedev" | "w:token:onedev")
        if [[ ${#SCRIPT_CMD_ARG} -ge 2 ]]; then
            _write_onedev_token "${FUNCTION_ARG[@]}"
        else
            _write_onedev_token
        fi
        ;;
    *)
        __display_info
        ;;
    esac
else
    if [[ "$(_interactive_shell)" = "0" ]]; then
        _log_error "Headless mode not setup."
    else
        __display_info
    fi
fi

_delete_running_file

# END - SCRIPT RUNTIME
