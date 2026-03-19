#!/bin/bash

APPID="amiexposed"
APP_USER="amiexposed"
APP_SERVICE="${APPID}"
APP_HOME="/home/${APP_USER}"
APP_CODE_DIR="${APP_HOME}/am-i-exposed"
APP_DATA_DIR="/mnt/hdd/app-data/${APPID}"
APP_PORT="3090"
PNPM_VERSION="10.26.1"

GITHUB_REPO="https://github.com/Copexit/am-i-exposed.git"
GITHUB_COMMIT="89020e33bfb31181bd7838b569500366d0047e91"

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.am-i-exposed.sh status            -> status information (key=value)"
  echo "# bonus.am-i-exposed.sh on                -> install and enable service"
  echo "# bonus.am-i-exposed.sh off [delete-data] -> disable and remove service"
  echo "# bonus.am-i-exposed.sh update            -> update code and rebuild"
  echo "# bonus.am-i-exposed.sh menu              -> SSH info dialog"
  exit 1
fi

echo "# Running: 'bonus.am-i-exposed.sh $*'"

source /mnt/hdd/app-data/raspiblitz.conf 2>/dev/null

isInstalled=$(sudo ls /etc/systemd/system/${APP_SERVICE}.service 2>/dev/null | grep -c "${APP_SERVICE}.service")
isRunning=$(sudo systemctl status ${APP_SERVICE} 2>/dev/null | grep -c 'active (running)')

if [ "${isInstalled}" = "1" ]; then
  localIP=$(hostname -I | awk '{print $1}')
fi

if [ "$1" = "status" ]; then
  echo "appID='${APPID}'"
  echo "appDisplayName='am-i-exposed'"
  echo "appUser='${APP_USER}'"
  echo "githubRepo='${GITHUB_REPO}'"
  echo "githubCommit='${GITHUB_COMMIT}'"
  echo "isInstalled=${isInstalled}"
  echo "isRunning=${isRunning}"
  if [ "${isInstalled}" = "1" ]; then
    echo "port=${APP_PORT}"
    echo "localIP='${localIP}'"
  fi
  exit 0
fi

if [ "$1" = "menu" ]; then
  source <(/home/admin/config.scripts/bonus.am-i-exposed.sh status)
  dialogTitle=" am-i-exposed "
  dialogText="Open in your local web browser:\nhttp://${localIP}:${APP_PORT}\n"
  whiptail --title "${dialogTitle}" --msgbox "${dialogText}" 10 60
  echo "please wait ..."
  exit 0
fi

if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  if [ "${isInstalled}" = "1" ]; then
    echo "# ${APP_SERVICE}.service is already installed."
    exit 1
  fi

  echo "# Installing ${APPID}"

  /home/admin/config.scripts/bonus.nodejs.sh on || exit 1

  sudo apt-get update
  sudo apt-get install -y git curl rsync || exit 1

  if id -u "${APP_USER}" >/dev/null 2>&1; then
    echo "# User ${APP_USER} already exists"
  else
    echo "# Creating dedicated user ${APP_USER}"
    sudo adduser --system --group --shell /usr/sbin/nologin --home "${APP_HOME}" "${APP_USER}" || exit 1
  fi

  sudo mkdir -p "${APP_DATA_DIR}" || exit 1
  sudo chown -R "${APP_USER}:${APP_USER}" "${APP_DATA_DIR}" || exit 1

  if [ -d "${APP_CODE_DIR}" ]; then
    echo "# Existing app directory found, updating source"
    cd "${APP_CODE_DIR}" || exit 1
    sudo -u "${APP_USER}" git fetch --tags || exit 1
    sudo -u "${APP_USER}" git reset --hard "${GITHUB_COMMIT}" || exit 1
  else
    echo "# Cloning source code"
    sudo -u "${APP_USER}" git clone "${GITHUB_REPO}" "${APP_CODE_DIR}" || exit 1
    cd "${APP_CODE_DIR}" || exit 1
    sudo -u "${APP_USER}" git reset --hard "${GITHUB_COMMIT}" || exit 1
  fi

  echo "# Installing dependencies and building web UI"
  cd "${APP_CODE_DIR}" || exit 1
  sudo -u "${APP_USER}" npx -y "pnpm@${PNPM_VERSION}" install || exit 1
  sudo -u "${APP_USER}" npx -y "pnpm@${PNPM_VERSION}" build || exit 1

  echo "# Writing local web/proxy server"
  cat >/var/cache/raspiblitz/${APPID}-server.mjs <<'EOF'
import { createServer } from "node:http";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const PORT = Number(process.env.PORT || 3090);
const ROOT = process.env.ROOT_DIR || "/home/amiexposed/am-i-exposed/out";
const MEMPOOL_BASE = process.env.MEMPOOL_BASE || "http://127.0.0.1:8999";

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".ico": "image/x-icon",
  ".webp": "image/webp",
  ".txt": "text/plain; charset=utf-8",
  ".map": "application/json; charset=utf-8",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

function toMempoolPath(urlPath) {
  if (urlPath.startsWith("/api/")) return `/api/v1/${urlPath.slice(5)}`;
  if (urlPath.startsWith("/signet/api/")) return `/api/v1/${urlPath.slice(12)}`;
  if (urlPath.startsWith("/testnet4/api/")) return `/api/v1/${urlPath.slice(14)}`;
  return null;
}

async function proxy(req, res, targetPath) {
  try {
    const targetUrl = `${MEMPOOL_BASE}${targetPath}${new URL(req.url, "http://localhost").search}`;
    const upstream = await fetch(targetUrl, {
      method: req.method,
      headers: {
        Accept: req.headers.accept || "*/*",
        "User-Agent": "am-i-exposed-raspiblitz",
      },
    });

    res.statusCode = upstream.status;
    res.statusMessage = upstream.statusText;
    for (const [k, v] of upstream.headers.entries()) {
      if (k === "transfer-encoding") continue;
      res.setHeader(k, v);
    }

    if (!upstream.body) {
      res.end();
      return;
    }

    for await (const chunk of upstream.body) {
      res.write(chunk);
    }
    res.end();
  } catch (error) {
    res.statusCode = 502;
    res.setHeader("content-type", "application/json; charset=utf-8");
    res.end(JSON.stringify({ error: "proxy_error", message: String(error) }));
  }
}

async function serveFile(req, res) {
  const pathname = new URL(req.url, "http://localhost").pathname;
  const cleanPath = normalize(pathname).replace(/^\.\.(\/|\\|$)/, "");
  const trimmedPath = cleanPath.replace(/^\/+/, "");
  const requested = trimmedPath === "" ? "index.html" : trimmedPath;
  const filePath = join(ROOT, requested);

  try {
    const fileStat = await stat(filePath);
    if (fileStat.isFile()) {
      res.statusCode = 200;
      res.setHeader("content-type", TYPES[extname(filePath)] || "application/octet-stream");
      createReadStream(filePath).pipe(res);
      return;
    }
  } catch {
    // Fall back to SPA index
  }

  const indexPath = join(ROOT, "index.html");
  try {
    await stat(indexPath);
    res.statusCode = 200;
    res.setHeader("content-type", "text/html; charset=utf-8");
    createReadStream(indexPath).pipe(res);
  } catch {
    res.statusCode = 404;
    res.end("not found");
  }
}

const server = createServer(async (req, res) => {
  if (!req.url) {
    res.statusCode = 400;
    res.end("bad request");
    return;
  }

  const targetPath = toMempoolPath(new URL(req.url, "http://localhost").pathname);
  if (targetPath) {
    await proxy(req, res, targetPath);
    return;
  }

  await serveFile(req, res);
});

server.listen(PORT, "0.0.0.0", () => {
  const here = fileURLToPath(new URL(".", import.meta.url));
  console.log(`am-i-exposed server running on :${PORT}`);
  console.log(`root=${ROOT} from ${here}`);
});
EOF

  sudo mv /var/cache/raspiblitz/${APPID}-server.mjs "${APP_CODE_DIR}/raspiblitz-server.mjs" || exit 1
  sudo chown "${APP_USER}:${APP_USER}" "${APP_CODE_DIR}/raspiblitz-server.mjs" || exit 1

  echo "# Creating systemd service"
  cat >/var/cache/raspiblitz/${APP_SERVICE}.service <<EOF
[Unit]
Description=am-i-exposed web UI
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=${APP_CODE_DIR}
Environment=PORT=${APP_PORT}
Environment=ROOT_DIR=${APP_CODE_DIR}/out
Environment=MEMPOOL_BASE=http://127.0.0.1:8999
ExecStart=/usr/bin/node ${APP_CODE_DIR}/raspiblitz-server.mjs
User=${APP_USER}
Group=${APP_USER}
Restart=on-failure
RestartSec=10
TimeoutSec=120

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true
ReadWritePaths=${APP_CODE_DIR} ${APP_DATA_DIR}

[Install]
WantedBy=multi-user.target
EOF

  sudo mv /var/cache/raspiblitz/${APP_SERVICE}.service /etc/systemd/system/${APP_SERVICE}.service || exit 1
  sudo chown root:root /etc/systemd/system/${APP_SERVICE}.service || exit 1

  echo "# Updating firewall"
  sudo ufw allow ${APP_PORT} comment "${APPID} WebUI" || exit 1

  /home/admin/config.scripts/blitz.conf.sh set ${APPID} "on"

  sudo systemctl daemon-reload
  sudo systemctl enable ${APP_SERVICE} || exit 1
  sudo systemctl restart ${APP_SERVICE} || exit 1

  echo "# OK - ${APP_SERVICE}.service installed and running"
  echo "# Open: http://$(hostname -I | awk '{print $1}'):${APP_PORT}"
  exit 0
fi

if [ "$1" = "update" ]; then
  if [ "${isInstalled}" != "1" ]; then
    echo "# ${APP_SERVICE} not installed"
    exit 1
  fi

  echo "# Updating ${APPID}"
  cd "${APP_CODE_DIR}" || exit 1
  sudo -u "${APP_USER}" git fetch --tags || exit 1
  sudo -u "${APP_USER}" git reset --hard "${GITHUB_COMMIT}" || exit 1
  sudo -u "${APP_USER}" npx -y "pnpm@${PNPM_VERSION}" install || exit 1
  sudo -u "${APP_USER}" npx -y "pnpm@${PNPM_VERSION}" build || exit 1

  sudo systemctl restart ${APP_SERVICE} || exit 1
  echo "# OK - ${APPID} updated"
  exit 0
fi

if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# Uninstalling ${APPID}"

  sudo systemctl stop ${APP_SERVICE} 2>/dev/null
  sudo systemctl disable ${APP_SERVICE} 2>/dev/null
  sudo rm -f /etc/systemd/system/${APP_SERVICE}.service
  sudo systemctl daemon-reload

  sudo ufw deny ${APP_PORT}

  /home/admin/config.scripts/blitz.conf.sh set ${APPID} "off"

  if [ "$(echo "$*" | grep -c 'delete-data')" -gt 0 ]; then
    echo "# delete-data specified: removing app-data directory"
    sudo rm -rf "${APP_DATA_DIR}"
  fi

  sudo userdel -rf "${APP_USER}" 2>/dev/null

  echo "# OK - ${APPID} removed"
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
