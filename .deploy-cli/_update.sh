#!/bin/bash

# Author: admin@xoren.io
# Script: _update.sh
# Link https://github.com/xorenio/deploy-cli.sh
# Description: Functions script.

# Script variables
NOWDATESTAMP="${NOWDATESTAMP:-$(date "+%Y-%m-%d_%H-%M-%S")}"

SCRIPT="${SCRIPT:-$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")}"
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
SCRIPT_DIR_NAME="${SCRIPT_DIR_NAME:-$(basename "$PWD")}"
SCRIPT_DEBUG=${SCRIPT_DEBUG:-false}

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

# START - IMPORT FUNCTIONS
if [[ ! -n "$(type -t _registered)" ]]; then
    if [[ -f "${SCRIPT_DIR}/.${SCRIPT_NAME}/_functions.sh" ]]; then
        # shellcheck source=_functions.sh
        source "${SCRIPT_DIR}/.${SCRIPT_NAME}/_functions.sh"
    fi
fi
# END - IMPORT FUNCTIONS

# Function: __overwrite_nginx_configurations
# Description: Private function to overwrite nginx sites, configs & snippets.
# Parameters: None
# Returns: None

__do_something() {
    echo "Did something"
}

# Function: _pre_update
# Description: Performs pre git download actions.
# Parameters: None
# Returns: None

_pre_update() {
    ## Ensure things for deployment

}

# Function: _post_update
# Description: Performs action git download.
# Parameters: None
# Returns: None

_post_update() {

    ## Ensure things for deployment

    if [[ ! -f "$HOME/${GIT_REPO_NAME}/.env" ]]; then
        cp "$HOME/${GIT_REPO_NAME}/.env.production" "$HOME/${GIT_REPO_NAME}/.env"
    fi

    sync

    # Clean-up
    _delete_old_project_files
}
