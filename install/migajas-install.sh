#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ultimoistante (ultimoistante)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ultimoistante/migajas

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  gcc \
  git \
  make \
  nginx
msg_ok "Installed Dependencies"

GO_VERSION="$(curl -fsSL https://go.dev/VERSION?m=text | head -1 | cut -c3-)" setup_go
NODE_VERSION="22" setup_nodejs
get_lxc_ip

msg_info "Cloning Migajas"
$STD git clone https://github.com/ultimoistante/migajas.git /opt/migajas
msg_ok "Cloned Migajas"

msg_info "Building Backend"
cd /opt/migajas/backend
$STD CGO_CFLAGS="-Wno-discarded-qualifiers" go build -o migajas-backend .
msg_ok "Built Backend"

msg_info "Building Frontend"
cd /opt/migajas/frontend
$STD npm install @sveltejs/adapter-static
sed -i "s|@sveltejs/adapter-auto|@sveltejs/adapter-static|" svelte.config.js
sed -i "s|adapter()|adapter({ fallback: 'index.html' })|" svelte.config.js
cat <<EOF >/opt/migajas/frontend/src/routes/+layout.ts
export const ssr = false;
export const prerender = false;
EOF
$STD npm install
$STD npm run build
msg_ok "Built Frontend"

msg_info "Configuring Migajas"
mkdir -p /opt/migajas/data/attachments
JWT_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_SECRET=$(openssl rand -hex 32)
cat <<EOF >/opt/migajas/.env
PORT=8080
DB_PATH=/opt/migajas/data/migajas.db
ATTACHMENTS_DIR=/opt/migajas/data/attachments
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
ACCESS_TOKEN_TTL_MINUTES=15
REFRESH_TOKEN_TTL_DAYS=7
FRONTEND_URL=http://${LOCAL_IP}
ALLOW_SELF_REGISTRATION=false
EOF
msg_ok "Configured Migajas"

msg_info "Configuring Nginx"
rm -f /etc/nginx/sites-enabled/default
cat <<EOF >/etc/nginx/conf.d/migajas.conf
server {
    listen 80;
    server_name _;
    client_max_body_size 50M;

    root /opt/migajas/frontend/build;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
$STD systemctl restart nginx
msg_ok "Configured Nginx"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/migajas.service
[Unit]
Description=Migajas Note-Taking App
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/migajas/backend
EnvironmentFile=/opt/migajas/.env
ExecStart=/opt/migajas/backend/migajas-backend
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now migajas
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
