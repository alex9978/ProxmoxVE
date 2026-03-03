#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/alex9978/ProxmoxVE/add-migajas/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: ultimoistante (ultimoistante)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ultimoistante/migajas

APP="Migajas"
var_tags="${var_tags:-notes;privacy}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_unprivileged="${var_unprivileged:-1}"

# Override: point install script to our fork instead of community-scripts
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/alex9978/ProxmoxVE/add-migajas/install/migajas-install.sh"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/migajas ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Checking for Updates"
  cd /opt/migajas
  $STD git fetch origin main
  LOCAL_COMMIT=$(git rev-parse HEAD)
  REMOTE_COMMIT=$(git rev-parse origin/main)

  if [[ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]]; then
    msg_ok "Update available"

    msg_info "Stopping Service"
    rc-service migajas stop
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/migajas/data /opt/migajas_data_backup
    msg_ok "Backed up Data"

    msg_info "Pulling Updates"
    $STD git pull origin main
    msg_ok "Pulled Updates"

    msg_info "Building Backend"
    cd /opt/migajas/backend
    export CGO_CFLAGS="-Wno-discarded-qualifiers"
    $STD go build -o migajas-backend .
    unset CGO_CFLAGS
    msg_ok "Built Backend"

    msg_info "Building Frontend"
    cd /opt/migajas/frontend
    $STD npm ci
    $STD npm run build
    msg_ok "Built Frontend"

    msg_info "Restoring Data"
    cp -r /opt/migajas_data_backup/. /opt/migajas/data/
    rm -rf /opt/migajas_data_backup
    msg_ok "Restored Data"

    msg_info "Starting Service"
    rc-service migajas start
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update available"
  fi
  exit
}

start
build_container
# Re-run install from our fork (overrides the community-scripts hardcoded URL)
lxc-attach -n "$CTID" -- bash -c "$(curl -fsSL "$INSTALL_SCRIPT_URL")"
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
