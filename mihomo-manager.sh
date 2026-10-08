#!/usr/bin/env bash
# Mihomo / mihomo-tui bootstrap and repair for Ubuntu (headless server).
set -Eeuo pipefail
TUI_REPO="WangZhongDian/mihomo-tui"
CORE_REPO="MetaCubeX/mihomo"
STATE=/var/lib/mihomo-tui
CORE_CFG="$STATE/mihomo/config.yaml"
TUI_BIN=/usr/local/bin/mihomo-tui
CORE_BIN=/usr/local/bin/mihomo
BACKUP_ROOT=/var/backups/mihomo-manager
PORT_HTTP=7890; PORT_SOCKS=7891; PORT_MIXED=7892
info(){ printf '\033[32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[提示]\033[0m %s\n' "$*" >&2; }
err(){ printf '\033[31m[错误]\033[0m %s\n' "$*" >&2; }
need_root(){ [[ $EUID -eq 0 ]] || { err "请执行 sudo bash $0 $*"; exit 1; }; }
arch(){ case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) err "不支持架构: $(uname -m)"; return 1;; esac; }
req(){ command -v "$1" >/dev/null || { err "缺少命令: $1 (sudo apt-get install $1)"; return 1; }; }
requirements(){ req curl; req python3; req tar; req gzip; req sha256sum; }
tmpdir(){ mktemp -d; }
backup(){
  need_root; local target="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$target"; chmod 700 "$BACKUP_ROOT" "$target"
  for d in /etc/mihomo "$STATE"; do
    if [[ -e "$d" ]]; then mkdir -p "$target$(dirname "$d")"; cp -a "$d" "$target$d"; fi
  done
  info "备份目录: $target"
}
# Only accept exact official release asset URL, obtained from GitHub's release API.
release_asset(){
  local repo="$1" kind="$2" cpu="$3"
  curl --noproxy '*' -fsSL --connect-timeout 8 --max-time 30 \
    "https://api.github.com/repos/$repo/releases/latest" | python3 -c '
import json,sys
obj=json.load(sys.stdin); assets=obj.get("assets",[]); arch=sys.argv[2]; kind=sys.argv[1]
if kind=="tui":
  matches=[x for x in assets if x["name"]=="mihomo-tui-linux-"+arch]
else:
  # Stable Linux amd64 v1 or arm64-v8, avoid alpha and incompatible variants.
  prefix="mihomo-linux-amd64-v1-" if arch=="amd64" else "mihomo-linux-arm64-v8-"
  matches=[x for x in assets if x["name"].startswith(prefix) and x["name"].endswith(".gz")]
if len(matches)!=1: sys.exit("未找到唯一匹配的官方安装包，请手动下载并核对 release")
x=matches[0]
print(x["browser_download_url"])
print(x.get("digest", ""))
' "$kind" "$cpu"
}
get_asset(){
  local kind="$1" repo="$2" cpu="$3" dst="$4" meta url digest
  meta=$(release_asset "$repo" "$kind" "$cpu") || return 1
  url=$(printf '%s\n' "$meta" | sed -n '1p')
  digest=$(printf '%s\n' "$meta" | sed -n '2p')
  [[ "$url" == https://github.com/"$repo"/releases/download/* ]] || { err '异常下载 URL'; return 1; }
  info "下载官方资产: ${url##*/}"
  curl --noproxy '*' -fL --retry 2 --connect-timeout 10 --max-time 180 "$url" -o "$dst" || return 1
  [[ -s "$dst" ]] || return 1
  if [[ "$digest" == sha256:* ]]; then
    printf '%s  %s\n' "${digest#sha256:}" "$dst" | sha256sum -c - >/dev/null || { err 'SHA256 验证失败'; return 1; }
  else
    warn '官方 Release API 未提供 SHA256 digest；请自行核实二进制来源。'
  fi
}
install_tui(){
  need_root; requirements; local cpu t
  cpu=$(arch)
  if command -v mihomo-tui >/dev/null 2>&1; then info "TUI 已安装: $(command -v mihomo-tui)，跳过下载";
  else
    t=$(tmpdir); trap 'rm -rf "$t"' RETURN
    get_asset tui "$TUI_REPO" "$cpu" "$t/tui" || { err '下载失败：可在 Mac 下载官方二进制并用 install-local 安装'; return 1; }
    install -m 755 "$t/tui" "$TUI_BIN"
  fi
  if ! systemctl list-unit-files mihomo-tui.service --no-legend 2>/dev/null | grep -q '^mihomo-tui.service'; then
    "$TUI_BIN" install_service
  fi
  systemctl enable --now mihomo-tui
  local operator="${SUDO_USER:-${USER:-ubuntu}}"
  if [[ "$operator" != root ]] && id "$operator" >/dev/null 2>&1; then
    "$TUI_BIN" grant_operator "$operator" || warn "grant_operator 失败，请检查权限"
    warn "如首次授权，退出 SSH 并重新登录，或执行 newgrp mihomo-tui"
  fi
  info 'TUI 服务已启动；用普通用户执行 mihomo-tui 进入界面'
}
install_local(){
  need_root; local file="${1:-}" cpu name
  [[ -f "$file" && -s "$file" ]] || { err '用法: install-local /path/to/mihomo-tui-linux-amd64'; return 1; }
  cpu=$(arch); name=$(basename "$file")
  [[ "$name" == "mihomo-tui-linux-$cpu" ]] || { err "文件名/架构不匹配: 需要 mihomo-tui-linux-$cpu"; return 1; }
  if command -v mihomo-tui >/dev/null 2>&1; then warn '已安装 TUI，不覆盖；直接运行 install'; return 0; fi
  install -m 755 "$file" "$TUI_BIN"; info "已安装 $TUI_BIN"
}
install_core(){
  need_root; requirements; local cpu t
  cpu=$(arch)
  if command -v mihomo >/dev/null 2>&1; then info "内核已安装: $(command -v mihomo)，跳过下载"; return 0; fi
  t=$(tmpdir); trap 'rm -rf "$t"' RETURN
  get_asset core "$CORE_REPO" "$cpu" "$t/core.gz" || { err '下载失败：请通过 TUI 资源管理安装内核或离线导入'; return 1; }
  gzip -t "$t/core.gz" || return 1
  gzip -cd "$t/core.gz" > "$t/mihomo"
  install -m 755 "$t/mihomo" "$CORE_BIN"
  "$CORE_BIN" -v
}
# Geodata is expected by -d /var/lib/mihomo-tui, NOT only under .../mihomo/.
geo_dir(){ echo "$STATE"; }
geo_one(){
  local name="$1" target="$STATE/$1" candidate src t url
  [[ -s "$target" ]] && { info "$name 已存在，跳过"; return 0; }
  for candidate in "$STATE/mihomo/$name" "/etc/mihomo/$name" "/tmp/$name"; do
    if [[ -s "$candidate" ]]; then
      install -m 644 "$candidate" "$target"; info "已复用本地 $candidate"; return 0
    fi
  done
  url="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/$name"
  t=$(mktemp "$STATE/.${name}.XXXXXX")
  info "下载 $name（失败不会覆盖已有文件）"
  if curl --noproxy '*' -fL --retry 2 --connect-timeout 8 --max-time 45 "$url" -o "$t" && [[ $(stat -c %s "$t") -gt 100000 ]]; then
    chmod 644 "$t"; mv -f "$t" "$target"; info "$name 下载完成"; return 0
  fi
  rm -f "$t"; warn "$name 无法下载：请在 Mac 下载后 scp 到 /tmp/$name，再运行 repair"; return 1
}
geo_repair(){
  need_root; mkdir -p "$STATE"; chmod 755 "$STATE"
  local fail=0
  geo_one geoip.dat || fail=1
  geo_one geosite.dat || fail=1
  # Do not pretend geoip.dat is a valid geoip-lite.dat. Existing custom geox-url may still require that file.
  if [[ -f "$CORE_CFG" ]]; then
    if grep -Eq 'geoip-lite\.dat' "$CORE_CFG"; then warn '配置引用 geoip-lite.dat：标准 geoip.dat 不一定能替代它，请检查 geox-url'; fi
  fi
  return "$fail"
}
validate(){
  need_root; req mihomo
  [[ -f "$CORE_CFG" ]] || { warn "未找到内核配置：$CORE_CFG，先在 TUI 导入订阅、应用订阅池并启动内核"; return 1; }
  mihomo -t -d "$STATE" -f "$CORE_CFG"
}
status(){
  echo '===== 版本 ====='; command -v mihomo-tui >/dev/null && mihomo-tui version || true
  command -v mihomo >/dev/null && mihomo -v || true
  echo '===== systemd ====='; systemctl is-active mihomo-tui || true
  echo '===== 进程 ====='; pgrep -a -x mihomo || true
  echo '===== 监听端口 ====='; ss -lntp 2>/dev/null | grep -E ':(7890|7891|7892|9090)\b' || true
  echo '===== GEO 文件 ====='; ls -lh "$STATE"/{geoip.dat,geosite.dat} 2>/dev/null || true
  echo '===== 配置 ====='; [[ -f "$CORE_CFG" ]] && grep -E '^(port|mixed-port|socks-port|external-controller|allow-lan|mode):' "$CORE_CFG" || true
  echo '===== 提示 ====='; echo "仅有 TUI daemon 不等于内核已启动。内核由 TUI 控制；请在首页启动。"
}
proxy_test(){
  req curl
  echo '===== 本机代理 HTTP 测试（请先确认 TUI 里端口） ====='
  curl --noproxy '' -sS -I -x "http://127.0.0.1:$PORT_MIXED" --max-time 15 https://github.com | head -n 8
}
proxy_env(){
  cat <<'ENV'
# 在当前 shell 中启用：eval "$(bash mihomo-manager.sh env-on)"
export HTTP_PROXY=http://127.0.0.1:7892
export HTTPS_PROXY=http://127.0.0.1:7892
export ALL_PROXY=socks5h://127.0.0.1:7891
export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTPS_PROXY"
export all_proxy="$ALL_PROXY"
ENV
}
env_on(){ cat <<'ENV'
export HTTP_PROXY=http://127.0.0.1:7892 HTTPS_PROXY=http://127.0.0.1:7892 ALL_PROXY=socks5h://127.0.0.1:7891
export http_proxy="$HTTP_PROXY" https_proxy="$HTTPS_PROXY" all_proxy="$ALL_PROXY"
ENV
}
env_off(){ cat <<'ENV'
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
ENV
}
import_sub(){
  req mihomo-tui
  local source="${1:-}" kind="${2:-url}"
  [[ -n "$source" ]] || { err '用法: import URL 或 import-file /path/to/sub.yaml'; return 1; }
  if [[ "$kind" == url ]]; then
    [[ "$source" == https://* ]] || { err '仅接受 HTTPS 订阅 URL'; return 1; }
    mihomo-tui subscription import --url "$source"
  else
    mihomo-tui subscription import --file "$source"
  fi
  warn '导入后仍需在 TUI 订阅池启用/接管，代理页面才能显示节点'
}
repair(){
  need_root; backup
  geo_repair || warn '部分 GEO 文件仍缺失；可在 Mac 下载后传入 /tmp，再次执行 repair'
  if [[ -f "$CORE_CFG" ]]; then
    validate || { err '配置验证失败。未重启内核、未覆盖订阅，请检查 GeoIP 下载日志'; return 1; }
  else warn '尚无 TUI 生成的配置文件；请进入 TUI 导入并应用订阅'; fi
  info '检查完成。请在 TUI 首页启动/重启内核以应用资源。'
}
health(){
  status
  echo '===== 非破坏性排查 ====='
  if [[ $EUID -eq 0 && -f "$CORE_CFG" ]]; then validate || true; else warn '如需配置校验：sudo bash mihomo-manager.sh check'; fi
  echo '===== 最近 daemon 日志 ====='; journalctl -u mihomo-tui -n 20 --no-pager 2>/dev/null || true
}
usage(){ cat <<'HELP'
Mihomo 管理脚本（面向 Ubuntu headless 服务器；默认不操作 TUN/路由/防火墙）
  sudo bash mihomo-manager.sh install            首次安装 TUI + 内核（已安装则跳过）
  sudo bash mihomo-manager.sh install-local FILE 离线安装指定架构的 TUI 二进制
  sudo bash mihomo-manager.sh repair             备份、修复 GEO 路径、验证现有配置
  sudo bash mihomo-manager.sh check              验证 TUI 内核配置
  bash mihomo-manager.sh tui                     进入 TUI（需授权的 ubuntu 用户）
  bash mihomo-manager.sh status                  检查进程/端口/目录
  sudo bash mihomo-manager.sh diagnose           深入诊断
  bash mihomo-manager.sh test                    用混合端口测试 GitHub
  bash mihomo-manager.sh import 'https://...'    导入订阅（命令行历史可能记录 URL）
  bash mihomo-manager.sh import-file PATH        离线导入订阅
  eval "$(bash mihomo-manager.sh env-on)"           当前 Shell 开启代理
  eval "$(bash mihomo-manager.sh env-off)"          当前 Shell 关闭代理
  bash mihomo-manager.sh menu                    交互菜单
提醒：TUI 是管理器；内核需在 TUI 首页启动。订阅导入后还需启用订阅池。
HELP
}
menu(){
  local pick
  while true; do
    printf '\n=== Mihomo Manager ===\n1 安装/复用\n2 修复 GEO 并检查\n3 状态\n4 进入 TUI\n5 测试代理\n6 诊断\n7 显示代理变量启用方法\n0 退出\n选择: '
    read -r pick || break
    case "$pick" in
      1) install_all;; 2) repair;; 3) status;; 4) run_tui;; 5) proxy_test;; 6) health;; 7) usage;; 0) break;; *) warn '无效选项';;
    esac
  done
}
run_tui(){ req mihomo-tui; [[ $EUID -ne 0 ]] || warn '更推荐用授权的 ubuntu 用户而不是 root 进入 TUI'; exec mihomo-tui; }
install_all(){ need_root; backup; install_tui; install_core || warn '内核安装失败；可在 TUI 中安装/选择现有内核'; geo_repair || warn 'GEO 下载失败，可在 Mac 离线下载上传后 repair'; info '安装阶段结束。切回普通用户运行 mihomo-tui，导入订阅并启动内核'; }
main(){
  case "${1:-menu}" in
    install) install_all;; install-local) install_local "${2:-}";; repair) repair;; check) validate;; tui) run_tui;;
    status) status;; diagnose) health;; test) proxy_test;; import) import_sub "${2:-}" url;;
    import-file) import_sub "${2:-}" file;; env-on) env_on;; env-off) env_off;; env) proxy_env;;
    menu) menu;; help|-h|--help) usage;; *) usage; exit 2;;
  esac
}
main "$@"
