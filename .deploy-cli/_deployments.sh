#!/bin/bash

# Author: admin@xoren.io
# Script: _deployments.sh
# Link https://github.com/xorenio/deploy-cli.sh
# Description: Functions script.

# Script variables
NOWDATESTAMP="${NOWDATESTAMP:-$(date "+%Y-%m-%d_%H-%M-%S")}"

SCRIPT_NAME="${SCRIPT_NAME:-$(basename "$(test -L "$0" && readlink "$0" || echo "$0")" | sed 's/\.[^.]*$//')}"
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

_registered_deployments() {
    # This is used for checking is _function.sh has been imported or not
    return 0
}

# Function: _calculate_folder_size
# Description: Function to calculate the size of a folder excluding specific directories.
# Parameters: None
# Returns: None

_calculate_folder_size() {
    local folder=$1
    local exclude_dirs=(".git" "laravel/node_modules" "laravel/vendor")
    local exclude_opts=""

    for dir in "${exclude_dirs[@]}"; do
        exclude_opts+="--exclude='${folder}'/'${dir}' "
    done

    du -s --exclude='.*/' "$exclude_opts" "$folder" | awk '{print $1}'
}

# Function: _delete_old_project_files
# Description: Deletes old project files.
# Parameters: None
# Returns: None

_delete_old_project_files() {

    [[ ! -d "$HOME/${GIT_REPO_NAME}_${NOWDATESTAMP}" ]] && return
    local old_size new_size size_difference

    # Compare the size of the old and new project folders
    old_size=$(_calculate_folder_size "$HOME/${GIT_REPO_NAME}")
    new_size=$(_calculate_folder_size "$HOME/${GIT_REPO_NAME}_${NOWDATESTAMP}")
    size_difference=$(echo "scale=2; ($old_size - $new_size) / $old_size * 100" | bc)

    # Check if the old project folder is within 80% of the size of the new project
    if (($(echo "$size_difference <= 80" | bc -l))); then
        _log_info "Deleted: $HOME/${GIT_REPO_NAME}_${NOWDATESTAMP}"
        yes | rm -rf "$HOME/${GIT_REPO_NAME}_${NOWDATESTAMP}"
    else
        _log_info "NOT Deleted: $HOME/${GIT_REPO_NAME}_${NOWDATESTAMP}"
    fi
}

# START - PROJECT FUNCTIONS

# Function: _check_project_secrets
# Description: Checks if the secrets file exists and prompts user to create it if it doesn't exist.
# Parameters: None
# Returns: None

_check_project_secrets() {
    # If no secrets file
    if [[ ! -f "$HOME/.${GIT_REPO_NAME}" ]]; then

        # Log the missing file
        _log_error ""
        _log_error "Failed deployment ${NOWDATESTAMP}"
        _log_error ""
        _log_error "Missing twisted var file $HOME/.${GIT_REPO_NAME}"

        # If script ran from tty
        if [[ "$(_interactive_shell)" = "1" ]]; then
            # Ask user if they want to write secret file
            read -rp "Write secrets file? [Y/n] (empty: no): " write_file
            if [[ $write_file =~ ^(YES|Yes|yes|Y|y)$ ]]; then
                _write_project_secrets
            fi
        fi
        # Exit script
        _exit_script
    fi
}

# Function: _load_project_secrets
# Description: Checks if the secrets file exists and load it.
# Parameters: None
# Returns: None

_load_project_secrets() {
    # shellcheck disable=SC1090
    [[ -f "$HOME/.${GIT_REPO_NAME}" ]] && source "$HOME/.${GIT_REPO_NAME}" ##|| echo 0
}

# Function: _write_project_secrets
# Description: Writes environment variables to a file in the user's home directory.
# Parameters: None
# Returns: None

_write_project_secrets() {

    cat >"$HOME/.${GIT_REPO_NAME}" <<EOF
# Deployment
DEPLOYMENT_ENV=production
DEPLOYMENT_TIMEZONE=Europe/London
DEPLOYMENT_ENCODE=en_GB
APP_ENV=production
APP_DEBUG=false
APP_ENCODE=en_GB
APP_USER_UUID=$UID
APP_USER_GUID=$(id -g)
APP_USER=$(whoami)
APP_TIMEZONE=Europe/London
APP_ENCODE=en_GB
APP_LANG=en_GB.UTF-8
ENABLED_LETSENCRYPT=true
MAIL_MAILER=log
MAIL_HOST=outbound.mailhop.org
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="hello@example.com"
MAIL_FROM_NAME="Node 0"
MAIL_TO_ADDRESS="me@domains.com"
EOF
    chmod 700 "$HOME"/."${GIT_REPO_NAME}"
    _log_info "Writen env vars file $HOME/.${GIT_REPO_NAME}"
}

# Function: _ensure_project_secrets_file
# Description: Check if secrets file doesn't exists and.
# Parameters: None
# Returns: None

_ensure_project_secrets_file() {
    # Check if secrets file doesn't exists and
    if [[ ! -f "$HOME/.${GIT_REPO_NAME}" ]]; then
        # Call function to help create it
        _write_project_secrets
    fi
}

# Function: _replace_env_project_secrets
# Description: Replaces the environment variables in the configuration file with their corresponding values.
# Parameters: None
# Returns: None

_replace_env_project_secrets() {

    _check_latest_sha
    # LATEST_PROJECT_SHA="$(_check_latest_sha true)"

    _log_info "Replacing APP environment variables"

    # Check if secrets file doesn't exists and
    _ensure_project_secrets_file

    # Remove window line endings
    sed -i 's/\r//g' "$HOME/.${GIT_REPO_NAME}"

    if [ -f "$HOME/${GIT_REPO_NAME}/.env.${DEPLOYMENT_ENV}" ]; then
        sed -i 's/\r//g' "$HOME/${GIT_REPO_NAME}/.env.${DEPLOYMENT_ENV}"
    fi

    # Copy the deployment version of .env file
    [[ ! -f "$HOME/${GIT_REPO_NAME}/.env" ]] && cp "$HOME/${GIT_REPO_NAME}/.env.${DEPLOYMENT_ENV}" "$HOME/${GIT_REPO_NAME}/.env"

    # Call sync for .env inode
    sync "$HOME/${GIT_REPO_NAME}/.env"

    # Make it excusable
    chmod 700 "$HOME/${GIT_REPO_NAME}/.env"

    # Call sync for .env inode
    local first_letter sec_name sec_value

    # Read line by line secrets file
    while read -r CONFIGLINE; do
        # Get the first letter of line
        first_letter=${CONFIGLINE:0:1}

        # Check first letter isnt a space or # and line length is greater then 3
        if [[ $first_letter != " " && $first_letter != "#" && ${#CONFIGLINE} -gt 3 ]]; then

            # Check for "=" in line
            if echo "$CONFIGLINE" | grep -F = &>/dev/null; then

                # Get the variable name
                sec_name="$(echo "$CONFIGLINE" | cut -d '=' -f 1)"

                # Get the variable value
                sec_value="$(echo "$CONFIGLINE" | cut -d '=' -f 2-)"

                # While loop grep .env file to replace all found configs
                while [[ "$(grep -oF "\"<$sec_name>\"" "$HOME/${GIT_REPO_NAME}/.env")" = "\"<$sec_name>\"" ]]; do
                    if sed -i 's|"<'"$sec_name"'>"|'"$sec_value"'|' "$HOME/${GIT_REPO_NAME}/.env"; then
                        # This because it seems, if we act to soon it doesn't write.
                        sync "$HOME/${GIT_REPO_NAME}/.env"
                        # Sleep for 1 second
                        sleep 0.2
                    fi
                done
            fi
        fi
    done <"$HOME/.${GIT_REPO_NAME}"

    # Replace deployment variables
    while grep -F "\"<DEPLOYMENT_VERSION>\"" "$HOME/${GIT_REPO_NAME}/.env" &>/dev/null; do
        sed -i "s|\"<DEPLOYMENT_VERSION>\"|$LATEST_PROJECT_SHA|" "$HOME/${GIT_REPO_NAME}/.env"
        sync "$HOME/${GIT_REPO_NAME}/.env"
        sleep 0.2s
    done
    sed -i "s|\"<DEPLOYMENT_AT>\"|$NOWDATESTAMP|" "$HOME/${GIT_REPO_NAME}/.env"

    # Call sync on .env file for inode changes
    sync "$HOME/${GIT_REPO_NAME}/.env"

    # _log_info "END: Replacing APP environment variables"
}

# Function: _get_project_docker_compose_file
# Description: Locates projects docker compose file.
# Parameters: None
# Returns:
#   0 if failed to locate docker-compose yml file
#   File path to project docker compose file

_get_project_docker_compose_file() {
    local docker_compose_file="0"

    # Check if docker-compose is installed
    if [[ "$(_is_present docker-compose)" = "1" ]]; then

        # Check for the default docker-compose yml file
        if [[ -f "$HOME/${GIT_REPO_NAME}/docker-compose.yml" ]]; then
            docker_compose_file="$HOME/${GIT_REPO_NAME}/docker-compose.yml"
        fi
        # Check for docker compose file with deployment environment tag
        if [[ -f "$HOME/${GIT_REPO_NAME}/docker-compose.${DEPLOYMENT_ENV}.yml" ]]; then
            docker_compose_file="$HOME/${GIT_REPO_NAME}/docker-compose.${DEPLOYMENT_ENV}.yml"
        fi
    fi

    # Return results
    echo "${docker_compose_file}"
}

# END - PROJECT FUNCTIONS

# START - GIT SERVICES

# Function: _git_service_provider
# Description: Returns git service providers domain.
# Parameters: None
# Returns: None

_git_service_provider() {
    # shellcheck disable=SC2164
    cd "$HOME"/"${GIT_REPO_NAME}"
    local git_domain

    git_domain=$(git remote get-url origin | awk -F'@|:' '{gsub("//", "", $2); print $2}')
    echo "$git_domain"
}

# END - GIT SERVICES

# START - GITHUB TOKEN

# Function: _check_github_token
# Description: Check $GITHUB_TOKEN variable has been set and matches the github personal token pattern.
# Parameters: None
# Returns:
#   1 if successfully loaded github token and matches pattern

_check_github_token() {
    local pattern="^ghp_[a-zA-Z0-9]{36}$"
    [[ ${GITHUB_TOKEN:-"ghp_##"} =~ $pattern ]] && echo 1
}

# Function: _check_github_token_file
# Description: Check the location for the github token file.
# Parameters: None
# Returns:
#   1 if github token file exists, otherwise 0.

_check_github_token_file() {
    [[ -f "$HOME/.github_token" ]] && echo 1
}

# Function: _load_github_token
# Description: If github token already has been loaded or check and loads from file then validate.
# Parameters: None
# Returns:
#   1 if github token already loaded or loads token from file and matches pattern, otherwise 0.

_load_github_token() {
    # Call _check_github_token to vildate current token variable.
    if [[ $(_check_github_token) = "1" ]]; then
        return
    fi

    # Call function to check for token file
    if [[ "$(_check_github_token_file)" = "1" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.github_token" || echo "Failed import of github_token"
    fi
}

# Function: _write_github_token
# Description: Given a gh token or from user prompt, validate and creates .github_token file.
# Parameters:
#   $1: optional github token
# Returns:
#   1 if successfully installed github token.

#shellcheck disable=SC2120
_write_github_token() {
    local pattern="^ghp_[a-zA-Z0-9]{36}$"
    local token

    # If function has param
    if [[ $# -ge 1 ]]; then
        # Use the param $1 as token
        token=$1
    elif [[ "$(_interactive_shell)" = "1" ]]; then # If run from tty

        # Create user interaction to get token from user.
        read -rp "Please provide Github personal access token (empty: cancel): " input_token

        token="$input_token"

        # Check user input token against pattern above.
        if [[ ! $token =~ $pattern ]]; then
            # Log error and exit script
            # _log_error "Missing github token file .github_token"
            _log_error "GITHUB_TOKEN=ghp_azAZ09azAZ09azAZ09azAZ09azAZ09azAZ09"
            _log_error "public_repo, read:packages, repo:status, repo_deployment"
            _log_error "Invalid github personal access token."
            _exit_script
        fi
    fi

    # If give token matches pattern
    if [[ $token =~ $pattern ]]; then
        # Create github token file
        echo "#" >"$HOME"/.github_token
        echo "GITHUB_TOKEN=$token" >>"$HOME"/.github_token
        echo "" >>"$HOME"/.github_token
        chmod 700 "$HOME"/.github_token
        # Load github token
        _load_github_token
        # Return success
        echo 1
    else
        # Log error and exit script
        _log_error "Invalid github personal access token."
        _exit_script
    fi
}

# END - GITHUB TOKEN

# START - GITHUB API

# Function: _get_project_github_latest_sha
# Description: Gets project files latest git commit sha from github.
# Parameters: None
# Returns:
#   0 - if failed to get latest git commit sha
#   github commit sha

_get_project_github_latest_sha() {

    # Load the github token if not loaded
    _load_github_token

    # Validate loaded token
    if [[ "$(_check_github_token)" = "0" ]]; then
        # On fail ask user to create token
        _write_github_token
    fi

    # Create local function variable
    local curl_data gh_sha

    # Send request to github with creds
    curl_data=$(curl -s -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version:2022-11-28" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        "$GITHUB_REPO_URL")

    # Check returned data from request
    if [[ $(echo "$curl_data" | jq -r .message 2>/dev/null && echo 1) ]]; then
        # Log error and return fail from function
        _log_to_file "$(echo "$curl_data" | jq .message)"
        echo 0
        return
    fi

    # Validate commit sha and return.
    if [[ $(echo "$curl_data" | jq -r .[0].commit.tree.sha 2>/dev/null && echo 1) ]]; then
        gh_sha="$(echo "$curl_data" | jq .[0].commit.tree.sha)"
        echo "${gh_sha//\"/}"
        return
    fi

    # Return fail code.
    echo 0
}

# END - GITHUB API

# START - ONEDEV TOKEN

# Function: _check_onedev_token
# Description: Check $GITHUB_TOKEN variable has been set and matches the onedev personal token pattern.
# Parameters: None
# Returns:
#   1 if successfully loaded github token and matches pattern

_check_onedev_token() {
    local pattern="^[A-Za-z0-9]+$"
    [[ ${ONEDEV_TOKEN:-"######"} =~ $pattern ]] && echo 1
}

# Function: _check_onedev_file
# Description: Check the location for the onedev token file.
# Parameters: None
# Returns:
#   1 if github token file exists, otherwise 0.

_check_onedev_file() {
    [[ -f "$HOME/.onedev_auth" ]] && echo 1
}

# Function: _load_onedev_token
# Description: If onedev token already has been loaded or check and loads from file then validate.
# Parameters: None
# Returns:
#   1 if github token already loaded or loads token from file and matches pattern, otherwise 0.

_load_onedev_token() {
    if [[ $(_check_onedev_token) = "1" ]]; then
        return
    fi

    if [[ "$(_check_onedev_file)" = "1" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.onedev_auth" || echo "Failed import of onedev_auth"
    fi
}

# Function: _write_onedev_token
# Description: Given a onedev token or from user prompt, validate and creates .onedev_token file.
# Parameters:
#   $1: optional github token
# Returns:
#   1 if successfully installed github token.

# shellcheck disable=SC2120
_write_onedev_token() {
    # Set local function variables
    local pattern="^[A-Za-z0-9]+$"
    local token username

    # If function has been given 1 argument
    if [[ $# -ge 1 ]]; then
        # Use the param $1 as token
        token=$1
    elif [[ "$(_interactive_shell)" = "1" ]]; then # If run from tty

        # Create user interaction to get token from user.
        read -rp "Please provide OneDev Access Token (empty: cancel): " input_token

        token="$input_token"

        # Check user input token against pattern above.
        if [[ ! $token =~ $pattern ]]; then
            # Log error and exit script
            # _log_error "Missing github token file .onedev_auth"
            _log_error "ONEDEV_TOKEN=########"
            _log_error "ONEDEV_USERNAME=######"
            _exit_script
        fi
    fi

    # If give token matches pattern
    if [[ $token =~ $pattern ]]; then

        # Write token file
        echo "#" >"$HOME"/.onedev_auth
        echo "ONEDEV_TOKEN=$token" >>"$HOME"/.onedev_auth

        # If function has been given 2 arguments
        if [[ $# -ge 2 ]]; then
            username="$2"
        else
            # Create user interaction to get username from user.
            read -rp "Please provide OneDev Username (empty: cancel): " input_username
            username="$input_username"
        fi

        # Add username variable to token file
        echo "ONEDEV_USERNAME=$username" >>"$HOME"/.onedev_auth

        echo "" >>"$HOME"/.onedev_auth
        chmod 700 "$HOME"/.onedev_auth

        # Load token from newly create token file
        _load_onedev_token
        echo 1
    else
        # Log error and exit script
        _log_error "Invalid github personal access token."
        _exit_script
    fi
}

# END - GITHUB TOKEN

# START - ONEDEV API

# Function: _get_project_onedev_latest_sha
# Description: Gets project files latest git commit sha from onedev.
# Parameters: None
# Returns:
#   0 - if failed to get latest git commit sha
#   github commit sha

_get_project_onedev_latest_sha() {
    # Call function to load token if not loaded
    _load_onedev_token

    # Run check on token variable
    if [[ "$(_check_onedev_token)" != "1" ]]; then
        # Ask user to full missing token
        _write_onedev_token
    fi

    # Set local function variables
    local curl_data project_id onedev_sha

    cd "$HOME"/"${GIT_REPO_NAME}" || _exit_script
    local git_domain git_url

    # Calling _git_service_provider function to check git provider from .git data
    git_url=$(git remote get-url origin)
    git_domain="$(_git_service_provider)"

    # URL to process
    local query='query="Name" is "'${GIT_REPO_NAME}'"'

    cleaned_url="${git_url#*://}"                  # Remove "http://" or "https://"
    cleaned_url="${cleaned_url#*/*}"               # Remove "git.xoren.io:6611/"
    cleaned_url="${cleaned_url/\/$GIT_REPO_NAME/}" # Remove "git.xoren.io"

    if [[ ${#cleaned_url} -ge 1 ]]; then
        query+=' and children of "'${cleaned_url}'"'
    fi
    ## Enable for debugging.
    # _log_to_file "query: $query"

    # Send request to git api to get id of repo
    curl_data=$(curl -s -u "${ONEDEV_USERNAME}:${ONEDEV_TOKEN}" \
        -G https://git.xoren.io/~api/projects \
        --data-urlencode "${query}" \
        --data-urlencode offset=0 --data-urlencode count=100)

    # Check request returning data
    if [[ ! $(echo "$curl_data" | jq .[0].id 2>/dev/null && echo 1) ]]; then
        # Error in api response, log and return fail from this function.
        _log_to_file "Cant find project id from git api"
        echo 0
        return
    fi

    # Set if from request data
    project_id="$(echo "$curl_data" | jq .[0].id)"

    # Send request to git repo api for commit data
    curl_data=$(curl -s -u "${ONEDEV_USERNAME}:${ONEDEV_TOKEN}" \
        -G "https://git.xoren.io/~api/repositories/${project_id}/commits" \
        --data-urlencode count=1)

    # Check request returning data
    if [[ $(echo "$curl_data" | jq -r .[0] 2>/dev/null && echo 1) ]]; then

        # On success echo back sha
        onedev_sha="$(echo "$curl_data" | jq .[0])"
        echo "${onedev_sha//\"/}"
        return
    fi

    # Return error code if failed above check.
    echo 0
}

# END - ONEDEV API

# START - UPDATE FUNCTIONS

# Function: _check_latest_sha
# Description: Sets LATEST_PROJECT_SHA via _set_latest_sha function, if LATEST_PROJECT_SHA not already set.
# Parameters: None
# Returns: None

_check_latest_sha() {
    local sha_length

    # Check if LATEST_PROJECT_SHA isn't set
    if [[ -z "${LATEST_PROJECT_SHA}" ]]; then
        # Call function to set LATEST_PROJECT_SHA
        LATEST_PROJECT_SHA="$(_set_latest_sha true)"
    else
        # If LATEST_PROJECT_SHA is set check length
        sha_length=${#LATEST_PROJECT_SHA}
        if ((sha_length <= 31)); then
            # If LATEST_PROJECT_SHA length is smaller then 32
            LATEST_PROJECT_SHA="$(_set_latest_sha true)"
        fi
    fi
}

# Function: _set_latest_sha
# Description: Checks git repo provider and gets sha from provider api.
# Parameters: None
#   $1: (optional) echo SHA
# Returns: None
#    SHA: if

_set_latest_sha() {
    cd "$HOME"/"${GIT_REPO_NAME}" || _exit_script
    local git_domain

    # Calling _git_service_provider function to check git provider from .git data
    git_domain="$(_git_service_provider)"

    # Check git provider host again known list
    if echo "$git_domain" | grep -q github.com; then
        # Set LATEST_PROJECT_SHA from github api function
        LATEST_PROJECT_SHA="$(_get_project_github_latest_sha)"
        if [[ $# -ge 1 ]]; then
            echo "$LATEST_PROJECT_SHA"
        fi
        return
    elif [[ "$git_domain" = "git.xoren.io" ]]; then
        # Set LATEST_PROJECT_SHA from onedev api function
        LATEST_PROJECT_SHA="$(_get_project_onedev_latest_sha)"
        if [[ $# -ge 1 ]]; then
            echo "$LATEST_PROJECT_SHA"
        fi
        return
    else
        if [[ $# -ge 1 ]]; then
            echo 0
            return
        fi
        # Unknown or no provider
        _log_error "Cant find git host."
        _exit_script
    fi
}

# Function: _check_update
# Description: Checks if the local version matches the remote version of the repository.
# If the versions match, the script will exit.
# If the versions do not match, the script will perform an update and update the local version.
# Parameters: None
# Returns: None

_check_update() {

    if [[ "$(_check_working_schedule)" = "1" ]]; then
        _exit_script
    fi

    # Call function to set if not set latest project sha.
    _check_latest_sha
    # LATEST_PROJECT_SHA="$(_check_latest_sha true)"

    # If LATEST_PROJECT_SHA equals 0.
    if [[ "${LATEST_PROJECT_SHA}" = "0" ]]; then
        # Log error and exit scripts
        _log_error "Failed to fetching SHA from git api service"
        _exit_script
    fi
    # If LATEST_PROJECT_SHA is blank.
    if [[ "${LATEST_PROJECT_SHA}" = "" ]]; then
        # Log error and exit scripts
        _log_error "Failed to fetching SHA from git api service"
        _exit_script
    fi

    # Check for default value.
    if [[ "${DEPLOYMENT_VERSION}" = "<DEPLOYMENT_VERSION>" ]]; then

        # Replace with requested data version.
        _log_error "Current version <DEPLOYMENT_VERSION> AKA deployment failure somewhere"
        _update
    elif [[ "${DEPLOYMENT_VERSION}" = "DEV" ]]; then

        _log_error "Updating is disabled in development"
    else

        # If local version and remote version match.
        if [[ "${DEPLOYMENT_VERSION}" = "${LATEST_PROJECT_SHA}" ]]; then

            if [[ "$(_interactive_shell)" = "1" ]]; then
                _log_info "VERSION MATCH, ending script"
            fi
            _exit_script
        fi

        # Finally run the update function
        _update
    fi
}

# Function: _update
# Description: Performs re-deployment of the project by cloning a fresh copy from GitHub and updating project files.
#              It also moves the old project folder to a backup location.
#              The function replaces environment variables and propagates the environment file.
# Parameters: None
# Returns: None

# shellcheck disable=SC2120
_update() {
    local sha
    sha="$1"

    # Set local variable.
    local docker_compose_file="0"

    cd "$HOME/$GIT_REPO_NAME" || _exit_script

    # Set local variable using _get_project_docker_compose_file function
    docker_compose_file="$(_get_project_docker_compose_file)"

    # Check for _update.sh script to overwrite or provide update functions
    # if [[ -f "$HOME/${GIT_REPO_NAME}/_update.sh" ]]; then
    # shellcheck disable=SC1090
    # source "$HOME/${GIT_REPO_NAME}/_update.sh"
    # fi

    if [[ -f "${SCRIPT_DIR}/.${SCRIPT_NAME}/_update.sh" ]]; then
        # shellcheck source=_update.sh
        source "${SCRIPT_DIR}/.${SCRIPT_NAME}/_update.sh"
    fi
    # Log the re-deployment
    _log_to_file "Re-deployment Started"
    _log_to_file "====================="
    _log_to_file "env: ${DEPLOYMENT_ENV}"

    # Enter project repo
    cd "$HOME/$GIT_REPO_NAME" || _exit_script

    # Check if the function is set
    if [[ -n "$(type -t _pre_update)" ]]; then
        _pre_update
    fi

    # Leave project directory
    cd "$HOME" || _exit_script

    # Call function to download fresh copy of project
    _download_project_files

    if [ -n "$sha" ]; then
        cd "$HOME"/"${GIT_REPO_NAME}" || _exit_script
        git checkout "$sha" 1>/dev/null 2>&1
    fi

    # Move any log or json files
    if ls "$HOME/${GIT_REPO_NAME}_${NOWDATESTAMP}/"*.log 1>/dev/null 2>&1; then
        mv "$HOME/${GIT_REPO_NAME}_${NOWDATESTAMP}/"*.log "$HOME/${GIT_REPO_NAME}/"
    fi
    if ls "$HOME/${GIT_REPO_NAME}_${NOWDATESTAMP}/"*.json 1>/dev/null 2>&1; then
        mv "$HOME/${GIT_REPO_NAME}_${NOWDATESTAMP}/"*.json "$HOME/${GIT_REPO_NAME}/"
    fi

    # Log the download finishing
    _log_to_file "Finished cloning fresh copy from ${GITHUB_REPO_OWNER}/${GIT_REPO_NAME}."

    # Replace .env file
    _replace_env_project_secrets

    # Check if _post_update function has been set
    if [[ -n "$(type -t _post_update)" ]]; then
        _post_update
    else
        # If no _post_update function
        if [[ "$DOCKER_IS_PRESENT" = "1" && "${docker_compose_file}" != "0" ]]; then
            docker-compose -f "${docker_compose_file}" up -d --build
        fi

        # Call function to delete old project files if condition match
        _delete_old_project_files
    fi

    # Log the finishing of the update
    _log_to_file "Finished updated project files."
    _log_to_file ""
}

# Function: _download_project_files
# Description: Performs re-download of the project files by cloning a fresh copy via git  and updating project files.
#              It also moves the old project folder to a backup location.
#              The function replaces environment variables and propagates the environment file.
# Parameters: None
# Returns: None

_download_project_files() {

    cd "$HOME"/"${GIT_REPO_NAME}" || _exit_script

    GIT_URL=$(git remote get-url origin)

    # Leave project folder.
    cd "$HOME" || _exit_script

    # Log the folder move.
    _log_to_file "Moving old project folder."

    # Delete old environment secret.
    [[ -f "$HOME/${GIT_REPO_NAME}/.env" ]] && rm "$HOME/${GIT_REPO_NAME}/.env"

    # Remove old project directory.
    mv -u -f "$HOME/$GIT_REPO_NAME" "$HOME/${GIT_REPO_NAME}_${NOWDATESTAMP}"

    # Call inode sync.
    sync "$HOME/${GIT_REPO_NAME}_${NOWDATESTAMP}"

    # Run git clone in if to error check.
    if ! git clone --quiet "${GIT_URL}"; then # If failed to git clone

        # Move old project files back to latest directory
        mv -u -f "$HOME/${GIT_REPO_NAME}_${NOWDATESTAMP}" "$HOME/$GIT_REPO_NAME"

        # Log the error
        _log_error "Cant contact to $(_git_service_provider)"

    fi

    # Call inode sync
    sync "$HOME/${GIT_REPO_NAME}"
}

# END - UPDATE FUNCTIONS

# START - SETUP

# Function: _setup
# Description: Sets up the Linux environment for hosting.
# Parameters: None
# Returns: None

_setup() {
    _install_linux_dep
    _ensure_project_secrets_file
    # _install_update_cron
    _check_update

    _send_email "Setup $GIT_REPO_NAME on $(hostname)"
}
