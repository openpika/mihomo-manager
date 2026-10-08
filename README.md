# Mihomo Manager

适用于 Ubuntu 无桌面服务器的 Mihomo / [mihomo-tui](https://github.com/WangZhongDian/mihomo-tui) 辅助安装、配置检查和 GEO 数据修复脚本。适合腾讯云等经 SSH 管理的服务器。

> 这是第三方辅助脚本，不属于 Mihomo 或 mihomo-tui 官方项目。**首次使用前请阅读脚本，建议先在测试机验证。** 不默认开启 TUN，不修改 SSH、防火墙或系统路由。

## 快速开始

```bash
git clone https://github.com/openpika/mihomo-manager.git
cd mihomo-manager
bash mihomo-manager.sh menu
```

首次安装（需要 sudo）：

```bash
sudo bash mihomo-manager.sh install
```

已经安装 mihomo / mihomo-tui 的机器上，脚本会尽量复用程序。安装完成后，用获授权的普通用户启动交互 TUI：

```bash
bash mihomo-manager.sh tui
```

如果出现 IPC 权限不足：

```bash
sudo mihomo-tui grant_operator "$USER"
newgrp mihomo-tui
```

新登录 SSH 会话也可刷新组权限。

## 主要命令

| 命令 | 用途 |
| --- | --- |
| `sudo bash mihomo-manager.sh install` | 安装或复用 TUI 和内核 |
| `sudo bash mihomo-manager.sh repair` | 备份并修复 GEO 路径、验证配置 |
| `sudo bash mihomo-manager.sh check` | 校验当前 TUI 内核配置 |
| `bash mihomo-manager.sh tui` | 打开终端交互界面 |
| `bash mihomo-manager.sh status` | 查看进程、端口、GEO 文件 |
| `sudo bash mihomo-manager.sh diagnose` | 输出配置检查和后台日志 |
| `bash mihomo-manager.sh test` | 测试本地代理连通 GitHub |
| `bash mihomo-manager.sh import-file /path/to/sub.yaml` | 从本地文件导入订阅 |
| `bash mihomo-manager.sh menu` | 打开交互菜单 |

导入 HTTPS 订阅可使用 `bash mihomo-manager.sh import 'https://...'`，**但 URL 可能进入 Shell 历史和进程参数，请优先在 TUI 内输入敏感订阅地址**。导入后仍可能需要到 TUI 的「订阅池」启用和应用订阅，并在首页启动内核。

## Shell 代理开关

脚本不会永久改变 Shell 环境变量；如需让**当前终端**走代理：

```bash
eval "$(bash mihomo-manager.sh env-on)"
curl -I --max-time 15 https://github.com
```

关闭：

```bash
eval "$(bash mihomo-manager.sh env-off)"
```

默认 HTTP/Mixed 端口 7892、SOCKS5 端口 7891。**使用前检查 TUI 中实际端口**。Shell 变量通常不会自动影响 systemd 后台服务；也不等于全系统流量接管。

## GEO 下载失败 / 目录不一致

本项目专门处理下面这种情况：

```text
Can't find GeoIP.dat, start download
context deadline exceeded
rules[...] GEOIP,CN,DIRECT error
```

TUI 启动内核的工作目录可能是 `/var/lib/mihomo-tui`，而资源管理下载的文件可能在 `/var/lib/mihomo-tui/mihomo`。先执行：

```bash
sudo bash mihomo-manager.sh repair
```

脚本会查找已有 GEO 数据，将找到的文件复制到内核工作目录；如果不存在再尝试下载，失败不会覆盖已有文件。**如果配置指向 `geoip-lite.dat`，请检查配置中的 GEO URL：不能假定普通 `geoip.dat` 总能替代 lite 版本。**

服务器无法连接 GitHub 时，可以在本地电脑从 [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat/releases) 下载 `geoip.dat` 和 `geosite.dat`，经 SCP 上传到服务器的 `/tmp` 后再次执行 `repair`。

## 排查顺序

1. `bash mihomo-manager.sh status`：确认 TUI daemon、mihomo 进程、代理端口是否真正启动。
2. `sudo bash mihomo-manager.sh check`：检查 GEO 数据或配置加载失败。
3. `sudo bash mihomo-manager.sh diagnose`：查看日志。
4. TUI 的「订阅」确认已解析节点；在「订阅池」启用和应用；在首页检查内核状态。
5. `bash mihomo-manager.sh test`：验证代理是否可访问外部网站。

**注意：** 有 `mihomo-tui server` 进程并不代表 mihomo 内核正常工作。默认配置可能包含 HTTP 7890、SOCKS 7891、Mixed 7892、Controller 9090；以实际配置为准。

## 安全和局限

- 脚本会在 `/var/backups/mihomo-manager` 保存配置备份，可能包含敏感订阅或节点数据，应限制访问。
- 默认不开放 7890/7891/7892/9090 到公网，也不会为你配置腾讯云安全组。
- 安装功能需要访问官方 GitHub Releases；网络受阻时需要离线下载。
- 安装/修复不保证所有订阅都可直接使用，TUI 中仍可能需要手动应用订阅池并启动内核。
- 不默认接管系统路由；远程 SSH 服务器上不建议贸然开启 TUN。
- 请遵守所在地区的法律法规和云服务商的使用条款。

## 相关项目

- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)
- [WangZhongDian/mihomo-tui](https://github.com/WangZhongDian/mihomo-tui)
