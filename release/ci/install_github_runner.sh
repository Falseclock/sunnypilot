#!/usr/bin/env bash
set -e

DEFAULT_REPO_URL="https://github.com/sunnypilot"
if [ $# -eq 0 ]; then
    echo "Required argument: <github_token>"
    echo "Optional argument: <repository_url> (default: ${DEFAULT_REPO_URL})"
    exit 1
fi

# Constants
GITHUB_TOKEN="$1"
REPO_URL="${2:-$DEFAULT_REPO_URL}"
RUNNER_USER="github-runner"
USER_GROUPS="comma,gpu,gpio,sudo"
BASE_DIR="/data/github"
RUNNER_DIR="${BASE_DIR}/runner"
BUILDS_DIR="${BASE_DIR}/builds"
LOGS_DIR="${BASE_DIR}/logs"
CACHE_DIR="${BASE_DIR}/cache"
OPENPILOT_DIR="${BASE_DIR}/openpilot"
SERVICE_NAME="github-runner"

create_directories() {
    sudo mkdir -p "$RUNNER_DIR" "$BUILDS_DIR" "$LOGS_DIR" "$CACHE_DIR" "$OPENPILOT_DIR"
    mkdir -p "/data/openpilot"
    sudo chown -R comma:comma "/data/openpilot"
}

download_and_setup_runner() {
    cd "$RUNNER_DIR"
    curl -o actions-runner-linux-arm64-2.321.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-arm64-2.321.0.tar.gz
    tar xzf ./actions-runner-linux-arm64-2.321.0.tar.gz
    rm ./actions-runner-linux-arm64-2.321.0.tar.gz
    chmod +x ./config.sh
}

setup_runner_user() {
    sudo useradd --comment 'GitHub Runner' --create-home --home-dir ${BASE_DIR} ${RUNNER_USER} --shell /bin/bash -G ${USER_GROUPS} || sudo usermod -aG ${USER_GROUPS} ${RUNNER_USER}
    export BASE_DIR
    sudo -u ${RUNNER_USER} bash -c "truncate -s 0 '${BASE_DIR}/.bash_logout'"
}

create_sudoers_entry() {
    sudo grep -qxF "${RUNNER_USER} ALL=(ALL) NOPASSWD: ALL" /etc/sudoers || echo "${RUNNER_USER} ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers
}

configure_runner() {
    cd "$RUNNER_DIR"
    sudo -u ${RUNNER_USER} ./config.sh --url "$REPO_URL" --token "$GITHUB_TOKEN" --name $(hostname) --runnergroup "tici-tizi" --labels "tici" --work "$BUILDS_DIR" --unattended
}

set_directory_permissions() {
    sudo chown -R ${RUNNER_USER}:comma "$BASE_DIR"
    sudo chmod g+rwx "$BASE_DIR"
    sudo chmod g+s "$BASE_DIR"
}

create_runner_service() {
    cat <<EOL | sudo tee /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=GitHub Runner
After=syslog.target network.target
[Service]
Type=simple
User=${RUNNER_USER}
WorkingDirectory=${RUNNER_DIR}
ExecStart=/usr/bin/unshare -m -- sh -c 'mount --bind $OPENPILOT_DIR /data/openpilot && exec ${RUNNER_DIR}/run.sh'
Restart=always
RestartSec=120
[Install]
WantedBy=multi-user.target
EOL
}

start_runner_service() {
    sudo systemctl daemon-reload
    sudo systemctl disable ${SERVICE_NAME}
    sudo systemctl start ${SERVICE_NAME}
}

# Make filesystem writable
sudo mount -o remount,rw /

# Ensure filesystem is remounted as read-only on script exit
trap "sudo mount -o remount,ro /" EXIT

# Execute installation steps
setup_runner_user
create_sudoers_entry
create_directories
download_and_setup_runner
configure_runner
set_directory_permissions
create_runner_service
start_runner_service