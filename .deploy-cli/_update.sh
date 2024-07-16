#!/bin/bash

# This script variables
SCRIPT="${SCRIPT:-$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")}"
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
SCRIPT_DIR_NAME="${SCRIPT_DIR_NAME:-$(basename "$PWD")}"
SCRIPT_DEBUG=${SCRIPT_DEBUG:-false}

# START - IMPORT FUNCTIONS
if [[ ! -n "$(type -t _registered)" ]]; then
    source _functions.sh
fi
# END - IMPORT FUNCTIONS

# Function: __overwrite_nginx_configurations
# Description: Private function to overwrite nginx sites, configs & snippets.
# Parameters: None
# Returns: None

__overwrite_nginx_configurations() {

    # If nginx config already broken, just exit.
    if ! nginx -t >/dev/null 2>&1; then
        # echo "nginx test failed:"
        return
    fi

    local timestamp
    local backup_dir
    local nginx_dir
    local nginx_conf_path
    local available_sites_dir
    local enabled_sites_dir
    local snippets_dir
    local sites_to_copy
    local snippets_to_copy
    local nginx_conf_to_copy
    local backup_nginx_conf_file
    local backup_available_file
    local backup_enabled_files
    local backup_snippets_files

    # Backup current available-sites folder
    timestamp="$(date +"%Y%m%d_%H%M%S")"
    backup_dir="/etc/nginx/backup/${timestamp}"
    mkdir -p "${backup_dir}"

    nginx_dir="/etc/nginx"
    nginx_conf_path="${nginx_dir}/nginx.conf"

    available_sites_dir="${nginx_dir}/sites-available"
    enabled_sites_dir="${nginx_dir}/sites-enabled"
    snippets_dir="${nginx_dir}/snippets"

    sites_to_copy="$HOME/${GIT_REPO_NAME}/etc/nginx/sites-available"
    snippets_to_copy="$HOME/${GIT_REPO_NAME}/etc/nginx/snippets"

    nginx_conf_to_copy="$HOME/${GIT_REPO_NAME}/etc/nginx/nginx.conf"

    # Backup existing site files
    backup_nginx_conf_file="${backup_dir}/nginx.conf"
    backup_available_file="${backup_dir}/available-sites.tar.gz"
    backup_enabled_files="${backup_dir}/enabled-sites.tar.gz"
    backup_snippets_files="${backup_dir}/snippets.tar.gz"

    tar -czvf "${backup_available_file}" "${available_sites_dir}" >/dev/null 2>&1
    tar -czvf "${backup_enabled_files}" "${enabled_sites_dir}" >/dev/null 2>&1
    tar -czvf "${backup_snippets_files}" "${snippets_dir}" >/dev/null 2>&1

    # Remove existing files in available-sites
    rm -rf "${available_sites_dir:?}/"
    rm -rf "${enabled_sites_dir:?}/"
    rm -rf "${snippets_dir:?}/"

    mkdir -p "${available_sites_dir}"
    mkdir -p "${enabled_sites_dir}"
    mkdir -p "${snippets_dir}"

    # Copy nginx config
    cp -r "${nginx_conf_path}" "${backup_nginx_conf_file}"
    cp -r "${nginx_conf_to_copy}" "${nginx_conf_path}"

    # Copy new site files from /home/sites/
    cp -r "${sites_to_copy}"/* "${available_sites_dir}"
    cp -r "${snippets_to_copy}"/* "${snippets_dir}"

    __symlink_available_sites

    sync

    # Check nginx configuration after updating files

    if nginx -t >/dev/null 2>&1; then
        _log_info "Nginx test after configuration update successful"
        systemctl restart nginx 2>&1

        # Delete un-used certs
        __delete_unused_certs

        # Delete left over backup archives.
        rm "${backup_available_file}"
        rm "${backup_enabled_files}"
        rm "${backup_snippets_files}"

        # Delete backed up nginx config file.
        rm "${backup_nginx_conf_file}"

        # Delete baackup folder if empty.
        if [ -d "$backup_dir" ]; then
            if [ -z "$(ls -A "$backup_dir")" ]; then
                rm -rf "$backup_dir"
            fi
        fi
        _send_email "$GIT_REPO_NAME on $(hostname) - configuration update successful"

        return
    else
        _log_error "Nginx new configuration failed, Rolling back..."
        _send_email "$GIT_REPO_NAME on $(hostname) - Rolling back..."

        # Delete updated configs
        rm -rf "${available_sites_dir:?}/"
        rm -rf "${enabled_sites_dir:?}/"
        rm -rf "${snippets_dir:?}/"

        # Copy back backed up nginx config.
        cp -r "${backup_nginx_conf_file}" "${nginx_conf_path}"

        sync

        # Restore backup, extract to / as archive has /etc/nginx/... structure.
        tar -xzvf "${backup_available_file}" -C / >/dev/null 2>&1
        tar -xzvf "${backup_enabled_files}" -C / >/dev/null 2>&1
        tar -xzvf "${backup_snippets_files}" -C / >/dev/null 2>&1

        sync

        # Delete left over backup archives.
        rm "${backup_available_file}"
        rm "${backup_enabled_files}"
        rm "${backup_snippets_files}"

        # Delete backed up nginx config file.
        rm "${backup_nginx_conf_file}"

        # Delete baackup folder if empty.
        if [ -d "$backup_dir" ]; then
            if [ -z "$(ls -A "$backup_dir")" ]; then
                rm -rf "$backup_dir"
            fi
        fi

        sync

        # echo 1
        return
    fi
}

# Function: __symlink_available_sites
# Description: Private function to create symlinks for every available nginx site config.
# Parameters: None
# Returns: None

__symlink_available_sites() {
    local available_sites_dir="/etc/nginx/sites-available"
    local sites_enabled_dir="/etc/nginx/sites-enabled"

    # Ensure the directories exist
    mkdir -p "$available_sites_dir"
    mkdir -p "$sites_enabled_dir"

    # Loop through files in available-sites directory
    for file in "$available_sites_dir"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            symlink="$sites_enabled_dir/$filename"
            # Check for default site first.
            if [[ "${filename,,}" = "readme.md" ]]; then
                echo "Skipping readme." >/dev/null 2>&1
            elif [[ "$filename" = "default" ]]; then
                # Check if symlink already exists
                if [[ ! -L "$symlink" ]]; then
                    # Create symlink
                    ln -s "../sites-available/$filename" "$symlink"
                    _log_info "Created symlink $symlink"
                fi
            # Check if Re get a cert for domain
            elif [[ "$(__cert_domain "$filename")" = "0" ]]; then
                # Check if symlink already exists
                if [[ ! -L "$symlink" ]]; then
                    # Create symlink
                    ln -s "../sites-available/$filename" "$symlink"
                    _log_info "Created symlink $symlink"
                fi
            fi
        fi
    done
}
# Function: __cert_domain
# Description: Acquires a SSL for given domain after checking.
# Parameters: None
#   $1 - domain name for cert.
# Returns:
#   0 - Success.
#   1 - Failed.

__cert_domain() {
    local site_domain="$1"
    local letsencrypt_live_dir
    local base_domain
    local www_domain
    local verification_dir
    local verification_string

    # Publicly available on point domains on http.
    verification_dir="/var/www/.hosted"
    verification_string=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 9)

    # Ensure hosted directory exists
    mkdir -p "${verification_dir}"

    # Directory where Let's Encrypt certificates are stored
    letsencrypt_live_dir="/etc/letsencrypt/live"

    # Initialize www_domain
    base_domain="${site_domain}"
    www_domain="www.$site_domain"

    # Check if the site_domain already has www.
    if [[ "$site_domain" == www.* ]]; then
        # Remove the leading www.
        base_domain="${site_domain#www.}"
        www_domain="$site_domain"
    fi

    # Checks to stop getting cert.
    if [[ -d "$letsencrypt_live_dir/$base_domain" || -d "$letsencrypt_live_dir/$www_domain" ]]; then
        _log_to_file "[$(date "+%Y-%m-%d_%H-%M-%S")] Certificate already exists for $site_domain"
        echo 0
        return
    fi

    # Add in cert file checking for assigned domains
    # openssl x509 -in /etc/letsencrypt/live/domain.com/fullchain.pem -text -noout \
    # | grep -E 'Subject:|X509v3 Subject Alternative Name' -A 1 | sed -n '/^ *DNS:/p'

    _log_to_file "[$(date "+%Y-%m-%d_%H-%M-%S")] No certificate found for $site_domain, attempting to obtain certificate..."

    # Create verification files.
    echo "${verification_string}" >"${verification_dir}/${www_domain}.txt"
    echo "${verification_string}" >"${verification_dir}/${base_domain}.txt"

    sync

    # Allow www-data user/group access to the directory.
    chown www-data:www-data "${verification_dir}" -R

    # Try get those files.
    hosting_www_domain=$(curl --silent "http://$www_domain/.hosted/$www_domain.txt")
    hosting_base_domain=$(curl --silent "http://$base_domain/.hosted/$base_domain.txt")
    cert_www_domain=0
    cert_base_domain=0
    if [[ "$hosting_www_domain" == *"$verification_string"* ]]; then
        cert_www_domain=1
    fi
    if [[ "$hosting_base_domain" == *"$verification_string"* ]]; then
        cert_base_domain=1
    fi

    # Delete verification files.
    rm "${verification_dir}/${www_domain}.txt"
    rm "${verification_dir}/${base_domain}.txt"

    # If not lets encrypt cert required return success
    if [[ "${ENABLED_LETSENCRYPT}" != "true" ]]; then
        # Signal success no cert required..
        if [[ "$cert_www_domain" = "1" || "$cert_base_domain" = "1" ]]; then
            # Signal success domain hosted
            echo 0
        else
            # Signal failure no domain hosted
            echo 1
        fi
        return
    fi

    if [[ "$cert_www_domain" = "1" || "$cert_base_domain" = "1" ]]; then
        _log_to_file "[$(date "+%Y-%m-%d_%H-%M-%S")] DNS is set for $site_domain"

        # Attempt to obtain certificate for both the main domain and the www subdomain.
        if [[ "$cert_www_domain" = "1" && "$cert_base_domain" = "1" ]]; then
            certbot certonly --webroot -w /var/www -d "$base_domain" -d "$www_domain"
        elif [[ "$cert_www_domain" = "1" ]]; then
            certbot certonly --webroot -w /var/www -d "$www_domain"
        elif [[ "$cert_base_domain" = "1" ]]; then
            certbot certonly --webroot -w /var/www -d "$base_domain"
        fi

        if [ $? -eq 0 ]; then
            _log_to_file "[$(date "+%Y-%m-%d_%H-%M-%S")] Certificate obtained successfully for $base_domain and $www_domain"
            # Signal success.
            sync
            echo 0
            return
        else
            _log_to_file "[$(date "+%Y-%m-%d_%H-%M-%S")] Failed to obtain certificate for $site_domain"
            # Signal error no cert.
            sync
            echo 1
            return
        fi
    fi

    # Signal error no domain hosted.
    echo 1
    return
}

# Function: __delete_unused_certs
# Description: Handles deleting un-used lets encrypt certs.
# Parameters: None
# Returns: None

__delete_unused_certs() {
    local NGINX_DIR="/etc/nginx/sites-available"
    local CERT_DIR="/etc/letsencrypt/live"

    # Get the list of domains in Nginx sites-available
    nginx_domains=$(ls $NGINX_DIR)

    # Loop through all certificate directories
    for cert_path in "$CERT_DIR"/*; do
        if [ -d "$cert_path" ]; then

            cert_domain=$(basename "$cert_path")

            # Extract domains from the certificate
            cert_domains=$(openssl x509 -in "$cert_path/fullchain.pem" -text -noout | grep -E 'Subject:|X509v3 Subject Alternative Name' -A 1 | awk -F 'DNS:|CN=' '/CN=/{print $2} /^ *DNS:/{print $2}')
            # Flag to check if any domain matches
            match_found=false

            # Check if any of the certificate domains match the Nginx configuration
            for domain in $cert_domains; do
                if echo "$nginx_domains" | grep -qw "$domain"; then
                    match_found=true
                    break
                fi
            done
            # echo "$cert_domain match $match_found"
            # If no match is found, print the unused certificate
            if [ "$match_found" = false ]; then
                _log_info "Unused certificate found for domains in: $cert_path"
                certbot delete --cert-name "$cert_domain"
            fi
        fi
    done
}

# Function: _update_limits_conf
# Description: Function to update limits.conf.
# Parameters: None
# Returns: None

__update_limits_conf() {
    local limit_type=$1
    local new_limit=$2

    if grep -q "\* $limit_type nofile" /etc/security/limits.conf; then
        sed -i "s/\* $limit_type nofile.*/\* $limit_type nofile $new_limit/" /etc/security/limits.conf
    else
        echo "* $limit_type nofile $new_limit" >>/etc/security/limits.conf
    fi
}

# Function: _update_nginx_conf
# Description: Function to update nginx.conf.
# Parameters: None
# Returns: None

__update_nginx_conf() {
    local new_limit=$1

    if grep -q "worker_rlimit_nofile" /etc/nginx/nginx.conf; then
        _log_info "Updating Nginx worker_rlimit_nofile to $new_limit"
        sed -i "s/worker_rlimit_nofile.*/worker_rlimit_nofile $new_limit;/" /etc/nginx/nginx.conf
    else
        # Add worker_rlimit_nofile at the top of the nginx.conf file
        _log_info "Adding Nginx worker_rlimit_nofile to $new_limit"
        sed -i "1s/^/worker_rlimit_nofile $new_limit;\n/" /etc/nginx/nginx.conf
    fi
}

# Function: _ensure_file_limits
# Description: Ensure the right file open limits are set.
# Parameters: None
# Returns: None

__ensure_file_limits() {
    # Desired limit value
    local DESIRED_LIMIT=65536
    local restart_nginx=false

    # Check current limits
    local current_soft_limit
    current_soft_limit=$(ulimit -n)
    local current_hard_limit
    current_hard_limit=$(ulimit -Hn)

    #echo "Current soft limit: $current_soft_limit"
    #echo "Current hard limit: $current_hard_limit"

    # Update limits if needed
    if [ "$current_soft_limit" -lt "$DESIRED_LIMIT" ]; then
        _log_info "Updating soft limit to $DESIRED_LIMIT"
        __update_limits_conf soft $DESIRED_LIMIT
        restart_nginx=true
    fi

    if [ "$current_hard_limit" -lt "$DESIRED_LIMIT" ]; then
        _log_info "Updating hard limit to $DESIRED_LIMIT"
        __update_limits_conf hard $DESIRED_LIMIT
        restart_nginx=true
    fi

    # Update nginx.conf
    __update_nginx_conf $DESIRED_LIMIT

    #echo "Restarting Nginx to apply changes..."
    if [ $restart_nginx = true ]; then
        systemctl restart nginx >/dev/null 2>&1
    fi
}

#
# Function: update_sysctl_conf
# Description: Function to update sysctl.conf if the setting is not already set or needs to be updated.
# Parameters: None
# Returns: None

__update_sysctl_conf() {
    local key=$1
    local value=$2
    local current_value
    current_value="$(sysctl -n "$key" 2>/dev/null)"

    if [ "$current_value" != "$value" ]; then
        if grep -q "^$key" /etc/sysctl.conf; then
            sed -i "s/^$key.*/$key = $value/" /etc/sysctl.conf
        else
            echo "$key=$value" >>/etc/sysctl.conf
        fi
        sysctl -q -w "$key=$value" >/dev/null 2>&1
    fi
}

# Function: _pre_update
# Description: Performs pre update checks.
# Parameters: None
# Returns: None

_pre_update() {
    local dhparam_pid=false
    local openssl_pid=false

    # Create Diffie-Hellman key exchange file if missing
    if [[ ! -f "/etc/nginx/dhparam.pem" ]]; then
        _log_info "Creating dhparam"
        # Generate Diffie-Hellman parameters
        openssl dhparam -out "/etc/nginx/dhparam.pem" 2048 >/dev/null 2>&1 &
        # Capture the PID of the openssl command
        dhparam_pid=$!
    fi
    # Create snakeoil cert if missing
    if [[ ! -f "/etc/ssl/private/ssl-cert-snakeoil.key" || ! -f "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]]; then
        _log_info "Creating snakeoil"
        # Generate a self-signed SSL certificate
        openssl req -x509 -nodes -newkey rsa:4096 \
            -keyout "/etc/ssl/private/ssl-cert-snakeoil.key" \
            -out "/etc/ssl/certs/ssl-cert-snakeoil.pem" -days 3650 \
            -subj "/C=${APP_ENCODE: -2}/ST=$(echo "$APP_TIMEZONE" | cut -d'/' -f2)/L=$(echo "$APP_TIMEZONE" | cut -d'/' -f2)/O=CompanyName/OU=IT Department/CN=example.com" >/dev/null 2>&1 &
        # Capture the PID of the openssl command
        openssl_pid=$!
    fi

    if [[ "$openssl_pid" != "false" ]]; then
        _wait_pid_expirer "$openssl_pid"
        _log_info "Finished generating self-signed SSL certificate."
    fi

    if [[ "$dhparam_pid" != "false" ]]; then
        _wait_pid_expirer "$dhparam_pid"
        _log_info "Finished generating Diffie-Hellman parameters."
    fi
}

# Function: _post_update
# Description: Performs some post flight checks..
# Parameters: None
# Returns: None

_post_update() {

    if [[ ! -f "$HOME/${GIT_REPO_NAME}/.env" ]]; then
        cp "$HOME/${GIT_REPO_NAME}/.env.production" "$HOME/${GIT_REPO_NAME}/.env"
    fi

    __overwrite_nginx_configurations

    # Increase file descriptors limit
    __update_sysctl_conf "fs.file-max" "2097152"

    # Increase network backlog
    __update_sysctl_conf "net.core.somaxconn" "65535"
    __update_sysctl_conf "net.core.netdev_max_backlog" "65535"

    # Enable TCP fast open
    __update_sysctl_conf "net.ipv4.tcp_fastopen" "3"

    # Optimize TCP settings
    __update_sysctl_conf "net.ipv4.tcp_fin_timeout" "30"
    __update_sysctl_conf "net.ipv4.tcp_tw_reuse" "1"
    __update_sysctl_conf "net.ipv4.tcp_syncookies" "1"
    __update_sysctl_conf "net.ipv4.tcp_max_syn_backlog" "65535"
    __update_sysctl_conf "net.ipv4.tcp_max_tw_buckets" "1440000"

    # Apply the settings
    sysctl -q -p

    __ensure_file_limits

    sync

    # Clean-up

    _delete_old_project_files
}
