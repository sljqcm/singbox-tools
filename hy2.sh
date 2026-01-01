#!/bin/bash
export LANG=en_US.UTF-8

# ======================================================================
# Sing-box hy2 一键脚本
# 作者：littleDoraemon
# 说明：
#   - 支持自动 / 交互模式
#   - 支持跳跃端口
#   - 支持环境变量：PORT （必填） / NGINX_PORT（必填） / UUID / RANGE_PORTS / NODE_NAME
#  
#  1、安装方式（2种）
#     1.1 交互式菜单安装：
#     curl -fsSL https://raw.githubusercontent.com/jyucoeng/singbox-tools/refs/heads/main/hy2.sh -o hy2.sh && chmod +x hy2.sh && ./hy2.sh
#    
#     1.2 非交互式全自动安装:
#     PORT=31020  NGINX_PORT=31039 RANGE_PORTS=40000-41000 NODE_NAME="小叮当的节点" bash <(curl -Ls https://raw.githubusercontent.com/jyucoeng/singbox-tools/refs/heads/main/hy2.sh)
#
# 
#  
# ======================================================================

AUTHOR="littleDoraemon"
VERSION="1.0.4(2025-12-31)"


SINGBOX_VERSION="1.12.13"

# ======================= 路径定义 =======================
SERVICE_NAME="sing-box-hy2"

work_dir="/etc/sing-box"
config_dir="$work_dir/config.json"
client_dir="$work_dir/url.txt"

sub_file="$work_dir/sub.txt"
sub_port_file="$work_dir/sub.port"
range_port_file="$work_dir/range_ports"

node_name_file="$work_dir/node_name"


sub_nginx_conf="$work_dir/singbox_hy2_sub.conf"



# NAT comment
NAT_COMMENT="hy2_jump"

# ======================= UI 输出 =======================
re="\033[0m"
white(){ echo -e "\033[1;37m$1\033[0m"; }
red(){ echo -e "\e[1;91m$1\033[0m"; }
green(){ echo -e "\e[1;32m$1\033[0m"; }
yellow(){ echo -e "\e[1;33m$1\033[0m"; }
blue(){ echo -e "\e[1;34m$1\033[0m"; }
purple(){ echo -e "\e[1;35m$1\033[0m"; }
err(){ red "[错误] $1" >&2; }

gradient() {
    local text="$1"
    local colors=(196 202 208 214 220 190 82 46 51 39 33)
    local i=0
    for ((n=0;n<${#text};n++)); do
        printf "\033[38;5;${colors[i]}m%s\033[0m" "${text:n:1}"
        i=$(( (i+1)%${#colors[@]} ))
    done
    echo
}

red_input() { printf "\e[1;91m%s\033[0m" "$1"; }


# ======================= 统一退出 =======================
exit_script() {
    echo ""
    green "感谢使用本脚本,再见👋"
    echo ""
    exit 0
}


# ======================= pause（tuic5 同款） =======================
pause_return() {
    echo ""
    read -n 1 -s -r -p "按任意键返回菜单..."
    echo ""
}

# ======================= Root 检查 =======================
if [[ $EUID -ne 0 ]]; then
    err "请使用 root 权限运行脚本"
    exit 1
fi

# ======================= 基础工具 =======================
command_exists(){ command -v "$1" >/dev/null 2>&1; }

is_valid_port(){
    [[ "$1" =~ ^[0-9]+$ && "$1" -ge 1 && "$1" -le 65535 ]]
}

is_port_occupied(){
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    # ss：兼容 IPv4 / IPv6 / [::]:PORT / 0.0.0.0:PORT
    ss -tuln | grep -qE "[:.]${port}\b"
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tuln | grep -qE "[:.]${port}\b"
  else
    # 理论兜底：无 ss / netstat 时认为未占用
    return 1
  fi
}

# ======================= 端口输入 & 校验（通用） =======================
prompt_valid_port() {
    local var_name="$1"     # 变量名，如 PORT / NGINX_PORT
    local prompt_text="$2"  # 提示文案
    local port

    # 取现有值（ENV 或上游赋值）
    port="${!var_name}"

    while true; do
        if [[ -z "$port" ]]; then
            read -rp "$(red_input "$prompt_text")" port
        fi

        if ! is_valid_port "$port"; then
            red "端口无效，请输入 1-65535 之间的数字"
            port=""
            continue
        fi

        if is_port_occupied "$port"; then
            red "端口 $port 已被占用，请重新输入"
            port=""
            continue
        fi

        break
    done

    # 回写到指定变量名
    printf -v "$var_name" '%s' "$port"
}


is_valid_uuid(){
    [[ "$1" =~ ^[a-fA-F0-9]{8}-([a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$ ]]
}

urlencode(){
    printf "%s" "$1" | jq -sRr @uri
}

urldecode(){
    printf '%b' "${1//%/\\x}"
}

# ======================= QR（在线） =======================
generate_qr() {
    local link="$1"
    [[ -z "$link" ]] && return
    yellow "二维码链接："
    echo "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${link}"
}

# ======================= 公网 IP 获取 =======================
get_public_ip() {
    local ip
    local sources=(
        "curl -4 -fs https://api.ipify.org"
        "curl -4 -fs https://ipv4.icanhazip.com"
        "curl -4 -fs https://ip.sb"
        "curl -4 -fs https://checkip.amazonaws.com"
    )

    for src in "${sources[@]}"; do
        ip=$(eval "$src" 2>/dev/null)
        [[ -n "$ip" ]] && { echo "$ip"; return; }
    done

    local sources6=(
        "curl -6 -fs https://api64.ipify.org"
        "curl -6 -fs https://ipv6.icanhazip.com"
    )

    for src in "${sources6[@]}"; do
        ip=$(eval "$src" 2>/dev/null)
        [[ -n "$ip" ]] && { echo "$ip"; return; }
    done
}


get_ipv4() { 
    local ip
    local sources=(
        "curl -4 -fs https://api.ipify.org"
        "curl -4 -fs https://ipv4.icanhazip.com"
        "curl -4 -fs https://ip.sb"
        "curl -4 -fs https://checkip.amazonaws.com"
    )

    for src in "${sources[@]}"; do
        ip=$(eval "$src" 2>/dev/null)
        [[ -n "$ip" ]] && { echo "$ip"; return; }
    done
 }

 get_ipv6() { 
   local ip
   local sources6=(
        "curl -6 -fs https://api64.ipify.org"
        "curl -6 -fs https://ipv6.icanhazip.com"
    )

    for src in "${sources6[@]}"; do
        ip=$(eval "$src" 2>/dev/null)
        [[ -n "$ip" ]] && { echo "$ip"; return; }
    done
 }


detect_nginx_conf_dir() {
  if [[ "$INIT_SYSTEM" == "openrc" ]]; then
    echo "/etc/nginx/http.d"
  else
    echo "/etc/nginx/conf.d"
  fi
}


detect_init() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    INIT_SYSTEM="systemd"
  elif command -v rc-service >/dev/null 2>&1; then
    INIT_SYSTEM="openrc"
  else
    red "无法识别 init 系统"
    exit 1
  fi
}




service_enable() {
  local svc="$1"
  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    systemctl enable "$svc"
  else
    rc-update add "$svc" default 2>/dev/null || rc-update add "$svc" boot
  fi
}

service_start() {
  local svc="$1"
  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    systemctl start "$svc"
  else
    rc-service "$svc" start
  fi
}

service_stop() {
  local svc="$1"
  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    systemctl stop "$svc"
  else
    rc-service "$svc" stop
  fi
}

service_restart() {
  local svc="$1"
  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    systemctl restart "$svc"
  else
    rc-service "$svc" restart
  fi
}

service_active() {
  local svc="$1"
  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    systemctl is-active --quiet "$svc"
  else
   rc-service "$svc" status | grep -q "started"
  fi
}

# ======================= ENV 自动模式加载 =======================
load_env_vars() {
    while IFS='=' read -r key value; do
        case "$key" in
            PORT|UUID|RANGE_PORTS|NODE_NAME|NGINX_PORT)
                if [[ -n "$value" && "$value" =~ ^[a-zA-Z0-9\.\-\:_/]+$ ]]; then
                    export "$key=$value"
                fi
                ;;
        esac
    done < <(env | grep -E '^(PORT|UUID|RANGE_PORTS|NODE_NAME|NGINX_PORT)=')
}
load_env_vars

# ======================= 模式判定 =======================
is_interactive_mode() {
    if [[ -n "$PORT" || -n "$UUID" || -n "$RANGE_PORTS" || -n "$NODE_NAME"  || -n "$NGINX_PORT" ]]; then
        return 1   # 自动模式
    else
        return 0   # 交互模式
    fi
}

DEFAULT_UUID=$(cat /proc/sys/kernel/random/uuid)

# ======================= 跳跃端口状态（唯一事实源） =======================
get_range_ports() {
    [[ -f "$range_port_file" ]] && cat "$range_port_file"
}

# ============================================================
# 安装常用依赖（等价原 hy2）
# ============================================================
install_common_packages() {
    local pkgs="tar jq openssl lsof curl coreutils iptables ip6tables nginx"
    local need_update=1

    for p in $pkgs; do
        if ! command_exists "$p"; then
            # 只 update 一次
            if [[ $need_update -eq 1 ]]; then
                if command_exists apt; then
                    apt update -y
                elif command_exists yum; then
                    yum makecache -y
                elif command_exists dnf; then
                    dnf makecache -y
                elif command_exists apk; then
                    apk update
                else
                    err "无法识别包管理器，请手动安装依赖"
                    return 1
                fi
                need_update=0
            fi

            yellow "安装依赖：$p"
            if command_exists apt; then
                apt install -y "$p"
            elif command_exists yum; then
                yum install -y "$p"
            elif command_exists dnf; then
                dnf install -y "$p"
            elif command_exists apk; then
                apk add "$p"
            else
                err "无法识别包管理器，请手动安装 $p"
                return 1
            fi
        fi
    done

    # ==================================================
    # Alpine nftables / iptables NAT 兼容兜底
    # ==================================================
    if command_exists apk; then
        # 检测 NAT 表是否可用
        if ! iptables -t nat -L >/dev/null 2>&1; then
            yellow "检测到 iptables NAT 不可用，尝试安装 iptables-legacy 兼容层"
            apk add iptables-legacy ip6tables-legacy >/dev/null 2>&1 || true
        fi
    fi
}


# ============================================================
# 防火墙放行 HY2 主端口（UDP）
# ============================================================
allow_port() {
    local port="$1"

    iptables -C INPUT -p udp --dport "$port" -j ACCEPT &>/dev/null ||
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT

    ip6tables -C INPUT -p udp --dport "$port" -j ACCEPT &>/dev/null ||
        ip6tables -I INPUT -p udp --dport "$port" -j ACCEPT

    green "已放行 UDP 端口：$port"
}


# ============================================================
# 防火墙放行 Nginx 订阅端口（TCP）
# ============================================================
allow_tcp_port() {
    local port="$1"

    iptables -C INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null ||
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT

    ip6tables -C INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null ||
        ip6tables -I INPUT -p tcp --dport "$port" -j ACCEPT

    green "已放行 TCP 端口：$port"
}


# ============================================================
# 防火墙回收 TCP 端口（Nginx 订阅端口）
# ============================================================
remove_tcp_port() {
    local port="$1"

    # IPv4
    while iptables -C INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null; do
        iptables -D INPUT -p tcp --dport "$port" -j ACCEPT
    done

    # IPv6
    while ip6tables -C INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null; do
        ip6tables -D INPUT -p tcp --dport "$port" -j ACCEPT
    done

    green "已回收 TCP 端口：$port"
}


# ============================================================
# 跳跃端口 NAT 管理（核心修复）
# ============================================================

# 添加跳跃端口 NAT
add_jump_rule() {
    local min="$1"
    local max="$2"
    local listen_port="$3"

    iptables -t nat -A PREROUTING \
        -p udp --dport ${min}:${max} \
        -m comment --comment "$NAT_COMMENT" \
        -j DNAT --to-destination :${listen_port}

    ip6tables -t nat -A PREROUTING \
        -p udp --dport ${min}:${max} \
        -m comment --comment "$NAT_COMMENT" \
        -j DNAT --to-destination :${listen_port}

    green "已添加跳跃端口 NAT：${min}-${max} → ${listen_port}"
}

# 删除所有跳跃端口 NAT
remove_jump_rule() {
    while iptables -t nat -C PREROUTING -m comment --comment "$NAT_COMMENT" &>/dev/null; do
        iptables -t nat -D PREROUTING -m comment --comment "$NAT_COMMENT"
    done

    while ip6tables -t nat -C PREROUTING -m comment --comment "$NAT_COMMENT" &>/dev/null; do
        ip6tables -t nat -D PREROUTING -m comment --comment "$NAT_COMMENT"
    done
}

# 删除 INPUT 放行（防残留）
remove_jump_input() {
    local min="$1"
    local max="$2"

    iptables -D INPUT -p udp --dport ${min}:${max} -j ACCEPT 2>/dev/null
    ip6tables -D INPUT -p udp --dport ${min}:${max} -j ACCEPT 2>/dev/null
}

# ============================================================
# 主端口变化时刷新跳跃端口（对齐 tuic5）
# ============================================================
refresh_jump_ports_for_new_main_port() {
    [[ ! -f "$range_port_file" ]] && return

    local rp
    rp=$(cat "$range_port_file")
    local min="${rp%-*}"
    local max="${rp#*-}"
    local new_port="$1"

    yellow "刷新跳跃端口 NAT：${min}-${max} → ${new_port}"

    # 清旧 NAT
    remove_jump_rule

    # 重新放行 INPUT
    remove_jump_input "$min" "$max"
    iptables -I INPUT -p udp --dport ${min}:${max} -j ACCEPT
    ip6tables -I INPUT -p udp --dport ${min}:${max} -j ACCEPT

    # 新 NAT
    add_jump_rule "$min" "$max" "$new_port"
}

# ============================================================
# 跳跃端口格式校验
# ============================================================
is_valid_range() {
    [[ "$1" =~ ^([0-9]+)-([0-9]+)$ ]] || return 1
    local min="${BASH_REMATCH[1]}"
    local max="${BASH_REMATCH[2]}"
    is_valid_port "$min" && is_valid_port "$max" && [[ $min -lt $max ]]
}

# ============================================================
# 安装 Sing-box（HY2）
# ============================================================
install_singbox() {

    clear
    purple "开始安装 Sing-box（Hysteria2）..."

    install_common_packages
    mkdir -p "$work_dir"

    # -------------------- 架构检测 --------------------
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        i386|i686) ARCH="i386" ;;
        riscv64) ARCH="riscv64" ;;
        mips64el) ARCH="mips64le" ;;
        *)
            err "不支持的架构：$ARCH"
            pause_return
            return
            ;;
    esac

    FILE="sing-box-${SINGBOX_VERSION}-linux-${ARCH}.tar.gz"
    URL="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/${FILE}"

    yellow "下载 Sing-box：$URL"
    curl -fSL --retry 3 --retry-delay 2 -o "$FILE" "$URL" || {
        err "下载失败"
        pause_return
        return
    }

    tar -xzf "$FILE" || {
        err "解压失败"
        pause_return
        return
    }
    rm -f "$FILE"

    extracted=$(find . -maxdepth 1 -type d -name "sing-box-*")
    extracted=$(echo "$extracted" | head -1)

    mv "$extracted/sing-box" "$work_dir/sing-box"
    chmod +x "$work_dir/sing-box"
    rm -rf "$extracted"

    # ====================================================
    # 模式判定
    # ====================================================
    is_interactive_mode
    if [[ $? -eq 1 ]]; then
        white "当前模式：自动模式"

        # -------- 主端口 --------
        if is_valid_port "$PORT" && ! is_port_occupied "$PORT"; then
            :
        else
            yellow "PORT 无效或被占用，切换为交互输入"
            prompt_valid_port "PORT" "请输入 HY2 主端口（UDP）："
        fi

        # -------- UUID --------
        if [[ -n "$UUID" ]]; then
            if ! is_valid_uuid "$UUID"; then
                yellow "UUID 无效，重新输入"
                while true; do
                    read -rp "$(red_input "请输入 UUID（回车自动生成）：")" UUID
                    [[ -z "$UUID" ]] && UUID=$(cat /proc/sys/kernel/random/uuid) && break
                    is_valid_uuid "$UUID" && break
                    red "UUID 格式错误"
                done
            fi
        else
            UUID=$(cat /proc/sys/kernel/random/uuid)
        fi

    else
        white "当前模式：交互模式"

        # -------- 主端口 --------
        while true; do
            read -rp "$(red_input "请输入 HY2 主端口（UDP）：")" PORT
            is_valid_port "$PORT" && ! is_port_occupied "$PORT" && break
            red "端口无效或被占用"
        done

        # -------- UUID --------
        while true; do
            read -rp "$(red_input "请输入 UUID（回车自动生成）：")" UUID
            [[ -z "$UUID" ]] && UUID=$(cat /proc/sys/kernel/random/uuid) && break
            is_valid_uuid "$UUID" && break
            red "UUID 格式错误"
        done
    fi

    # ====================================================
    # 放行主端口
    # ====================================================
    allow_port "$PORT"

    # ====================================================
    # TLS 证书（自签）
    # ====================================================
    openssl ecparam -genkey -name prime256v1 -out "$work_dir/private.key"
    openssl req -x509 -new -nodes \
        -key "$work_dir/private.key" \
        -sha256 -days 3650 \
        -subj "/C=US/ST=CA/O=bing.com/CN=bing.com" \
        -out "$work_dir/cert.pem"

    # ====================================================
    # 生成 config.json
    # ====================================================
cat > "$config_dir" <<EOF
{
  "log": {
    "level": "error",
    "output": "$work_dir/sb.log"
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        { "password": "$UUID" }
      ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$work_dir/cert.pem",
        "key_path": "$work_dir/private.key"
      }
    }
  ],
  "outbounds": [
    { "type": "direct" }
  ]
}
EOF

    green "配置文件已生成：$config_dir"

    # ====================================================
    # 创建并启动服务（systemd / openrc 自适应）
    # ====================================================
    make_service

    green "Sing-box HY2 服务已启动"

    init_node_name_on_install
    
    # 默认启用订阅服务（如 nginx 已安装）
    build_subscribe_conf



}


make_service() {
  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    make_service_systemd
  else
    make_service_openrc
  fi

  service_enable "${SERVICE_NAME}"
  service_start  "${SERVICE_NAME}"
}



make_service_systemd() {

cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Sing-box Hysteria2
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${work_dir}/sing-box run -c ${config_dir}
Restart=always
RestartSec=3
LimitNOFILE=1048576

# 安全加固（可选，但推荐）
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

  # 重新加载 systemd
  systemctl daemon-reload
}



make_service_openrc() {
cat > /etc/init.d/${SERVICE_NAME} <<EOF
#!/sbin/openrc-run
name="sing-box hy2"
command="$work_dir/sing-box"
command_args="run -c $config_dir"
supervisor="supervise-daemon"
output_log="/var/log/${SERVICE_NAME}.log"
error_log="/var/log/${SERVICE_NAME}.err"

depend() {
  need net
}
EOF

chmod +x /etc/init.d/${SERVICE_NAME}
}


# ============================================================
# 查看节点信息 / 多客户端订阅 / 二维码
# ============================================================

check_nodes() {
    local mode="$1"   # silent / empty

    [[ ! -f "$config_dir" ]] && {
        red "未找到配置文件，请先安装 HY2"
        [[ "$mode" != "silent" ]] && pause_return
        return
    }

    # =====================================================
    # 基础信息
    # =====================================================
    local PORT UUID
    PORT=$(jq -r '.inbounds[0].listen_port' "$config_dir")
    UUID=$(jq -r '.inbounds[0].users[0].password' "$config_dir")

    # =====================================================
    # 探测 IPv4 / IPv6
    # =====================================================
    local ip4 ip6
    ip4=$(get_ipv4)
    ip6=$(get_ipv6)

    if [[ -z "$ip4" && -z "$ip6" ]]; then
        red "无法获取 IPv4 / IPv6 公网地址"
        [[ "$mode" != "silent" ]] && pause_return
        return
    fi

    # =====================================================
    # 节点基础名称
    # =====================================================
    local BASE_NAME
    BASE_NAME=$(get_node_name)

    # =====================================================
    # 订阅端口（仅用于展示）
    # =====================================================
    local sub_port
    if [[ -f "$sub_port_file" ]]; then
        sub_port=$(cat "$sub_port_file")
    fi

    # =====================================================
    # 初始化订阅内容（数据层）
    # =====================================================
    > "$sub_file"

    yellow "========================================================"

    # =====================================================
    # HY2 IPv4 节点
    # =====================================================
    local hy2_v4=""
    if [[ -n "$ip4" ]]; then
        local name4 enc4
        name4="${BASE_NAME}"
        enc4=$(urlencode "$name4")

        hy2_v4="hysteria2://${UUID}@${ip4}:${PORT}/?insecure=1&alpn=h3#${enc4}"

        purple "HY2 IPv4 节点（${name4}）"
        green "$hy2_v4"
        [[ "$mode" != "silent" ]] && generate_qr "$hy2_v4"
        echo ""

        echo "$hy2_v4" >> "$sub_file"
        echo "$hy2_v4" > "$client_dir"
    fi

    # =====================================================
    # HY2 IPv6 节点
    # =====================================================
    local hy2_v6=""
    if [[ -n "$ip6" ]]; then
        local name6 enc6
        name6="${BASE_NAME}"
        enc6=$(urlencode "$name6")

        hy2_v6="hysteria2://${UUID}@[${ip6}]:${PORT}/?insecure=1&alpn=h3#${enc6}"

        purple "HY2 IPv6 节点（${name6}）"
        green "$hy2_v6"
        [[ "$mode" != "silent" ]] && generate_qr "$hy2_v6"
        echo ""

        echo "$hy2_v6" >> "$sub_file"
        [[ -z "$hy2_v4" ]] && echo "$hy2_v6" > "$client_dir"
    fi

    yellow "========================================================"

    # =====================================================
    # 本地订阅（base64，仅数据）
    # =====================================================
    base64 -w0 "$sub_file" > "${work_dir}/sub_base64.txt"

    # =====================================================
    # 订阅展示（仅在订阅启用时）
    # =====================================================
    if [[ -f "$sub_nginx_conf" ]]; then
        local sub_url_v4="" sub_url_v6=""

        if [[ -n "$ip4" ]]; then
            sub_url_v4="http://${ip4}:${sub_port}/${UUID}"
            purple "基础订阅（IPv4）："
            green "$sub_url_v4"
            [[ "$mode" != "silent" ]] && generate_qr "$sub_url_v4"
            echo ""
        fi

        if [[ -n "$ip6" ]]; then
            sub_url_v6="http://[${ip6}]:${sub_port}/${UUID}"
            purple "基础订阅（IPv6）："
            green "$sub_url_v6"
            [[ "$mode" != "silent" ]] && generate_qr "$sub_url_v6"
            echo ""
        fi

        yellow "========================================================"

        # ================= 客户端订阅 =================
        print_client_subscribe_links "$sub_url_v4" "IPv4" "$mode"
        print_client_subscribe_links "$sub_url_v6" "IPv6" "$mode"
    else
        if [[ "$mode" != "silent" ]]; then
            yellow "订阅服务当前未启用"
            echo ""
            blue  "提示：如需使用订阅功能，请前往以下菜单手动启用："
            green "  主菜单 → 6. 订阅服务管理"
            green "           → 启用 / 重建订阅服务"
        fi
    fi

    yellow "========================================================"

    [[ "$mode" != "silent" ]] && pause_return

    return 0
}



print_client_subscribe_links() {
    local sub_url="$1"   # 基础订阅 URL
    local label="$2"     # IPv4 / IPv6（仅用于显示）
    local mode="$3"      # silent / empty

    # 没有订阅 URL 直接返回
    [[ -z "$sub_url" ]] && return

    # ---------- Clash / Mihomo ----------
    purple "Clash / Mihomo（${label}）："
    local clash_url="https://sublink.eooce.com/clash?config=${sub_url}"
    green "$clash_url"
    [[ "$mode" != "silent" ]] && generate_qr "$clash_url"
    echo ""

    # ---------- Sing-box ----------
    purple "Sing-box（${label}）："
    local singbox_url="https://sublink.eooce.com/singbox?config=${sub_url}"
    green "$singbox_url"
    [[ "$mode" != "silent" ]] && generate_qr "$singbox_url"
    echo ""

    # ---------- Surge ----------
    purple "Surge（${label}）："
    local surge_url="https://sublink.eooce.com/surge?config=${sub_url}"
    green "$surge_url"
    [[ "$mode" != "silent" ]] && generate_qr "$surge_url"
    echo ""
}


get_node_name() {
    local name

     # ======================================================
    # 1. 持久化节点名称优先（如果用户曾设置过）
    # ======================================================
    if [[ -f "$work_dir/node_name" ]]; then
        saved_name=$(cat "$work_dir/node_name")
        if [[ -n "$saved_name" ]]; then
            echo "$saved_name"
            return
        fi
    fi

    # ======================================================
    # 2. 当前会话设置的节点名称（change_node_name 临时变量）
    # ======================================================
    if [[ -n "$NODE_NAME" ]]; then
        echo "$NODE_NAME"
        return
    fi


   # ======================================================
    # 3. 自动生成节点名称（国家代码 + 运营商）
    # ======================================================

    local country=""
    local org=""

    # 先尝试 ipapi
    country=$(curl -fs --max-time 2 https://ipapi.co/country 2>/dev/null | tr -d '\r\n')
    org=$(curl -fs --max-time 2 https://ipapi.co/org 2>/dev/null | sed 's/[ ]\+/_/g')

    # fallback
    if [[ -z "$country" ]]; then
        country=$(curl -fs --max-time 2 ip.sb/country 2>/dev/null | tr -d '\r\n')
    fi

    if [[ -z "$org" ]]; then
        org=$(curl -fs --max-time 2 ipinfo.io/org 2>/dev/null \
            | awk '{$1=""; print $0}' \
            | sed -e 's/^[ ]*//' -e 's/[ ]\+/_/g')
    fi

    # 自动生成节点名称规则
    if [[ -n "$country" && -n "$org" ]]; then
        echo "${country}-${org}"
        return
    fi

    if [[ -n "$country" && -z "$org" ]]; then
        echo "$country"
        return
    fi

    if [[ -z "$country" && -n "$org" ]]; then
        echo "${AUTHOR}-hy2"
        return
    fi

    echo "$name"
}



init_node_name_on_install() {

    local DEFAULT_NODE_NAME="${AUTHOR}-hy2"
    local country="" org="" name=""

    # 已存在则不覆盖（重装/升级保护）
    [[ -f "$work_dir/node_name" ]] && return

    # 1. ENV 优先
    if [[ -n "$NODE_NAME" ]]; then
        echo "$NODE_NAME" > "$work_dir/node_name"
        green "节点名称初始化为：$NODE_NAME"
        return
    fi

    # 2. IP 推断
    country=$(curl -fs --max-time 2 https://ipapi.co/country 2>/dev/null | tr -d '\r\n')
    org=$(curl -fs --max-time 2 https://ipapi.co/org 2>/dev/null | sed 's/[ ]\+/_/g')

    if [[ -z "$country" ]]; then
        country=$(curl -fs --max-time 2 ip.sb/country 2>/dev/null | tr -d '\r\n')
    fi

    if [[ -z "$org" ]]; then
        org=$(curl -fs --max-time 2 ipinfo.io/org 2>/dev/null \
            | awk '{$1=""; print $0}' \
            | sed -e 's/^[ ]*//' -e 's/[ ]\+/_/g')
    fi

    # 3. 组合规则（修正你原来的不一致）
    if [[ -n "$country" && -n "$org" ]]; then
        name="${country}-${org}"
    elif [[ -n "$country" ]]; then
        name="$country"
    elif [[ -n "$org" ]]; then
        name="$org"
    else
        name="$DEFAULT_NODE_NAME"
    fi

    echo "$name" > "$work_dir/node_name"
    green "节点名称初始化为：$name"
}


# ============================================================
# Sing-box 服务管理
# ============================================================
manage_singbox() {
    while true; do
        clear
        blue "========== Sing-box 服务管理 =========="
        echo ""
        green " 1. 启动 Sing-box"
        green " 2. 停止 Sing-box"
        green " 3. 重启 Sing-box"
        green " 4. 查看运行状态"
        yellow "--------------------------------------"
        green " 0. 返回上级菜单"
        red   "88. 退出脚本"
        echo ""

        read -rp "请选择操作：" sel
        case "$sel" in
            1)
                service_start "${SERVICE_NAME}"
                if service_active "${SERVICE_NAME}"; then
                    green "Sing-box 已启动"
                else
                    red "Sing-box 启动失败"
                fi
                pause_return
                ;;
            2)
                service_stop "${SERVICE_NAME}"
                if service_active "${SERVICE_NAME}"; then
                    red "Sing-box 停止失败"
                else
                    green "Sing-box 已停止"
                fi
                pause_return
                ;;
            3)
                service_restart "${SERVICE_NAME}"
                if service_active "${SERVICE_NAME}"; then
                    green "Sing-box 已重启"
                else
                    red "Sing-box 重启失败"
                fi
                pause_return
                ;;
            4)
                echo ""
                if service_active "${SERVICE_NAME}"; then
                    green "Sing-box 当前状态：运行中"
                else
                    red "Sing-box 当前状态：未运行"
                fi
                echo ""
                pause_return
                ;;
            0)
                return
                ;;
            88)
                exit_script
                ;;
            *)
                red "无效输入"
                pause_return
                ;;
        esac
    done
}


# ============================================================
# 修改 HY2 主端口（自动刷新 NAT）
# ============================================================
change_hy2_port() {

    read -rp "$(red_input "请输入新的 HY2 主端口：")" new_port

    is_valid_port "$new_port" || { red "端口无效"; return; }
    is_port_occupied "$new_port" && { red "端口已被占用"; return; }

    old_port=$(jq -r '.inbounds[0].listen_port' "$config_dir")

    # 修改 config.json
    sed -i "s/\"listen_port\": ${old_port}/\"listen_port\": ${new_port}/" "$config_dir"

    green "主端口已修改：${old_port} → ${new_port}"

    # 刷新防火墙
    allow_port "$new_port"

    # 刷新跳跃端口 NAT（如存在）
    refresh_jump_ports_for_new_main_port "$new_port"


    # 默认回收旧端口（安全策略）
    if [[ "$old_port" != "$new_port" ]]; then
        iptables -D INPUT -p udp --dport "$old_port" -j ACCEPT 2>/dev/null
        ip6tables -D INPUT -p udp --dport "$old_port" -j ACCEPT 2>/dev/null
        green "旧端口 ${old_port} 已回收"
    fi


    # 重启服务
    service_restart "${SERVICE_NAME}"


    green "Sing-box 已重启，端口修改生效"

    check_nodes silent
    pause_return

}

# ============================================================
# 修改 UUID
# ============================================================
change_uuid() {

    read -rp "$(red_input "请输入新的 UUID（回车自动生成）：")" new_uuid

    if [[ -z "$new_uuid" ]]; then
        new_uuid=$(cat /proc/sys/kernel/random/uuid)
        green "已生成新 UUID：$new_uuid"
    else
        is_valid_uuid "$new_uuid" || { red "UUID 格式错误"; return; }
    fi

    old_uuid=$(jq -r '.inbounds[0].users[0].password' "$config_dir")

    tmpfile=$(mktemp)
    jq '.inbounds[0].users[0].password = "'"$new_uuid"'"' "$config_dir" > "$tmpfile" \
        && mv "$tmpfile" "$config_dir"

    green "UUID 已修改：${old_uuid} → ${new_uuid}"

    service_restart "${SERVICE_NAME}"
    green "Sing-box 已重启"

    pause_return
}

# ============================================================
# 修改节点名称（只改 tag）
# ============================================================
change_node_name() {

    read -rp "$(red_input "请输入新的节点名称：")" new_name
    [[ -z "$new_name" ]] && { red "节点名称不能为空"; return; }

    encoded_name=$(urlencode "$new_name")

    if [[ -f "$client_dir" ]]; then
        old_url=$(cat "$client_dir")
        url_body="${old_url%%#*}"
        echo "${url_body}#${encoded_name}" > "$client_dir"
        green "节点名称已修改"
    fi


    pause_return
}


# ============================================================
# 跳跃端口处理
# ============================================================
apply_range_ports_if_needed() {
    [[ -z "$RANGE_PORTS" ]] && return

    green "检测到跳跃端口……"

    if ! is_valid_range "$RANGE_PORTS"; then
        red "RANGE_PORTS 格式错误，已跳过跳跃端口配置"
        return
    fi

    local min="${RANGE_PORTS%-*}"
    local max="${RANGE_PORTS#*-}"
    local PORT
    PORT=$(jq -r '.inbounds[0].listen_port' "$config_dir")

    yellow "应用跳跃端口区间：${min}-${max} → ${PORT}"

    # 清理旧规则（幂等）
    remove_jump_rule
    
    if [[ -f "$range_port_file" ]]; then
    old=$(cat "$range_port_file")
    remove_jump_input "${old%-*}" "${old#*-}"

    fi


    # 写入状态文件
    echo "$RANGE_PORTS" > "$range_port_file"

    # 放行 INPUT
    iptables -I INPUT -p udp --dport ${min}:${max} -j ACCEPT
    ip6tables -I INPUT -p udp --dport ${min}:${max} -j ACCEPT

    # 添加 NAT
    add_jump_rule "$min" "$max" "$PORT"

    green "跳跃端口已生效：$RANGE_PORTS"
}



# ============================================================
# 启用 / 修改跳跃端口（动作函数）
# ============================================================
enable_or_update_jump_ports() {
    read -rp "$(red_input "请输入跳跃端口区间（如 10000-20000）：")" rp

    if ! is_valid_range "$rp"; then
        red "跳跃端口格式错误"
        pause_return
        return
    fi

    local min="${rp%-*}"
    local max="${rp#*-}"
    local PORT
    PORT=$(jq -r '.inbounds[0].listen_port' "$config_dir")

    # 幂等清理旧规则
    remove_jump_rule
    if [[ -f "$range_port_file" ]]; then
        old_range=$(cat "$range_port_file")
        remove_jump_input "${old_range%-*}" "${old_range#*-}"
    fi

    # 写入状态文件
    echo "$rp" > "$range_port_file"

    # 放行 INPUT
    iptables -I INPUT -p udp --dport ${min}:${max} -j ACCEPT
    ip6tables -I INPUT -p udp --dport ${min}:${max} -j ACCEPT

    # 添加 NAT
    add_jump_rule "$min" "$max" "$PORT"

    green "跳跃端口已启用 / 更新：$rp"
    pause_return
}

# ============================================================
# 关闭跳跃端口（动作函数）
# ============================================================
disable_jump_ports() {
    if [[ ! -f "$range_port_file" ]]; then
        yellow "当前未启用跳跃端口"
        pause_return
        return
    fi

    local rp
    rp=$(cat "$range_port_file")
    local min="${rp%-*}"
    local max="${rp#*-}"

    remove_jump_rule
    remove_jump_input "$min" "$max"
    rm -f "$range_port_file"

    green "跳跃端口已关闭"
    pause_return
}


# ============================================================
# 修改节点配置菜单（平铺最终版）
# ============================================================
manage_node_config_menu() {
    while true; do
        clear
        blue "========== 修改节点配置 =========="
        echo ""

        # 当前节点状态提示
        local CUR_PORT CUR_UUID CUR_RANGE
        CUR_PORT=$(jq -r '.inbounds[0].listen_port' "$config_dir" 2>/dev/null)
        CUR_UUID=$(jq -r '.inbounds[0].users[0].password' "$config_dir" 2>/dev/null)

        if [[ -f "$range_port_file" ]]; then
            CUR_RANGE=$(cat "$range_port_file")
        else
            CUR_RANGE="未启用"
        fi

        yellow "当前主端口：${CUR_PORT:-未安装}"
        yellow "当前 UUID ：${CUR_UUID:-未安装}"
        yellow "跳跃端口  ：$CUR_RANGE"
        echo ""

        green " 1. 修改 HY2 主端口"
        green " 2. 修改 UUID"
        green " 3. 修改节点名称"
        green " 4. 修改跳跃端口"
        green " 5. 关闭跳跃端口"
        yellow "---------------------------------"
        green " 0. 返回上级菜单"
        red   "88. 退出脚本"
        echo ""

        read -rp "请选择操作：" sel
        case "$sel" in
            1)
                change_hy2_port
                ;;
            2)
                change_uuid
                ;;
            3)
                change_node_name
                ;;
            4)
                enable_or_update_jump_ports
                ;;
            5)
                disable_jump_ports
                ;;
            0)
                return
                ;;
            88)
                exit_script
                ;;
            *)
                red "无效输入"
                pause_return
                ;;
        esac
    done
}


uninstall_singbox() {

    clear
    blue "============== 卸载 HY2 =============="
    echo ""

    read -rp "确认卸载 Sing-box（HY2）？ [Y/n]（默认 Y）：" u
    u=${u:-y}
    [[ ! "$u" =~ ^[Yy]$ ]] && { yellow "已取消卸载"; pause_return; return; }

    if [[ -f "$sub_port_file" ]]; then
        old_port=$(cat "$sub_port_file")
        remove_tcp_port "$old_port"
    fi


    # ---------- 清理跳跃端口 ----------
    remove_jump_rule
    if [[ -f "$range_port_file" ]]; then
        rp=$(cat "$range_port_file")
        min="${rp%-*}"
        max="${rp#*-}"
        iptables -D INPUT -p udp --dport ${min}:${max} -j ACCEPT 2>/dev/null
        ip6tables -D INPUT -p udp --dport ${min}:${max} -j ACCEPT 2>/dev/null
        rm -f "$range_port_file"
    fi
    green "已清理跳跃端口相关规则"

    # ---------- 停止并移除服务 ----------
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl stop ${SERVICE_NAME} 2>/dev/null
        systemctl disable ${SERVICE_NAME} 2>/dev/null
        rm -f /etc/systemd/system/${SERVICE_NAME}.service
        systemctl daemon-reload
    else
        rc-service ${SERVICE_NAME} stop 2>/dev/null
        rc-update del ${SERVICE_NAME} 2>/dev/null
        rm -f /etc/init.d/${SERVICE_NAME}
    fi
    green "服务已移除"

    # ---------- 删除运行目录 ----------
    rm -rf "$work_dir"

    # ---------- 删除订阅配置 ----------
    rm -f "$sub_nginx_conf" "$nginx_conf_link"

    # ---------- 重载 nginx（如存在） ----------
    if command_exists nginx && service_active nginx; then
        service_restart nginx
    fi

    green "HY2 已卸载完成"
    echo ""

    # ---------- 是否卸载 nginx ----------
    if command_exists nginx; then
        read -rp "是否同时卸载 Nginx？ [y/N]：" delng
        delng=${delng:-n}
        if [[ "$delng" =~ ^[Yy]$ ]]; then
            if command_exists apt; then
                apt remove -y nginx nginx-core
            elif command_exists yum; then
                yum remove -y nginx
            elif command_exists dnf; then
                dnf remove -y nginx
            elif command_exists apk; then
                apk del nginx
            fi
            green "Nginx 已卸载"
        else
            yellow "已保留 Nginx"
        fi
    fi

    pause_return
}


# ============================================================
# 订阅服务（Nginx）管理菜单
# ============================================================
manage_subscribe_menu() {
    while true; do
        clear
        blue "========== 订阅服务管理（Nginx） =========="
        echo ""

        print_subscribe_status
        echo ""

        green " 1. 启动 Nginx"
        green " 2. 停止 Nginx"
        green " 3. 重启 Nginx"

        yellow "-----------------------------------------"
        green " 4. 启用 / 重建订阅服务"
        green " 5. 修改订阅端口"
        green " 6. 关闭订阅服务"

        yellow "-----------------------------------------"
        green " 0. 返回上级菜单"
        red   "88. 退出脚本"
        echo ""

        read -rp "请选择操作：" sel
        case "$sel" in
            1)
                service_start nginx
                service_active nginx && green "Nginx 已启动" || red "Nginx 启动失败"
                pause_return
                ;;
            2)
                service_stop nginx
                service_active nginx && red "Nginx 停止失败" || green "Nginx 已停止"
                pause_return
                ;;
            3)
                service_restart nginx
                service_active nginx && green "Nginx 已重启" || red "Nginx 重启失败"
                pause_return
                ;;
            4)
                build_subscribe_conf
                pause_return
                ;;
            5)
                change_subscribe_port
                pause_return
                ;;
            6)
                disable_subscribe
                pause_return
                ;;
            0)
                return
                ;;
            88)
                exit_script
                ;;
            *)
                red "无效输入"
                pause_return
                ;;
        esac
    done
}



# ============================================================
# 主菜单（最终版，对齐 tuic5）
# ============================================================
main_menu() {
    while true; do
        clear
        blue "===================================================="
        gradient "       Sing-box 一键脚本（hy2版本）"
        green    "       作者：$AUTHOR"
        yellow   "       版本：$VERSION"
        blue "===================================================="
        echo ""


        sb="$(get_singbox_status_colored)"
        ng="$(get_nginx_status_colored)"
        ss="$(get_subscribe_status_colored)"

        yellow " Sing-box 状态：$sb"
        yellow " Nginx 状态：   $ng"
        yellow " 订阅 状态：   $ss"
        echo ""
        green " 1. 安装 Sing-box (HY2)"
        red   " 2. 卸载 Sing-box"
        yellow "----------------------------------------"
        green " 3. 管理 Sing-box 服务"
        green " 4. 查看节点信息"
        yellow "----------------------------------------"
        green " 5. 修改节点配置"
        green " 6. 订阅服务管理"
        yellow "---------------------------------------------"
        green " 88. 退出脚本"
        echo ""

        read -rp "请选择操作：" choice
        case "$choice" in
            1)
                install_singbox
                # 安装后统一处理（对齐自动模式）
                apply_range_ports_if_needed
                check_nodes
                ;;
            2)
                uninstall_singbox
                ;;
            3)   
                manage_singbox
                ;;
            4)
                check_nodes
                ;;
            5)
                manage_node_config_menu
                ;;
            6)
                manage_subscribe_menu
                ;;
            88)
                exit_script
                ;;
            *)
                red "无效输入"
                pause_return
                ;;
        esac
    done
}


get_singbox_status_colored() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${SERVICE_NAME}\.service" \
            || { red "未安装"; return; }
    else
        [[ -f "/etc/init.d/${SERVICE_NAME}" ]] || { red "未安装"; return; }
    fi

    service_active ${SERVICE_NAME} && green "运行中" || red "未运行"
}

get_nginx_status_colored() {
    if ! command_exists nginx; then
        red "未安装"
        return
    fi

    service_active nginx && green "运行中" || red "未运行"
}



get_subscribe_status_colored() {
    if [[ -f "$sub_nginx_conf" ]]; then
        green "已启用"
    else
        yellow "未启用"
    fi
}



print_subscribe_status() {
    if [[ -f "$sub_nginx_conf" ]]; then
        green "当前订阅状态：已启用"
    else
        yellow "当前订阅状态：未启用"
    fi
}

is_subscribe_enabled() {
    [[ -f "$sub_nginx_conf" ]]
}



build_subscribe_conf() {
    local sub_port uuid content

    # ==================================================
    # 1. 确保订阅数据存在（彻底解耦 check_nodes 调用顺序）
    # ==================================================
    if [[ ! -f "$sub_file" || ! -s "$sub_file" ]]; then
        yellow "订阅数据不存在，正在自动生成节点信息…"
        check_nodes silent || {
            red "生成订阅数据失败，无法创建订阅服务"
            return 1
        }
    fi

    # ==================================================
    # 2. 读取 UUID 与订阅端口
    # ==================================================
    uuid=$(jq -r '.inbounds[0].users[0].password' "$config_dir")

    # ==================================================
    # 2. 读取并校验 NGINX_PORT（必填）
    # ==================================================
    prompt_valid_port "NGINX_PORT" "请输入订阅服务端口 NGINX_PORT："

    sub_port="$NGINX_PORT"
    echo "$sub_port" > "$sub_port_file"


    # 放行 Nginx TCP 端口
    allow_tcp_port "$sub_port"

    # ==================================================
    # 3. 构建 Base64 订阅内容（单一事实源）
    # ==================================================
    content=$(base64 -w0 "$sub_file")

    # ==================================================
    # 4. 生成 Nginx 订阅配置
    # ==================================================
    cat > "$sub_nginx_conf" <<EOF
server {
    listen ${sub_port};
    server_name _;

    location /${uuid} {
        default_type text/plain;
        return 200 "${content}";
    }
}
EOF

    # ==================================================
    # 5. 建立软链到 Nginx 配置目录（systemd / openrc 通用）
    # ==================================================
    ln -sf "$sub_nginx_conf" "$nginx_conf_link"

    # ==================================================
    # 6. 重载 Nginx（如正在运行）
    # ==================================================
    if command_exists nginx && service_active nginx; then
        service_restart nginx
        green "订阅服务已生成并生效"
    else
        yellow "Nginx 未运行，订阅配置已生成，启动 Nginx 后生效"
    fi
}







disable_subscribe() {
    rm -f "$sub_nginx_conf"
    rm -f "$nginx_conf_link"

    if [[ -f "$sub_port_file" ]]; then
        old_port=$(cat "$sub_port_file")
        remove_tcp_port "$old_port"
        rm -f "$sub_port_file"
    fi


    if command_exists nginx && service_active nginx; then
        service_restart nginx
    fi


    green "订阅服务已关闭"
}

change_subscribe_port() {
    prompt_valid_port "new_port" "请输入新的订阅端口："


    old_port=$(cat "$sub_port_file" 2>/dev/null)
    [[ -n "$old_port" ]] && remove_tcp_port "$old_port"


    echo "$new_port" > "$sub_port_file"

    allow_tcp_port "$new_port"


    # 如果订阅已启用，重建 conf
    if [[ -f "$sub_nginx_conf" ]]; then
        build_subscribe_conf
        green "订阅端口已修改为：$new_port"
    else
        yellow "订阅未启用，端口已保存，启用订阅后生效"
    fi
    
}


init_nginx_paths() {
  NGX_NGINX_DIR="$(detect_nginx_conf_dir)"
  nginx_conf_link="$NGX_NGINX_DIR/singbox_hy2_sub.conf"
  mkdir -p "$NGX_NGINX_DIR"
}


init_platform() {
  init_nginx_paths
}


main_entry() {
    detect_init
    init_platform
    
    is_interactive_mode
    if [[ $? -eq 1 ]]; then
        # ==================================================
        # 非交互式 / 自动模式
        # ==================================================

        yellow "检测到自动模式（ENV 已传入），开始自动部署..."

        install_singbox

        #  显式处理跳跃端口
        apply_range_ports_if_needed

        echo ""
        green "安装完成，正在输出节点与订阅信息..."
        echo ""

        # 自动模式下不 pause
        check_nodes silent

        green "自动模式执行完成"
        exit 0
    else
        # ==================================================
        # 交互式模式
        # ==================================================
        main_menu
    fi
}


main_entry
