# Xray-AlpineInstall（amd64 only）

Alpine Linux 用的 Xray 安装脚本，改自 [XTLS/Xray-install](https://github.com/XTLS/Xray-install) 的官方 Alpine 脚本。

**改动点**：去掉了端侧 `unzip` 解压环节。本仓库通过 GitHub Actions 定时跟随上游 [XTLS/Xray-core](https://github.com/XTLS/Xray-core) 最新版，在 CI 侧解压 `Xray-linux-64.zip`，
把裸二进制（`xray`、`geoip.dat`、`geosite.dat`）发布到本仓库的 Release Assets，安装脚本直接 `curl` 下载。
目的是让 64MB 这种小内存机器也能安装，避免解压时 OOM。

## 适用范围

- 仅 `amd64` / `x86_64`，其他架构直接报错退出
- Alpine（或 Gentoo），且使用 OpenRC（要求 `rc-service` 存在）
- 必须以 root 运行
- 需要能直连 `github.com`（Release 直链 + OpenRC service 文件均托管在 GitHub）

## 前置依赖

脚本只需要 `curl`，缺失时会自动 `apk add curl`。但注意：下载本脚本本身就需要先有 `curl` 或 `wget`，
所以全新系统上请先手动 `apk add curl`（见下文使用方法）。其余均为 Alpine 默认自带：

| 依赖 | 用途 | 说明 |
| --- | --- | --- |
| `curl` | 下载二进制与 service 文件 | 缺失时自动安装 |
| `sha256sum` | 校验下载文件 | busybox 自带 |
| `pgrep` | 检测 xray 是否在运行 | busybox 自带 |
| `openrc`（`rc-service` / `rc-update`） | 注册与启停服务 | 缺失则报错退出，需手动安装 |
| `ash`、`awk`、`mktemp`、`install` | 脚本自身 | busybox/coreutils 自带 |

注意：脚本不再需要 `unzip`。

## 使用方法

先把脚本下载到机器上（Alpine 刚装好可能既没有 `curl` 也没有 `wget`，先装一个）：

```sh
apk add curl
curl -fL -O https://raw.githubusercontent.com/bbw3000/Xray-AlpineInstall/main/install-release.sh
# 或者用 wget：
# apk add wget
# wget https://raw.githubusercontent.com/bbw3000/Xray-AlpineInstall/main/install-release.sh
```

然后以 root 执行：

```sh
ash install-release.sh
```

脚本会依次执行：检查系统与架构 → 补装 `curl` → 从本仓库最新 Release 下载三个裸文件及其 `.sha256` 并校验 →
如 xray 在运行则先停服 → 安装到系统路径 → 初始化配置目录与日志 → 下载 OpenRC service 文件 → 输出结果。

安装完成后按提示执行：

```sh
rc-update add xray
rc-service xray start
```

### 换用 fork 仓库

默认下载源是本仓库的 Release。如 fork 后自用，可不改脚本，用环境变量覆盖：

```sh
REPO=你的用户名/Xray-AlpineInstall ash install-release.sh
```

## 安装后的文件布局

- `/usr/local/bin/xray` — 主程序
- `/usr/local/share/xray/geoip.dat`、`geosite.dat` — 路由数据
- `/usr/local/etc/xray/*.json` — 分片空配置（仅首次安装时生成，已有则不动）
- `/var/log/xray/access.log`、`error.log` — 日志（属主 `nobody`）
- `/etc/init.d/xray` — OpenRC 服务（取自上游 Xray-install 仓库）

卸载依赖提示：装完后如需清理，可执行脚本末尾输出的 `apk del curl`（确认无其他程序依赖 `curl` 再删）。

## 自动更新机制

`.github/workflows/extract-xray.yml` 每 6 小时检查一次上游最新 tag：

1. 本仓库已存在对应 `xray-<上游tag>` Release 则跳过；
2. 否则下载官方 `Xray-linux-64.zip{,.dgst}`，按官方 dgst 校验；
3. CI 侧解压，`chmod +x`，生成各文件的 `.sha256` 与 `version`；
4. 发布到本仓库 Release，tag 形如 `xray-v26.3.27`。

脚本始终从 `releases/latest/download` 取最新版，因此服务端无需任何操作即可跟随上游。

上游发版后想立即同步，或想补发某个旧版本，可去 Actions 页手动触发 `Extract Xray`，在 `version` 输入框填上游 tag（如 `v26.3.27`），留空则取最新。
