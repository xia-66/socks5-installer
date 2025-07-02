#!/bin/bash

# SOCKS5服务器一键安装脚本
# 支持 Ubuntu/Debian/CentOS 系统

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用root权限运行此脚本"
        exit 1
    fi
}

# 检测系统类型
detect_os() {
    if [[ -f /etc/redhat-release ]]; then
        OS="centos"
        PM="yum"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        PM="apt"
    else
        log_error "不支持的操作系统"
        exit 1
    fi
    log_info "检测到系统: $OS"
}

# 安装依赖
install_dependencies() {
    log_info "更新系统并安装依赖..."
    
    if [[ $OS == "centos" ]]; then
        $PM update -y
        $PM install -y epel-release
        $PM install -y dante-server
    else
        $PM update -y
        $PM install -y dante-server
    fi
    
    if [[ $? -eq 0 ]]; then
        log_info "依赖安装完成"
    else
        log_error "依赖安装失败"
        exit 1
    fi
}

# 获取服务器IP和网络接口
get_server_ip() {
    SERVER_IP=$(curl -s ipv4.icanhazip.com)
    if [[ -z $SERVER_IP ]]; then
        SERVER_IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
    fi
    
    # 获取主网络接口
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -z $INTERFACE ]]; then
        INTERFACE=$(ip link show | grep -E "^[0-9]+:" | grep -v lo | awk -F: '{print $2}' | tr -d ' ' | head -n1)
    fi
    
    log_info "服务器IP: $SERVER_IP"
    log_info "网络接口: $INTERFACE"
}

# 创建用户输入函数
get_user_input() {
    echo
    read -p "请输入SOCKS5端口 (默认1080): " SOCKS_PORT
    SOCKS_PORT=${SOCKS_PORT:-1080}
    
    echo
    echo -e "${YELLOW}认证设置:${NC}"
    echo "1) 无需认证 (任何人都可以连接)"
    echo "2) 用户名密码认证 (推荐)"
    read -p "请选择认证方式 (1-2, 默认2): " AUTH_METHOD
    AUTH_METHOD=${AUTH_METHOD:-2}
    
    if [[ $AUTH_METHOD == "1" ]]; then
        USE_AUTH=false
        log_info "已选择无认证模式"
    else
        USE_AUTH=true
        read -p "请输入用户名 (留空则无认证): " SOCKS_USER
        if [[ -n $SOCKS_USER ]]; then
            read -s -p "请输入密码: " SOCKS_PASS
            echo
            if [[ -z $SOCKS_PASS ]]; then
                log_warn "密码为空，将使用无认证模式"
                USE_AUTH=false
            fi
        else
            log_warn "用户名为空，将使用无认证模式"
            USE_AUTH=false
        fi
    fi
    
    echo
    log_info "配置信息:"
    log_info "端口: $SOCKS_PORT"
    if [[ $USE_AUTH == true ]]; then
        log_info "认证模式: 用户名密码"
        log_info "用户名: $SOCKS_USER"
        log_info "密码: [已设置]"
    else
        log_info "认证模式: 无需认证"
    fi
}

# 创建系统用户
create_system_user() {
    if [[ $USE_AUTH == true ]]; then
        log_info "创建系统用户..."
        
        if id "$SOCKS_USER" &>/dev/null; then
            log_warn "用户 $SOCKS_USER 已存在"
        else
            useradd -r -s /bin/false $SOCKS_USER
            log_info "用户 $SOCKS_USER 创建成功"
        fi
        
        # 设置密码
        echo "$SOCKS_USER:$SOCKS_PASS" | chpasswd
        log_info "用户密码设置完成"
    else
        log_info "无认证模式，跳过用户创建"
    fi
}

# 配置Dante
configure_dante() {
    log_info "配置Dante SOCKS服务器..."
    
    # 备份原配置
    if [[ -f /etc/danted.conf ]]; then
        cp /etc/danted.conf /etc/danted.conf.backup
    fi
    
    # 创建日志目录
    mkdir -p /var/log
    touch /var/log/danted.log
    chmod 644 /var/log/danted.log
    
    # 根据认证模式创建不同的配置文件
    if [[ $USE_AUTH == true ]]; then
        # 用户名密码认证配置
        cat > /etc/danted.conf << EOF
# Dante SOCKS5 服务器配置 (用户名密码认证)

# 日志设置
logoutput: /var/log/danted.log
debug: 1

# 内部接口（服务器接收连接的接口）
internal: 0.0.0.0 port = $SOCKS_PORT

# 外部接口（服务器转发数据的接口）
external: $INTERFACE

# 认证方法
socksmethod: username
clientmethod: none

# 用户规则
user.privileged: root
user.unprivileged: nobody

# 客户端连接规则
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}

# SOCKS连接规则
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
    socksmethod: username
}
EOF
    else
        # 无认证配置
        cat > /etc/danted.conf << EOF
# Dante SOCKS5 服务器配置 (无认证)

# 日志设置
logoutput: /var/log/danted.log
debug: 1

# 内部接口（服务器接收连接的接口）
internal: 0.0.0.0 port = $SOCKS_PORT

# 外部接口（服务器转发数据的接口）
external: $INTERFACE

# 认证方法
socksmethod: none
clientmethod: none

# 用户规则
user.privileged: root
user.unprivileged: nobody

# 客户端连接规则
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}

# SOCKS连接规则
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
    socksmethod: none
}
EOF
    fi

    log_info "Dante配置完成"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    # 检查并配置防火墙
    if command -v ufw &> /dev/null; then
        ufw allow $SOCKS_PORT/tcp
        log_info "UFW防火墙规则已添加"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$SOCKS_PORT/tcp
        firewall-cmd --reload
        log_info "Firewalld防火墙规则已添加"
    elif command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport $SOCKS_PORT -j ACCEPT
        # 保存iptables规则
        if [[ $OS == "centos" ]]; then
            service iptables save
        else
            iptables-save > /etc/iptables/rules.v4
        fi
        log_info "Iptables防火墙规则已添加"
    else
        log_warn "未检测到防火墙，请手动开放端口 $SOCKS_PORT"
    fi
}

# 启动服务
start_service() {
    log_info "启动Dante服务..."
    
    # 先测试配置文件
    log_info "测试配置文件..."
    if danted -v -f /etc/danted.conf; then
        log_info "配置文件验证通过"
    else
        log_error "配置文件验证失败，请检查配置"
        exit 1
    fi
    
    # 创建systemd服务文件
    cat > /etc/systemd/system/danted.service << EOF
[Unit]
Description=Dante SOCKS5 Server
After=network.target

[Service]
Type=forking
PIDFile=/var/run/danted.pid
ExecStart=/usr/sbin/danted -f /etc/danted.conf
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # 重载systemd并停止可能运行的服务
    systemctl daemon-reload
    systemctl stop danted 2>/dev/null || true
    
    # 启动服务
    systemctl enable danted
    systemctl start danted
    
    # 等待服务启动
    sleep 2
    
    if systemctl is-active --quiet danted; then
        log_info "Dante服务启动成功"
    else
        log_error "Dante服务启动失败，查看详细错误信息："
        systemctl status danted --no-pager
        log_error "查看日志："
        journalctl -u danted --no-pager -l
        exit 1
    fi
}

# 显示连接信息
show_connection_info() {
    echo
    echo "=================================================="
    log_info "SOCKS5服务器安装完成！"
    echo "=================================================="
    echo
    echo -e "${BLUE}连接信息:${NC}"
    echo -e "服务器地址: ${GREEN}$SERVER_IP${NC}"
    echo -e "端口: ${GREEN}$SOCKS_PORT${NC}"
    if [[ $USE_AUTH == true ]]; then
        echo -e "用户名: ${GREEN}$SOCKS_USER${NC}"
        echo -e "密码: ${GREEN}$SOCKS_PASS${NC}"
        echo -e "认证: ${GREEN}用户名密码${NC}"
    else
        echo -e "认证: ${GREEN}无需认证${NC}"
    fi
    echo -e "协议: ${GREEN}SOCKS5${NC}"
    echo
    echo -e "${BLUE}管理命令:${NC}"
    echo -e "启动服务: ${YELLOW}systemctl start danted${NC}"
    echo -e "停止服务: ${YELLOW}systemctl stop danted${NC}"
    echo -e "重启服务: ${YELLOW}systemctl restart danted${NC}"
    echo -e "查看状态: ${YELLOW}systemctl status danted${NC}"
    echo -e "查看日志: ${YELLOW}tail -f /var/log/danted.log${NC}"
    echo -e "查看系统日志: ${YELLOW}journalctl -u danted -f${NC}"
    echo
    echo -e "${BLUE}故障排除:${NC}"
    echo -e "测试配置: ${YELLOW}danted -v -f /etc/danted.conf${NC}"
    echo -e "手动启动: ${YELLOW}danted -f /etc/danted.conf${NC}"
    echo -e "检查端口: ${YELLOW}netstat -tlnp | grep $SOCKS_PORT${NC}"
    echo
    if [[ $USE_AUTH == false ]]; then
        echo -e "${RED}警告: 当前为无认证模式，任何人都可以使用此代理！${NC}"
        echo -e "${RED}建议在可信网络环境中使用，或配置防火墙限制访问。${NC}"
        echo
    fi
    echo "=================================================="
}

# 测试连接
test_connection() {
    log_info "测试SOCKS5服务器连接..."
    
    # 简单的端口检测
    if netstat -tlnp | grep :$SOCKS_PORT > /dev/null; then
        log_info "SOCKS5服务器正在监听端口 $SOCKS_PORT"
    else
        log_warn "端口 $SOCKS_PORT 未在监听，请检查服务状态"
    fi
}

# 主函数
main() {
    echo "=================================================="
    echo -e "${BLUE}SOCKS5服务器一键安装脚本${NC}"
    echo "=================================================="
    
    check_root
    detect_os
    install_dependencies
    get_server_ip
    get_user_input
    create_system_user
    configure_dante
    configure_firewall
    start_service
    test_connection
    show_connection_info
}

# 运行主函数
main "$@"