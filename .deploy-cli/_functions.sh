#!/bin/bash

# Author: admin@xoren.io
# Script: _functions.sh
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
# Working Schedule
# This is referenced in the update check function and will exclude updating in given time frames, or false to disable
# Define a single string with time ranges, where ranges can be specified like 1-5:07:00-16:00
# Format: day(s):start_time-end_time|...
# Example:
# Monday to Friday: 1-5:07:00-16:00
# Saturday and Sunday: 6-7:09:00-15:00
# WORKING_SCHEDULE=${WORKING_SCHEDULE:-"1-5:07:00-16:00|6:20:00-23:59"}
WORKING_SCHEDULE=false

_registered() {
    # This is used for checking is _function.sh has been imported or not
    echo 1
}

# START - LOGS
if [[ ! -n "$(type -t _registered_logs)" ]]; then
    if [[ -f "${SCRIPT_DIR}/.${SCRIPT_NAME}/_logs.sh" ]]; then
        # shellcheck source=_functions.sh
        source "${SCRIPT_DIR}/.${SCRIPT_NAME}/_logs.sh"
    fi
fi
# END - LOGS

# START - UTILS
if [[ ! -n "$(type -t _registered_utils)" ]]; then
    if [[ -f "${SCRIPT_DIR}/.${SCRIPT_NAME}/_utils.sh" ]]; then
        # shellcheck source=_functions.sh
        source "${SCRIPT_DIR}/.${SCRIPT_NAME}/_utils.sh"
    fi
fi
# END - UTILS

# START - DEPLOYMENTS
if [[ ! -n "$(type -t _registered_deployments)" ]]; then
    if [[ -f "${SCRIPT_DIR}/.${SCRIPT_NAME}/_deployments.sh" ]]; then
        # shellcheck source=_functions.sh
        source "${SCRIPT_DIR}/.${SCRIPT_NAME}/_deployments.sh"
    fi
fi
# END - DEPLOYMENTS

# START - RUNNING FILE

# Function: _create_running_file
# Description: Creates a running file with the current date and time.
# Parameters: None
# Returns: None

_create_running_file() {
    echo "${NOWDATESTAMP}" >"${SCRIPT_RUNNING_FILE}"
}

# Function: _check_running_file
# Description: Checks if the running file exists and exits the script if it does.
# Parameters: None
# Returns: None

_check_running_file() {
    # If running file exists
    if [[ -f "${SCRIPT_RUNNING_FILE}" ]]; then
        # Log and hard exit
        _log_info "Script already running."
        exit
    fi
}

# Function: _delete_running_file
# Description: Deletes the running file.
# Parameters: None
# Returns: None

_delete_running_file() {
    # If running file exists delete it
    if [[ -f "${SCRIPT_RUNNING_FILE}" ]]; then
        rm "${SCRIPT_RUNNING_FILE}"
    fi
    # Return users tty to starting directory or home or do nothing.
    cd "${STARTING_LOCATION}" || cd "$HOME" || return
}

# END - RUNNING FILE

# Function: _exit_script
# Description: Graceful exiting of script.
# Parameters: None
# Returns: None

_exit_script() {

    rm "${SCRIPT_LOG_EMAIL_FILE}"

    # Delete running file
    _delete_running_file

    # Return users tty to starting directory or home or do nothing.
    cd "${STARTING_LOCATION}" || cd "$HOME" || exit

    # Making sure we do stop the script.
    exit
}

# START - WORKING SCHEDULE

# Function: _in_working_schedule (NOT WORKING, NOT FINISHED)
# Description: Validate working schedule variable and checks if in time.
# Parameters: None
# Returns:
#   0: Not in working hours
#   1: In configured working hours.
#   exit: Invalid working schedule variable.

_in_working_schedule() {
    local pattern="^[0-7]-[0-7]:[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$"
    local day_of_week current_hour current_day_schedule

    if [[ ! $WORKING_SCHEDULE =~ $pattern ]]; then
        _log_error "Invalid WORKING_SCHEDULE format. Please use the format: day(s):start_time-end_time."
        _exit_script
    fi

    # Get the current day of the week (1=Monday, 2=Tuesday, ..., 7=Sunday)
    day_of_week=$(date +%u)

    # Get the current hour (in 24-hour format)
    current_hour=$(date +%H)

    # Define a single string with time ranges, where ranges can be specified like 1-5:07:00-16:00
    # Format: day(s):start_time-end_time|...
    # e.g., "1-5:07:00-16:00|6:09:00-15:00|7:09:00-15:00"
    # SCRIPT_SCHEDULE="1-5:07:00-16:00|6:09:00-15:00|7:09:00-15:00"

    # Split the time_ranges string into an array using the pipe '|' delimiter
    IFS="|" read -ra ranges <<<"$WORKING_SCHEDULE"

    # Initialize a variable to store the current day's time range
    current_day_schedule=""

    # Iterate through the time ranges to find the one that matches the current day
    for range in "${ranges[@]}"; do
        days="${range%%:*}"
        times="${range#*:}"
        start_day="${days%%-*}"
        end_day="${days##*-}"

        if [ "$day_of_week" -ge "$start_day" ] && [ "$day_of_week" -le "$end_day" ]; then
            current_day_schedule="$times"
            break
        fi
    done

    if [ -n "$current_day_schedule" ]; then
        start_time="${current_day_schedule%%-*}"
        end_time="${current_day_schedule##*-}"

        if [ "$current_hour" -ge "$start_time" ] && [ "$current_hour" -le "$end_time" ]; then
            _log_error "Script is running within the allowed time range. Stopping..."
            return 0
        fi
    fi
    return 1 # Outside of working hours
}

# Function: _check_working_schedule
# Description: Check working variable doesn't equals false and runs in working schedule function
# Parameters: None
# Returns:
#   0: Not in working hours
#   1: In configured working hours

_check_working_schedule() {

    # Check for update exclude
    if [[ "$WORKING_SCHEDULE" != "false" ]]; then

        _in_working_schedule
        return
    fi
    echo 0
}
# END - WORKING SCHEDULE

# START - HELPER FUNCTIONS

# START - UPDATE CRONJOB

# Function: _install_update_cron
# Description: Sets up the update project cronjob.
# Parameters: None
# Returns: None

_install_update_cron() {
    # shellcheck disable=SC2005
    echo "$(_install_cronjob "*/15 * * * *" "/bin/bash $HOME/${GIT_REPO_NAME}/${SCRIPT} version:check")"
}

# Function: _remove_update_cron
# Description: Removes  the update project cronjob.
# Parameters: None
# Returns: None

_remove_update_cron() {
    # shellcheck disable=SC2005
    echo "$(_remove_cronjob "*/15 * * * *" "/bin/bash $HOME/${GIT_REPO_NAME}/${SCRIPT} version:check")"
}

# END - UPDATE CRONJOB

# Function: _setup_ssh_key
# Description: Sets up an ED25519 ssh key for the root user.
# Parameters: None
# Returns: None

_setup_ssh_key() {

    _log_info "Checking ssh key"

    if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
        _log_info "Creating ed25519 ssh key"
        ssh-keygen -t ed25519 -N "" -C "${GIT_EMAIL}" -f "$HOME/.ssh/id_ed25519" >/dev/null 2>&1
        _log_info "Public: $(cat "$HOME/.ssh/id_ed25519.pub")"
        eval "$(ssh-agent -s)"
        ssh-add "$HOME/.ssh/id_ed25519"
    fi
}

# END - HELPER FUNCTIONS

# START - HELPER VARIABLES

# shellcheck disable=SC2034
APT_IS_PRESENT="$(_is_present apt-get)"
# shellcheck disable=SC2034
YUM_IS_PRESENT="$(_is_present yum)"
# shellcheck disable=SC2034
PACMAN_IS_PRESENT="$(_is_present pacman)"
# shellcheck disable=SC2034
ZYPPER_IS_PRESENT="$(_is_present zypper)"
# shellcheck disable=SC2034
DNF_IS_PRESENT="$(_is_present dnf)"
# shellcheck disable=SC2034
DOCKER_IS_PRESENT="$(_is_present docker)"
# END - HELPER VARIABLES

# START - SET DISTRO VARIABLES

if [[ "$APT_IS_PRESENT" = "1" ]]; then
    PM_COMMAND=apt-get
    PM_INSTALL=(install -y)
    PREREQ_PACKAGES="docker docker-compose whois jq yq curl git bc parallel screen sendmail"
elif [[ "$YUM_IS_PRESENT" = "1" ]]; then
    PM_COMMAND=yum
    PM_INSTALL=(-y install)
    PREREQ_PACKAGES="docker docker-compose whois jq yq curl git bc parallel screen sendmail"
elif [[ "$PACMAN_IS_PRESENT" = "1" ]]; then
    PM_COMMAND=pacman
    PM_INSTALL=(-S --noconfirm)
    PREREQ_PACKAGES="docker docker-compose whois jq yq curl git bc parallel screen sendmail"
elif [[ "$ZYPPER_IS_PRESENT" = "1" ]]; then
    PM_COMMAND=zypper
    PM_INSTALL=(install -y)
    PREREQ_PACKAGES="docker docker-compose whois jq yq curl git bc parallel screen sendmail"
elif [[ "$DNF_IS_PRESENT" = "1" ]]; then
    PM_COMMAND=dnf
    PM_INSTALL=(install -y)
    PREREQ_PACKAGES="docker docker-compose whois jq yq curl git bc parallel screen sendmail"
else
    _log_error "This system doesn't appear to be supported. No supported package manager (apt/yum/pacman/zypper/dnf) was found."
    exit
fi

# Function: _install_linux_dep
# Description: Installed Linux dependencies.
# Parameters: None
# Returns: None

_install_linux_dep() {
    # Install prerequisites
    $PM_COMMAND "${PM_INSTALL[@]}" $PREREQ_PACKAGES
}

# END - SET DISTRO VARIABLES

# START - EXTRAS
if [[ ! -n "$(type -t _registered_extras)" ]]; then
    if [[ -f "${SCRIPT_DIR}/.${SCRIPT_NAME}/_extras.sh" ]]; then
        # shellcheck source=_functions.sh
        source "${SCRIPT_DIR}/.${SCRIPT_NAME}/_extras.sh"
    fi
fi
# END -EXTRAS
