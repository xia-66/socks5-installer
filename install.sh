#!/usr/bin/env bash

#================================================================
#	脚本名称: SOCKS5 一键安装/卸载脚本 (基于gost)
#	系统支持: CentOS 7+, Debian 8+, Ubuntu 16+
#	作者:       Your Name
#	项目地址:   https://github.com/ginuerzh/gost
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
        read -p "请输入 SOCKS5 代理的密码: " SOCKS5_PASS
        while [ -z "$SOCKS5_PASS" ]; do
            echo -e "${RED}密码不能为空！${PLAIN}"
            read -p "请重新输入 SOCKS5 代理的密码: " SOCKS5_PASS
        done
        AUTH_INFO="${SOCKS5_USER}:${SOCKS5_PASS}"
    fi

    # 下载并安装 gost
    ARCH=$(get_arch)
    DOWNLOAD_URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost-linux-${ARCH}-${GOST_VERSION}.tar.gz"

    echo -e "${YELLOW}正在从 GitHub 下载 gost v${GOST_VERSION} for ${ARCH}...${PLAIN}"
    curl -sL "$DOWNLOAD_URL" -o "/tmp/gost.tar.gz"
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败！请检查网络或 GitHub Release 链接。${PLAIN}"
        exit 1
    fi

    echo -e "${YELLOW}正在解压并安装...${PLAIN}"
    tar -zxf "/tmp/gost.tar.gz" -C "/tmp/"
    mv "/tmp/gost-linux-${ARCH}/gost" "${GOST_INSTALL_PATH}/gost"
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
    echo "{\"port\": \"${SOCKS5_PORT}\", \"user\": \"${SOCKS5_USER}\", \"pass\": \"${SOCKS5_PASS}\"}" > "$GOST_CONFIG_FILE"


    # 启动服务
    echo -e "${YELLOW}正在启动并设置开机自启...${PLAIN}"
    systemctl daemon-reload
    systemctl enable gost
    systemctl start gost

    # 配置防火墙
    echo -e "${YELLOW}正在配置防火墙...${PLAIN}"
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --zone=public --add-port=${SOCKS5_PORT}/tcp --permanent
        firewall-cmd --reload
    elif command -v ufw &> /dev/null; then
        ufw allow ${SOCKS5_PORT}/tcp
        ufw reload
    else
        echo -e "${YELLOW}警告: 未检测到 firewalld 或 ufw，请手动开放端口 ${SOCKS5_PORT}。${PLAIN}"
    fi

    # 显示安装结果
    sleep 2
    if systemctl is-active --quiet gost; then
        echo -e "${GREEN}===== SOCKS5 代理安装成功！=====${PLAIN}"
        echo -e "地址:   $(curl -s ip.sb)"
        echo -e "端口:   ${GREEN}${SOCKS5_PORT}${PLAIN}"
        if [ -n "$SOCKS5_USER" ]; then
            echo -e "用户名: ${GREEN}${SOCKS5_USER}${PLAIN}"
            echo -e "密码:   ${GREEN}${SOCKS5_PASS}${PLAIN}"
        else
            echo -e "认证:   ${YELLOW}未设置${PLAIN}"
        fi
        echo -e "\n${YELLOW}请在客户端中使用以上信息进行连接。${PLAIN}"
    else
        echo -e "${RED}安装失败！请查看服务状态以获取更多信息:${PLAIN}"
        echo -e "journalctl -u gost -n 20"
    fi
}

# 卸载 gost
uninstall_gost() {
    if [ ! -f "$GOST_SERVICE_FILE" ]; then
        echo -e "${RED}错误: 未检测到 gost 安装。${PLAIN}"
        exit 1
    fi

    echo -e "${YELLOW}===== 开始卸载 SOCKS5 代理 =====${PLAIN}"

    # 停止并禁用服务
    systemctl stop gost
    systemctl disable gost

    # 删除服务文件和二进制文件
    rm -f "$GOST_SERVICE_FILE"
    rm -f "${GOST_INSTALL_PATH}/gost"
    rm -rf "$GOST_CONFIG_DIR"

    systemctl daemon-reload

    # 关闭防火墙端口
    SOCKS5_PORT=$(grep -oP '"port":\s*"\K[^"]+' "$GOST_CONFIG_FILE" 2>/dev/null)
    if [ -n "$SOCKS5_PORT" ]; then
        echo -e "${YELLOW}正在关闭防火墙端口 ${SOCKS5_PORT}...${PLAIN}"
        if command -v firewall-cmd &> /dev/null; then
            firewall-cmd --zone=public --remove-port=${SOCKS5_PORT}/tcp --permanent
            firewall-cmd --reload
        elif command -v ufw &> /dev/null; then
            ufw delete allow ${SOCKS5_PORT}/tcp
            ufw reload
        fi
    fi

    echo -e "${GREEN}SOCKS5 代理已成功卸载！${PLAIN}"
}

# 查看状态
check_status() {
    if [ ! -f "$GOST_SERVICE_FILE" ]; then
        echo -e "${RED}错误: 未检测到 gost 安装。${PLAIN}"
        exit 1
    fi
    systemctl status gost --no-pager -l
}

# 显示主菜单
show_menu() {
    clear
    echo "=================================================="
    echo " SOCKS5 一键安装/卸载脚本 (基于 gost)"
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

