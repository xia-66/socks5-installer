#!/usr/bin/env bash

#================================================================
#	脚本名称: SOCKS5 一键安装/卸载脚本 (基于gost)
#	系统支持: CentOS 7+, Debian 8+, Ubuntu 16+
#	项目地址: https://github.com/ginuerzh/gost
#================================================================

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 定义脚本变量
GOST_VERSION="2.12.0"
GOST_INSTALL_PATH="/usr/local/bin"
GOST_SERVICE_FILE="/etc/systemd/system/gost.service"
GOST_CONFIG_DIR="/etc/gost"
GOST_CONFIG_FILE="${GOST_CONFIG_DIR}/config.json"

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 本脚本必须以 root 权限运行！${PLAIN}"
        exit 1
    fi
}

# 检查操作系统和 systemd
check_os() {
    if ! command -v systemctl &> /dev/null; then
        echo -e "${RED}错误: 本脚本仅支持使用 systemd 的 Linux 系统。${PLAIN}"
        exit 1
    fi
}

# 获取系统架构
get_arch() {
    case $(uname -m) in
        x86_64)
            echo "amd64"
            ;;
        aarch64)
            echo "arm64"
            ;;
        armv7l)
            echo "armv7"
            ;;
        *)
            echo -e "${RED}错误: 不支持的系统架构: $(uname -m)${PLAIN}"
            exit 1
            ;;
    esac
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在检查并安装依赖 (curl, tar)...${PLAIN}"
    if ! command -v curl &> /dev/null || ! command -v tar &> /dev/null; then
        if command -v yum &> /dev/null; then
            yum install -y curl tar
        elif command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y curl tar
        else
            echo -e "${RED}错误: 无法自动安装依赖。请手动安装 curl 和 tar。${PLAIN}"
            exit 1
        fi
    fi
}

# 安装 gost
install_gost() {
    if [ -f "$GOST_SERVICE_FILE" ]; then
        echo -e "${YELLOW}检测到 gost 已安装，将执行卸载...${PLAIN}"
        uninstall_gost
    fi

    echo -e "${GREEN}===== 开始安装 SOCKS5 代理 =====${PLAIN}"

    # 获取用户输入
    read -p "请输入 SOCKS5 代理的监听端口 (默认 1080): " SOCKS5_PORT
    SOCKS5_PORT=${SOCKS5_PORT:-1080}

    read -p "请输入 SOCKS5 代理的用户名 (留空则不设置认证): " SOCKS5_USER
    
    if [ -n "$SOCKS5_USER" ]; then
        read -sp "请输入 SOCKS5 代理的密码: " SOCKS5_PASS
        echo
        while [ -z "$SOCKS5_PASS" ]; do
            echo -e "${RED}密码不能为空！${PLAIN}"
            read -sp "请重新输入 SOCKS5 代理的密码: " SOCKS5_PASS
            echo
        done
        AUTH_INFO="${SOCKS5_USER}:${SOCKS5_PASS}"
    fi

    # 下载并安装 gost
    ARCH=$(get_arch)
    # --- [!] 修改点: 修正了文件名的格式 ---
    FILENAME="gost-linux-${ARCH}-${GOST_VERSION}.tgz"
    
    # 定义多个下载源
    DOWNLOAD_URLS=(
        "https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/${FILENAME}"
        "https://ghproxy.com/https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/${FILENAME}"
        "https://mirror.ghproxy.com/https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/${FILENAME}"
    )

    echo -e "${YELLOW}正在下载 gost v${GOST_VERSION} for ${ARCH}...${PLAIN}"

    # 尝试所有下载源
    download_success=false
    for url in "${DOWNLOAD_URLS[@]}"; do
        echo -e "${YELLOW}[尝试] ${url}${PLAIN}"
        # --- [!] 修改点: 临时文件名改为 .tgz ---
        if curl -sL --connect-timeout 15 --max-time 120 "$url" -o "/tmp/gost.tgz"; then
            # 验证文件
            # --- [!] 修改点: 验证 .tgz 文件 ---
            if tar -tzf "/tmp/gost.tgz" &>/dev/null; then
                echo -e "${GREEN}✓ 下载成功！${PLAIN}"
                download_success=true
                break
            else
                echo -e "${YELLOW}✗ 文件损坏，尝试下一个源...${PLAIN}"
            fi
        else
            echo -e "${YELLOW}✗ 下载失败，尝试下一个源...${PLAIN}"
        fi
        rm -f "/tmp/gost.tgz"
    done

    if [ "$download_success" = false ]; then
        echo -e "${RED}所有下载源均失败！${PLAIN}"
        echo -e "${YELLOW}请检查：${PLAIN}"
        echo "  1. 网络连接是否正常"
        echo "  2. 能否访问 GitHub"
        echo "  3. DNS 设置是否正确"
        echo -e "\n${YELLOW}手动下载地址:${PLAIN}"
        echo "  https://github.com/ginuerzh/gost/releases/tag/v${GOST_VERSION}"
        exit 1
    fi

    echo -e "${YELLOW}正在解压并安装...${PLAIN}"
    # --- [!] 修改点: 解压 .tgz 文件 ---
    tar -zxf "/tmp/gost.tgz" -C "/tmp/"
    
    # --- [!] 修改点: v2.12.0 解压后文件位于一个目录中 ---
    EXTRACTED_DIR="/tmp/gost-linux-${ARCH}-${GOST_VERSION}"
    if [ ! -f "${EXTRACTED_DIR}/gost" ]; then
        echo -e "${RED}错误: 解压后未找到 gost 可执行文件！${PLAIN}"
        rm -rf /tmp/gost*
        exit 1
    fi
    
    mv "${EXTRACTED_DIR}/gost" "${GOST_INSTALL_PATH}/gost"
    chmod +x "${GOST_INSTALL_PATH}/gost"

    # 清理临时文件
    rm -rf /tmp/gost*

    # 创建 systemd 服务文件
    echo -e "${YELLOW}正在创建 systemd 服务...${PLAIN}"
    
    local exec_start_cmd="${GOST_INSTALL_PATH}/gost -L socks5://"
    if [ -n "$AUTH_INFO" ]; then
        exec_start_cmd+="${AUTH_INFO}@"
    fi
    exec_start_cmd+=":${SOCKS5_PORT}"

    cat > "$GOST_SERVICE_FILE" <<EOF
[Unit]
Description=Gost SOCKS5 Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=${exec_start_cmd}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    # 保存配置信息
    mkdir -p "$GOST_CONFIG_DIR"
    cat > "$GOST_CONFIG_FILE" <<EOF
{
  "port": "${SOCKS5_PORT}",
  "user": "${SOCKS5_USER}",
  "version": "${GOST_VERSION}"
}
EOF

    # 启动服务
    echo -e "${YELLOW}正在启动并设置开机自启...${PLAIN}"
    systemctl daemon-reload
    systemctl enable gost
    systemctl start gost

    # 配置防火墙
    echo -e "${YELLOW}正在配置防火墙...${PLAIN}"
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --add-port=${SOCKS5_PORT}/tcp --permanent &>/dev/null
        firewall-cmd --reload &>/dev/null
    elif command -v ufw &> /dev/null; then
        ufw allow ${SOCKS5_PORT}/tcp &>/dev/null
    else
        echo -e "${YELLOW}警告: 未检测到防火墙，请手动开放端口 ${SOCKS5_PORT}。${PLAIN}"
    fi

    # 显示安装结果
    sleep 2
    if systemctl is-active --quiet gost; then
        local server_ip=$(curl -s --max-time 5 ip.sb 2>/dev/null || curl -s --max-time 5 ip.me 2>/dev/null || echo "YOUR_SERVER_IP")
        
        echo -e "${GREEN}=================================================${PLAIN}"
        echo -e "${GREEN}       SOCKS5 代理安装成功！${PLAIN}"
        echo -e "${GREEN}=================================================${PLAIN}"
        echo -e "服务器地址: ${GREEN}${server_ip}${PLAIN}"
        echo -e "端口:       ${GREEN}${SOCKS5_PORT}${PLAIN}"
        if [ -n "$SOCKS5_USER" ]; then
            echo -e "用户名:     ${GREEN}${SOCKS5_USER}${PLAIN}"
            echo -e "密码:       ${GREEN}${SOCKS5_PASS}${PLAIN}"
        else
            echo -e "认证:       ${YELLOW}未设置${PLAIN}"
        fi
        echo -e "${GREEN}=================================================${PLAIN}"
        echo -e "${YELLOW}请在客户端中使用以上信息进行连接。${PLAIN}"
    else
        echo -e "${RED}安装失败！请查看服务状态以获取更多信息:${PLAIN}"
        echo -e "  journalctl -u gost -n 20"
    fi
}

# 卸载 gost
uninstall_gost() {
    if [ ! -f "$GOST_SERVICE_FILE" ]; then
        echo -e "${RED}错误: 未检测到 gost 安装。${PLAIN}"
        return 1
    fi

    echo -e "${YELLOW}===== 开始卸载 SOCKS5 代理 =====${PLAIN}"

    # 读取端口信息
    SOCKS5_PORT=$(grep -oP '"port":\s*"\K[^"]+' "$GOST_CONFIG_FILE" 2>/dev/null)

    # 停止并禁用服务
    systemctl stop gost
    systemctl disable gost

    # 删除服务文件和二进制文件
    rm -f "$GOST_SERVICE_FILE"
    rm -f "${GOST_INSTALL_PATH}/gost"
    rm -rf "$GOST_CONFIG_DIR"

    systemctl daemon-reload

    # 关闭防火墙端口
    if [ -n "$SOCKS5_PORT" ]; then
        echo -e "${YELLOW}正在关闭防火墙端口 ${SOCKS5_PORT}...${PLAIN}"
        if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
            firewall-cmd --zone=public --remove-port=${SOCKS5_PORT}/tcp --permanent &>/dev/null
            firewall-cmd --reload &>/dev/null
        elif command -v ufw &> /dev/null; then
            ufw delete allow ${SOCKS5_PORT}/tcp &>/dev/null
        fi
    fi

    echo -e "${GREEN}SOCKS5 代理已成功卸载！${PLAIN}"
}

# 查看状态
check_status() {
    if [ ! -f "$GOST_SERVICE_FILE" ]; then
        echo -e "${RED}错误: 未检测到 gost 安装。${PLAIN}"
        return 1
    fi
    
    echo -e "${YELLOW}===== 服务状态 =====${PLAIN}"
    systemctl status gost --no-pager -l
    
    if [ -f "$GOST_CONFIG_FILE" ]; then
        echo -e "\n${YELLOW}===== 配置信息 =====${PLAIN}"
        # 使用 jq 美化输出 (如果已安装)
        if command -v jq &> /dev/null; then
            jq . "$GOST_CONFIG_FILE"
        else
            cat "$GOST_CONFIG_FILE"
        fi
    fi
}

# 显示主菜单
show_menu() {
    clear
    echo "=================================================="
    echo " SOCKS5 一键安装/卸载脚本 (基于 gost v${GOST_VERSION})"
    echo "=================================================="
    echo -e " ${GREEN}1. 安装 SOCKS5 代理${PLAIN}"
    echo -e " ${RED}2. 卸载 SOCKS5 代理${PLAIN}"
    echo -e " ${YELLOW}3. 查看 SOCKS5 代理状态${PLAIN}"
    echo " ──────────────────────────────────"
    echo " 0. 退出脚本"
    echo "=================================================="
    read -p "请输入你的选择 [0-3]: " choice

    case $choice in
        1)
            install_gost
            ;;
        2)
            uninstall_gost
            ;;
        3)
            check_status
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选择，请输入正确的数字。${PLAIN}"
            sleep 2
            show_menu
            ;;
    esac
}

# 脚本主入口
main() {
    check_root
    check_os
    install_dependencies
    show_menu
}

main

