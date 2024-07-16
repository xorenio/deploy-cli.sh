#!/bin/bash

# Author: admin@xoren.io
# Script: _utils.sh
# Link https://github.com/xorenio/deploy-cli.sh
# Description: Functions script.

# Script variables
NOWDATESTAMP="${NOWDATESTAMP:-$(date "+%Y-%m-%d_%H-%M-%S")}"

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

_registered_utils() {
    # This is used for checking is _function.sh has been imported or not
    return 0
}

# Function: _is_present
# Description: Checks if the given command is present in the system's PATH.
# Parameters:
#   $1: The command to check.
# Returns:
#   1 if the command is present, otherwise void.

_is_present() { command -v "$1" &>/dev/null && echo 1; }

# Function: _is_file_open
# Description: Checks if the given file is open by any process.
# Parameters:
#   $1: The file to check.
# Returns:
#   1 if the file is open, otherwise void.

_is_file_open() { lsof "$1" &>/dev/null && echo 1; }

# Function: _is_in_screen
# Description: Function to run the DIY.com website scraper..
# Parameters: None
# Returns: None

_is_in_screen() {
    if [[ ! -z "$STY" ]]; then
        echo "1"
    else
        echo "0"
    fi
}

# Function: _interactive_shell
# Description: Checks if the script is being run from a headless terminal or cron job.
#              Returns 1 if running from a cron job or non-interactive environment, 0 otherwise.
# Parameters: None
# Returns:
#   1 if running from a cron job or non-interactive environment
#   0 otherwise.

_interactive_shell() {
    # Check if the script is being run from a headless terminal or cron job
    if [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
        if [ -t 0 ] && [ -t 1 ]; then
            # Script is being run from an interactive shell or headless terminal
            echo 1
        else
            # Script is likely being run from a cron job or non-interactive environment
            echo 0
        fi
    else
        # Script is being run from an interactive shell
        echo 1
    fi
}

# Function: _wait_pid_expirer
# Description: Waits for a process with the given PID to expire.
# Parameters:
#   $1: The PID of the process to wait for.
# Returns: None

_wait_pid_expirer() {
    # If sig is 0, then no signal is sent, but error checking is still performed.
    while kill -0 "$1" 2>/dev/null; do
        sleep 1s
    done
}

# Function: _install_cronjob
# Description: Installs a cron job from the crontab.
# Parameters:
#   $1: The cron schedule for the job. "* * * * * "
#   $2: The command of the job. "/bin/bash command-to-be-executed"
# Returns: None

_install_cronjob() {

    if [[ $# -lt 2 ]]; then
        _log_info "Missing arguments <$(echo "$1" || echo "schedule")> <$([ ${#2} -ge 1 ] && echo "$2" || echo "command")>"
        _exit_script
    fi

    # Define the cron job entry
    local cron_schedule=$1
    local cron_job=$2
    local cron_file="/tmp/.temp_cron"

    _log_info "Installing Cron job: ${cron_job}"

    # Load the existing crontab into a temporary file
    crontab -l >"$cron_file"

    # Check if the cron job already exists
    if ! grep -q "$cron_job" "$cron_file"; then
        # Append the new cron job entry to the temporary file
        echo "$cron_schedule $cron_job" >>"$cron_file"

        # Install the updated crontab from the temporary file
        crontab "$cron_file"

        if [[ $? -eq 0 ]]; then
            _log_info "Cron job installed successfully."
        else
            _log_error "Cron job installation failed: $cron_schedule $cron_job"
        fi
    else
        _log_info "Cron job already exists."
    fi

    # Remove the temporary file
    rm "$cron_file"
}

# Function: _remove_cronjob
# Description: Uninstalls a cron job from the crontab.
# Parameters:
#   $1: The cron schedule for the job. "* * * * * "
#   $2: The command of the job. "/bin/bash command-to-be-executed"
# Returns: None

_remove_cronjob() {
    if [[ $# -lt 2 ]]; then
        _log_info "Missing arguments <$(echo "$1" || echo "schedule")> <$([ ${#2} -ge 1 ] && echo "$2" || echo "command")>"
        _exit_script
    fi

    # Define the cron job entry
    local cron_schedule=$1
    local cron_job=$2
    local cron_file="/tmp/.temp_cron"

    _log_info "Removing cronjob: ${cron_job}"

    # Load the existing crontab into a temporary file
    crontab -l >_temp_cron

    # Check if the cron job exists in the crontab
    if grep -q "$cron_job" "$cron_file"; then
        # Remove the cron job entry from the temporary file
        sed -i "/$cron_schedule $cron_job/d" "$cron_file"

        # Install the updated crontab from the temporary file
        crontab "$cron_file"

        if [[ $? -eq 0 ]]; then
            _log_info "Cron job removed successfully."
        else
            _log_error "Failed to install cronjob: $cron_schedule $cron_job"
        fi
    else
        _log_info "Cron job not found."
    fi

    # Remove the temporary file
    rm "$cron_file"
}

# START - GEOLCATION FUNCTIONS

# Function: _valid_ip
# Description: Checks if the given IP address is valid.
# Parameters:
#   $1: The IP address to validate.
# Returns:
#   0 if the IP address is valid, 1 otherwise.

_valid_ip() {
    local ip="$1"
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && $(
        IFS='.'
        set -- "$ip"
        (($1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255))
    ) ]]
}

# Function: _set_location_var
# Description: Retrieves the public IP address and sets the ISOLOCATION variable based on the country.
# Parameters: None
# Returns: None

_set_location_var() {
    local public_ip
    public_ip=$(_get_public_ip)

    if _valid_ip "${public_ip}"; then
        # Whois public ip and grep first country code
        ISOLOCATION="$(whois "$public_ip" -a | grep -iE ^country: | head -n 1)"
        ISOLOCATION="${ISOLOCATION:(-2)}"
    fi
}

# END - GEOLCATION FUNCTIONS

# START - COMPLETION

# _script_completion() {
#     local cur prev opts
#     COMPREPLY=()
#     cur="${COMP_WORDS[COMP_CWORD]}"
#     prev="${COMP_WORDS[COMP_CWORD-1]}"
#     opts="user:add linux:install setup:hpages setup:ssh:keys setup:certbot setup:git:profile setup:well-known certbot:add system:json repo:check repo:update queue:worker config:backup config:restore version:local version:remote"

#     case "${prev}" in
#         certbot:add)
#             # Custom completion for certbot:add option
#             COMPREPLY=($(compgen -f -- "${cur}"))
#             return 0
#             ;;
#         user:add)
#             # Custom completion for user:add option
#             COMPREPLY=($(compgen -f -- "${cur}"))
#             return 0
#             ;;
#         *)
#             ;;
#     esac

#     COMPREPLY=($(compgen -W "${opts}" -- "${cur}"))
#     return 0
# }

# complete -F _script_completion "${SCRIPT}"

# END - COMPLETION
