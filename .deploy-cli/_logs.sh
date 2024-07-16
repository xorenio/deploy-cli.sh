#!/bin/bash

# Defaulting variables
NOWDATESTAMP="${NOWDATESTAMP:-$(date "+%Y-%m-%d_%H-%M-%S")}"

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

# # START - IMPORT FUNCTIONS
if [[ ! -n "$(type -t _registered)" ]]; then
    if [[ -f "${SCRIPT_DIR}/.${SCRIPT_NAME}/_functions.sh" ]]; then
        # shellcheck source=_functions.sh
        source "${SCRIPT_DIR}/.${SCRIPT_NAME}/_functions.sh"
    fi
fi
# END - IMPORT FUNCTIONS

_registered_logs() {
    # This is used for checking is _function.sh has been imported or not
    return 0
}

# START - LOG FUNCTIONS

# Function: _log_error
# Description: Logs an error message and sends it to the _log_data function.
# Parameters:
#   $1: The error message to log.
# Returns: None

_log_error() {
    _log_data "ERROR" "$1"
}

# Function: _log_info
# Description: Logs an informational message and sends it to the _log_data function.
# Parameters:
#   $1: The informational message to log.
# Returns: None

_log_info() {
    _log_data "INFO" "$1"
}

# Function: _log_debug
# Description: Logs a debug message and sends it to the _log_data function.
# Parameters:
#   $1: The debug message to log.
# Returns: None

_log_debug() {
    _log_data "DEBUG" "$1"
}

# Function: _log_success
# Description: Logs a success message and sends it to the _log_data function.
# Parameters:
#   $1: The success message to log.
# Returns: None

_log_success() {
    _log_data "SUCCESS" "$1"
}

# Function: _log_data
# Description: Adds a datestamp to the log message and sends it to the logs file and console.
# Parameters:
#   $1: The log level (e.g., ERROR, INFO, DEBUG, SUCCESS).
#   $2: The log message.
# Returns: None

_log_data() {
    local message

    # Check for two params
    if [[ $# -eq 2 ]]; then
        # Add prefix to message
        message="[$1] $2"
    else
        # No prefix
        message="$1"
    fi

    if [[ "$(_interactive_shell)" = "1" ]]; then
        # Log to the console if debug mode is enabled
        _log_console "[$(date "+%d/%m/%Y %H:%M:%S")]$message"
    fi

    # Log to file
    _log_to_file "[$NOWDATESTAMP]$message"
}

# Function: _log_to_file
# Description: Sends the log message to the log file.
# Parameters:
#   $1: The log message.
# Returns: None

_log_to_file() {
    # If not existing log file directory return
    if [[ ! -d $(pwd "${SCRIPT_LOG_FILE}") ]]; then
        return
    fi
    # If not existing log file create
    if [[ ! -f "${SCRIPT_LOG_FILE}" ]]; then
        echo "$1" >"${SCRIPT_LOG_FILE}"
    # If existing log file add to it
    else
        echo "$1" >>"${SCRIPT_LOG_FILE}"
    fi

    # To the email file for sending later
    # If not existing log file directory return
    if [[ ! -d $(pwd "${SCRIPT_LOG_EMAIL_FILE}") ]]; then
        return
    fi
    # If not existing log file create
    if [[ ! -f "${SCRIPT_LOG_EMAIL_FILE}" ]]; then
        echo "$1" >"${SCRIPT_LOG_EMAIL_FILE}"
    # If existing log file add to it
    else
        echo "$1" >>"${SCRIPT_LOG_EMAIL_FILE}"
    fi
}

# Function: _log_console
# Description: Prints the log message to the console.
# Parameters:
#   $1: The log message.
# Returns:
#   $1: The log message.

_log_console() {
    local _message="$1"
    echo "$_message"
}

# Function: _log_console
# Description: Prints the log message to the console.
# Parameters:
#   $1: The log message.
# Returns:
#   $1: The log message.

_send_email() {

    cat <<EOF >~/.msmtprc
defaults
tls on
tls_starttls off
tls_certcheck off

account default
host $MAIL_HOST
port $MAIL_PORT
auth on
user $MAIL_USERNAME
password $MAIL_PASSWORD
from $MAIL_FROM_ADDRESS
logfile ~/.msmtp.log
EOF
    chmod 600 ~/.msmtprc

    local _email_subject="${1:-"Untitled"}"

    if [[ "$MAIL_MAILER" = "smtp" ]]; then

        # echo -e "From: $MAIL_FROM_NAME <$MAIL_FROM_ADDRESS>\nTo: <$MAIL_TO_ADDRESS>\nSubject: ${GIT_REPO_NAME}: ${_email_subject}\n\n$(cat "$SCRIPT_LOG_EMAIL_FILE")" | msmtp -a default
        # echo -e "From: $MAIL_FROM_NAME <$MAIL_FROM_ADDRESS>\nTo: <$MAIL_TO_ADDRESS>\nSubject: ${GIT_REPO_NAME}: ${_email_subject}\n\n$(cat "$SCRIPT_LOG_EMAIL_FILE")" | msmtp --host="$MAIL_HOST" --port="$MAIL_PORT" --auth=on --user="$MAIL_USERNAME" --passwordeval="$MAIL_PASSWORD" --from="$MAIL_FROM_ADDRESS" --tls=on --tls-starttls=on --tls-certcheck=off "$MAIL_TO_ADDRESS"
        msmtp -a default -t <<EOF
From: $MAIL_FROM_NAME <$MAIL_FROM_ADDRESS>\n
To: <$MAIL_TO_ADDRESS>\n
Subject: ${GIT_REPO_NAME}: ${_email_subject}

$(cat "$SCRIPT_LOG_EMAIL_FILE")
EOF
        rm "${SCRIPT_LOG_EMAIL_FILE}"
    fi
}

# END - LOG FUNCTIONS
