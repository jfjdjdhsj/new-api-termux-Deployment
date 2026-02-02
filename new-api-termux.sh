#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/root/new-api"
WEB_DIR="/root/new-api/web"
NODE_VER="20"
NVM_VER="v0.39.7"

log(){ echo -e "\n\033[1;32m[+] $*\033[0m"; }
skip(){ echo -e "\033[1;33m[skip] $*\033[0m"; }
warn(){ echo -e "\n\033[1;33m[!] $*\033[0m"; }
err(){ echo -e "\n\033[1;31m[✗] $*\033[0m"; }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "请用 root 运行（你在 proot Ubuntu 里一般就是 root）"
    exit 1
  fi
}

is_installed() { dpkg -s "$1" >/dev/null 2>&1; }

apt_install_one() {
  local pkg="$1"
  if is_installed "$pkg"; then
    skip "$pkg 已安装"
    return 0
  fi
  log "安装 $pkg"
  if apt-get install -y "$pkg"; then
    return 0
  else
    warn "$pkg 安装失败，已跳过（不影响脚本继续）"
    return 0
  fi
}

write_tsinghua_sources() {
  log "写入清华源 /etc/apt/sources.list"
  tee /etc/apt/sources.list > /dev/null <<'EOF'
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ questing main universe multiverse
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ questing-updates main universe multiverse
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ questing-security main universe multiverse
EOF
}

install_base_deps() {
  log "apt update"
  apt-get update -y

  log "安装基础依赖（逐个装，失败就跳过）"
  apt_install_one git
  apt_install_one curl
  apt_install_one ca-certificates
  apt_install_one build-essential

  apt_install_one pkgconf
  apt_install_one pkg-config
}

ensure_go() {
  if command -v go >/dev/null 2>&1; then
    log "检测到 Go：$(go version)"
    skip "Go 已存在，跳过安装"
    return 0
  fi

  warn "系统未检测到 go，尝试 apt 安装 golang-go"
  if apt-get install -y golang-go; then
    log "Go 安装完成：$(go version || true)"
    return 0
  fi

  warn "apt 安装 golang-go 失败，改用官方 Go tarball（arm64）安装到 /usr/local/go"
  GO_VER="1.22.11"
  cd /tmp
  rm -f "go${GO_VER}.linux-arm64.tar.gz"
  curl -L "https://go.dev/dl/go${GO_VER}.linux-arm64.tar.gz" -o "go${GO_VER}.linux-arm64.tar.gz"

  rm -rf /usr/local/go
  tar -C /usr/local -xzf "go${GO_VER}.linux-arm64.tar.gz"

  if ! grep -q '/usr/local/go/bin' /root/.bashrc 2>/dev/null; then
    echo 'export PATH=/usr/local/go/bin:$PATH' >> /root/.bashrc
  fi
  export PATH=/usr/local/go/bin:$PATH

  log "Go tarball 安装完成：$(go version)"
}

install_nvm_node() {
  export HOME="/root"
  if [ -d "/root/.nvm" ]; then
    skip "nvm 已存在"
  else
    log "安装 nvm (${NVM_VER})"
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VER}/install.sh" | bash
  fi

  # shellcheck disable=SC1091
  . "/root/.nvm/nvm.sh"

  if nvm ls "${NODE_VER}" | grep -q "v${NODE_VER}"; then
    skip "Node ${NODE_VER} 已安装"
  else
    log "安装 Node ${NODE_VER}"
    nvm install "${NODE_VER}"
  fi

  nvm use "${NODE_VER}" >/dev/null
  log "Node / npm 版本："
  node -v
  npm -v
}

set_node_memory() {
  if [ -f /etc/profile.d/node_options.sh ] && grep -q max-old-space-size /etc/profile.d/node_options.sh; then
    skip "NODE_OPTIONS 已设置"
    export NODE_OPTIONS="--max-old-space-size=8192"
    return 0
  fi
  log "设置 Node 内存（防前端构建 OOM）"
  export NODE_OPTIONS="--max-old-space-size=8192"
  echo 'export NODE_OPTIONS="--max-old-space-size=8192"' > /etc/profile.d/node_options.sh
}

clone_or_update_repo() {
  log "准备 new-api 仓库"
  if [ -d "${APP_DIR}/.git" ]; then
    skip "仓库已存在，执行 git pull"
    cd "${APP_DIR}"
    git pull || warn "git pull 失败（可忽略，脚本继续）"
  else
    log "克隆仓库到 ${APP_DIR}"
    rm -rf "${APP_DIR}"
    git clone https://github.com/Calcium-Ion/new-api.git "${APP_DIR}"
  fi
}

go_deps() {
  log "Go 依赖：go mod download（已下载会自动跳过）"
  cd "${APP_DIR}"
  go mod download
}

npm_install_web() {
  log "前端依赖：存在 node_modules 就跳过"
  cd "${WEB_DIR}"

  # shellcheck disable=SC1091
  . "/root/.nvm/nvm.sh"
  nvm use "${NODE_VER}" >/dev/null

  if [ -d "node_modules" ]; then
    skip "node_modules 已存在，跳过 npm install"
    return 0
  fi

  if npm install; then
    log "npm install 成功"
  else
    warn "npm install 失败，改用 --legacy-peer-deps"
    npm install --legacy-peer-deps
  fi
}

patch_semi_css() {
  cd "${WEB_DIR}"
  if [ ! -f "src/index.jsx" ]; then
    warn "未找到 src/index.jsx，跳过 semi-ui patch（可能项目结构变化）"
    return 0
  fi

  if grep -q "/@fs/root/new-api/web/node_modules/@douyinfe/semi-ui/dist/css/semi.min.css" src/index.jsx; then
    skip "semi-ui 路径已修复"
    return 0
  fi

  warn "应用 semi-ui CSS 路径修复"
  sed -i "s|@douyinfe/semi-ui/dist/css/semi\.css|@douyinfe/semi-ui/dist/css/semi.min.css|g" src/index.jsx || true
  sed -i "s|@douyinfe/semi-ui/dist/css/semi\.min\.css|/@fs/root/new-api/web/node_modules/@douyinfe/semi-ui/dist/css/semi.min.css|g" src/index.jsx || true
}

ensure_antd() {
  cd "${WEB_DIR}"
  if npm ls antd >/dev/null 2>&1; then
    skip "antd 已存在"
    return 0
  fi
  warn "安装 antd@5（仅缺失时安装）"
  npm i antd@5 --legacy-peer-deps
}

build_web() {
  cd "${WEB_DIR}"

  if [ -d "dist" ]; then
    skip "检测到 web/dist 已存在，跳过 npm run build"
    return 0
  fi

  log "构建前端：npm run build"
  npm run build
}

print_done() {
  log "✅ 安装/编译已完成（未自动启动）"
  echo -e "\n接下来你手动启动："
  echo -e "  cd /root/new-api && go run main.go"
  echo -e "\n（提示：如果你关闭终端就会停，建议后面用 screen/tmux/nohup 守护）"
}

main() {
  need_root

  write_tsinghua_sources
  install_base_deps

  ensure_go
  install_nvm_node
  set_node_memory

  clone_or_update_repo
  go_deps
  npm_install_web
  patch_semi_css
  ensure_antd
  build_web

  # ✅ 不自动启动，改为提示完成
  print_done
}

main "$@"
