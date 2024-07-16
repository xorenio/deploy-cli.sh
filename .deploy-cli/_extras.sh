#!/bin/bash

# This script variables
SCRIPT_NAME="${SCRIPT_NAME:-$(basename "$(test -L "$0" && readlink "$0" || echo "$0")" | sed 's/\.[^.]*$//')}"
SCRIPT="${SCRIPT:-$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")}"
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
SCRIPT_DIR_NAME="${SCRIPT_DIR_NAME:-$(basename "$PWD")}"
SCRIPT_DEBUG=${SCRIPT_DEBUG:-false}

# Terminal starting directory
STARTING_LOCATION=${STARTING_LOCATION:-"$(pwd)"}

# Deployment environment
DEPLOYMENT_ENV=${DEPLOYMENT_ENV:-"production"}

# Enable location targeted deployment
DEPLOYMENT_ENV_LOCATION=${DEPLOYMENT_ENV_LOCATION:-false}

# Deployment location
ISOLOCATION=${ISOLOCATION:-"GB"}
ISOSTATELOCATION=${ISOSTATELOCATION:-""}

# Git repo name
GIT_REPO_NAME="${GIT_REPO_NAME:-$(basename "$(git rev-parse --show-toplevel)")}"

# if using GitHub, Github Details if not ignore
GITHUB_REPO_OWNER="${GITHUB_REPO_OWNER:-$(git remote get-url origin | sed -n 's/.*github.com:\([^/]*\)\/.*/\1/p')}"
GITHUB_REPO_URL="${GITHUB_REPO_URL:-"https://api.github.com/repos/$GITHUB_REPO_OWNER/$GIT_REPO_NAME/commits"}"

SCRIPT_LOG_FILE=${SCRIPT_LOG_FILE:-"${SCRIPT_DIR}/${SCRIPT_NAME}.log"}
SCRIPT_LOG_EMAIL_FILE=${SCRIPT_LOG_EMAIL_FILE:-"$HOME/${SCRIPT_NAME}.mail.log"}
JSON_FILE_NAME=${JSON_FILE_NAME:-"${SCRIPT_DIR}/${SCRIPT_NAME}_${NOWDATESTAMP}.json"}
SCRIPT_RUNNING_FILE=${SCRIPT_RUNNING_FILE:-"${HOME}/${GIT_REPO_NAME}_running.txt"}

LATEST_PROJECT_SHA=${LATEST_PROJECT_SHA:-0}

# START - IMPORT FUNCTIONS
if [[ ! -n "$(type -t _registered)" ]]; then
    if [[ -f "${SCRIPT_DIR}/.${SCRIPT_NAME}/_functions.sh" ]]; then
        # shellcheck source=_functions.sh
        source "${SCRIPT_DIR}/.${SCRIPT_NAME}/_functions.sh"
    fi
fi
# END - IMPORT FUNCTIONS
