##视频教程

https://b23.tv/djSE4hl
自动安装脚本
```bash
apt update && apt install -y curl && bash -c "$(curl -fsSL https://raw.githubusercontent.com/jfjdjdhsj/new-api-termux-Deployment/refs/heads/main/new-api-termux.sh)"
```
**⬇️手动部署教程**

# 📦 Termux + proot-distro 部署 new-api（Ubuntu）完整教程

> 适用于 **Termux / Android / proot-distro Ubuntu**

---

## 一、安装 proot-distro

```bash
pkg install -y proot-distro
```

---

二、安装 Ubuntu
```bash
proot-distro install ubuntu
```
---

三、登录 Ubuntu
```bash
proot-distro login ubuntu
```

---

四、切换清华源
```bash
tee /etc/apt/sources.list > /dev/null <<'EOF'
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ questing main universe multiverse
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ questing-updates main universe multiverse
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ questing-security main universe multiverse
EOF
```

---

五、安装系统依赖（Go + Node 基础环境）
```bash
apt update && apt install -y \
  git \
  curl \
  ca-certificates \
  build-essential \
  pkg-config \
  golang \
  nodejs \
  npm
```
> ⚠️ 后面 Node 实际用 nvm 管理的版本，系统自带 node 只是兜底。




---

六、克隆项目
```bash
git clone https://github.com/Calcium-Ion/new-api.git
cd new-api
```

---

七、安装 Node（使用 nvm，强烈推荐）
```bash
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install 20
nvm use 20
node -v
npm -v
```

---

八、设置 Node 内存（防止前端构建 OOM）
```bash
export NODE_OPTIONS="--max-old-space-size=8192"
```

---

九、下载 Go 依赖
```bash
go mod download
```

---

十、安装前端依赖
```bash
cd /root/new-api/web
npm install
```
如果 npm install 报错，使用：
```bash
npm install --legacy-peer-deps
```

---

十一、构建前端（⚠️重点：踩坑集中区）

1️⃣ 第一次构建
```bash
npm run build
```

---

❌ 报错 1：semi-ui CSS 路径不存在

报错信息：

Missing "./dist/css/semi.css" specifier in "@douyinfe/semi-ui"

✅ 修复：
```bash
sed -i "s|@douyinfe/semi-ui/dist/css/semi\.css|@douyinfe/semi-ui/dist/css/semi.min.css|g" src/index.jsx
```
重新构建：
```bash
npm run build
```

---

❌ 报错 2：semi.min.css 仍然无法解析

报错信息：

Missing "./dist/css/semi.min.css" specifier

✅ 修复（使用 Vite fs 绝对路径）：
```bash
sed -i "s|@douyinfe/semi-ui/dist/css/semi\.min\.css|/@fs/root/new-api/web/node_modules/@douyinfe/semi-ui/dist/css/semi.min.css|g" src/index.jsx
```
重新构建：
```bash
npm run build
```

---

❌ 报错 3：缺少 antd 依赖

报错信息：

failed to resolve import "antd"

✅ 修复：
```bash
npm i antd@5 --legacy-peer-deps
```
重新构建：
```bash
npm run build
```

---

✅ 前端构建成功标志

看到类似输出即代表成功：
```bash
✓ xxxx modules transformed
Build completed successfully
```

---

十二、返回主目录并启动服务
```bash
cd ..
go run main.go
```

---

🎉 部署完成

浏览器访问：
```bash
http://127.0.0.1:3000
```
---
