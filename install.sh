#!/bin/bash

# SOCKS5服务器管理脚本 (增强版)
# 支持 Ubuntu/Debian/CentOS 系统
# 功能: 安装、卸载、状态查看、使用统计

# 配置文件路径
CONFIG_DIR="/etc/socks5-manager"
STATS_FILE="$CONFIG_DIR/usage_stats.log"
INSTALL_INFO="$CONFIG_DIR/install_info.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

log_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

# 记录使用统计
log_usage() {
    local action="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$CONFIG_DIR"
    echo "[$timestamp] $action" >> "$STATS_FILE"
}

# 保存安装信息
save_install_info() {
    mkdir -p "$CONFIG_DIR"
    cat > "$INSTALL_INFO" << EOF
SOCKS_PORT=$SOCKS_PORT
USE_AUTH=$USE_AUTH
SOCKS_USER=$SOCKS_USER
SERVER_IP=$SERVER_IP
INTERFACE=$INTERFACE
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
SCRIPT_VERSION=2.0
EOF
    log_usage "Installation completed - Port:$SOCKS_PORT Auth:$USE_AUTH"
}

# 读取安装信息
load_install_info() {
    if [[ -f "$INSTALL_INFO" ]]; then
        source "$INSTALL_INFO"
        return 0
    else
        return 1
    fi
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

# 检查是否已安装
check_installation() {
    if systemctl list-unit-files | grep -q "danted.service"; then
        return 0  # 已安装
    else
        return 1  # 未安装
    fi
}

# 显示主菜单
show_menu() {
    echo
    echo "=================================================="
    echo -e "${BLUE}SOCKS5 服务器管理脚本 v2.0${NC}"
    echo "=================================================="
    echo
    echo -e "${CYAN}请选择操作:${NC}"
    echo "1) 安装 SOCKS5 服务器"
    echo "2) 卸载 SOCKS5 服务器"
    echo "3) 查看服务状态"
    echo "4) 重启服务"
    echo "5) 查看使用统计"
    echo "6) 查看连接信息"
    echo "7) 修改配置"
    echo "8) 查看实时日志"
    echo "0) 退出"
    echo
}

# 安装依赖
install_dependencies() {
    log_info "更新系统并安装依赖..."
    
    if [[ $OS == "centos" ]]; then
        $PM update -y
        $PM install -y epel-release
        $PM install -y dante-server net-tools
    else
        $PM update -y
        $PM install -y dante-server net-tools
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
    SERVER_IP=$(curl -s --max-time 10 ipv4.icanhazip.com)
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
    
    # 检查端口是否被占用
    if netstat -tlnp | grep ":$SOCKS_PORT " > /dev/null; then
        log_error "端口 $SOCKS_PORT 已被占用，请选择其他端口"
        get_user_input
        return
    fi
    
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
        read -p "请输入用户名: " SOCKS_USER
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
        cp /etc/danted.conf /etc/danted.conf.backup.$(date +%Y%m%d_%H%M%S)
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
# Generated by SOCKS5 Manager Script v2.0
# $(date)

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
# Generated by SOCKS5 Manager Script v2.0
# $(date)

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
            service iptables save 2>/dev/null || true
        else
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        log_info "Iptables防火墙规则已添加"
    else
        log_warn "未检测到防火墙，请手动开放端口 $SOCKS_PORT"
    fi
}

# 启动服务
start_service() {
    log_info "配置并启动Dante服务..."
    
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
Documentation=man:danted(8)
After=network.target

[Service]
Type=forking
PIDFile=/var/run/danted.pid
ExecStart=/usr/sbin/danted -f /etc/danted.conf
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
User=root

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
    sleep 3
    
    if systemctl is-active --quiet danted; then
        log_success "Dante服务启动成功"
    else
        log_error "Dante服务启动失败，查看详细错误信息："
        systemctl status danted --no-pager
        log_error "查看日志："
        journalctl -u danted --no-pager -l
        exit 1
    fi
}

# 卸载服务
uninstall_service() {
    log_info "开始卸载SOCKS5服务器..."
    log_usage "Uninstall initiated"
    
    read -p "确认要卸载SOCKS5服务器吗？(y/N): " confirm
    if [[ $confirm != [yY] ]]; then
        log_info "取消卸载"
        return
    fi
    
    # 停止并禁用服务
    if systemctl is-active --quiet danted; then
        log_info "停止Dante服务..."
        systemctl stop danted
    fi
    
    if systemctl is-enabled --quiet danted; then
        log_info "禁用Dante服务..."
        systemctl disable danted
    fi
    
    # 删除服务文件
    if [[ -f /etc/systemd/system/danted.service ]]; then
        rm -f /etc/systemd/system/danted.service
        log_info "删除systemd服务文件"
    fi
    
    systemctl daemon-reload
    
    # 删除配置文件（备份后删除）
    if [[ -f /etc/danted.conf ]]; then
        cp /etc/danted.conf /etc/danted.conf.uninstall.backup.$(date +%Y%m%d_%H%M%S)
        rm -f /etc/danted.conf
        log_info "删除配置文件（已备份）"
    fi
    
    # 删除日志文件
    read -p "是否删除日志文件？(y/N): " del_logs
    if [[ $del_logs == [yY] ]]; then
        rm -f /var/log/danted.log
        log_info "删除日志文件"
    fi
    
    # 删除用户（如果存在且是由脚本创建的）
    if load_install_info && [[ $USE_AUTH == true ]] && [[ -n $SOCKS_USER ]]; then
        read -p "是否删除SOCKS用户 $SOCKS_USER？(y/N): " del_user
        if [[ $del_user == [yY] ]]; then
            if id "$SOCKS_USER" &>/dev/null; then
                userdel $SOCKS_USER 2>/dev/null || true
                log_info "删除用户 $SOCKS_USER"
            fi
        fi
    fi
    
    # 清理防火墙规则
    if load_install_info && [[ -n $SOCKS_PORT ]]; then
        read -p "是否删除防火墙规则（端口 $SOCKS_PORT）？(y/N): " del_fw
        if [[ $del_fw == [yY] ]]; then
            # UFW
            if command -v ufw &> /dev/null; then
                ufw delete allow $SOCKS_PORT/tcp 2>/dev/null || true
                log_info "删除UFW防火墙规则"
            fi
            # Firewalld
            if command -v firewall-cmd &> /dev/null; then
                firewall-cmd --permanent --remove-port=$SOCKS_PORT/tcp 2>/dev/null || true
                firewall-cmd --reload 2>/dev/null || true
                log_info "删除Firewalld防火墙规则"
            fi
            # Iptables (需要手动处理)
            if command -v iptables &> /dev/null; then
                log_warn "请手动删除iptables规则: iptables -D INPUT -p tcp --dport $SOCKS_PORT -j ACCEPT"
            fi
        fi
    fi
    
    # 卸载软件包
    read -p "是否卸载dante-server软件包？(y/N): " uninstall_pkg
    if [[ $uninstall_pkg == [yY] ]]; then
        if [[ $OS == "centos" ]]; then
            yum remove -y dante-server
        else
            apt remove -y dante-server
        fi
        log_info "卸载dante-server软件包"
    fi
    
    # 删除管理文件
    read -p "是否删除脚本配置文件和统计数据？(y/N): " del_config
    if [[ $del_config == [yY] ]]; then
        rm -rf "$CONFIG_DIR"
        log_info "删除脚本配置文件"
    else
        log_usage "Uninstall completed (config preserved)"
    fi
    
    log_success "SOCKS5服务器卸载完成！"
}

# 查看服务状态
show_status() {
    echo
    echo "=================================================="
    echo -e "${BLUE}SOCKS5 服务器状态${NC}"
    echo "=================================================="
    
    if check_installation; then
        log_info "服务安装状态: 已安装"
        
        # 服务状态
        if systemctl is-active --quiet danted; then
            echo -e "服务状态: ${GREEN}运行中${NC}"
        else
            echo -e "服务状态: ${RED}已停止${NC}"
        fi
        
        # 开机自启
        if systemctl is-enabled --quiet danted; then
            echo -e "开机自启: ${GREEN}已启用${NC}"
        else
            echo -e "开机自启: ${RED}已禁用${NC}"
        fi
        
        # 显示配置信息
        if load_install_info; then
            echo
            echo -e "${CYAN}配置信息:${NC}"
            echo -e "服务器IP: ${GREEN}$SERVER_IP${NC}"
            echo -e "端口: ${GREEN}$SOCKS_PORT${NC}"
            echo -e "认证模式: ${GREEN}$([ "$USE_AUTH" == "true" ] && echo "用户名密码" || echo "无认证")${NC}"
            if [[ $USE_AUTH == true ]]; then
                echo -e "用户名: ${GREEN}$SOCKS_USER${NC}"
            fi
            echo -e "安装时间: ${GREEN}$INSTALL_DATE${NC}"
            
            # 端口监听状态
            echo
            if netstat -tlnp 2>/dev/null | grep ":$SOCKS_PORT " > /dev/null; then
                echo -e "端口监听: ${GREEN}正常${NC}"
            else
                echo -e "端口监听: ${RED}异常${NC}"
            fi
        fi
        
        # 系统资源使用
        echo
        echo -e "${CYAN}系统资源:${NC}"
        local mem_usage=$(ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | grep danted | grep -v grep | head -1 | awk '{print $4}')
        local cpu_usage=$(ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | grep danted | grep -v grep | head -1 | awk '{print $5}')
        echo -e "内存使用: ${GREEN}${mem_usage:-0}%${NC}"
        echo -e "CPU使用: ${GREEN}${cpu_usage:-0}%${NC}"
        
    else
        log_warn "SOCKS5服务器未安装"
    fi
    
    log_usage "Status checked"
}

# 查看使用统计
show_usage_stats() {
    echo
    echo "=================================================="
    echo -e "${BLUE}使用统计${NC}"
    echo "=================================================="
    
    if [[ -f "$STATS_FILE" ]]; then
        echo -e "${CYAN}最近10条操作记录:${NC}"
        tail -10 "$STATS_FILE"
        
        echo
        echo -e "${CYAN}统计摘要:${NC}"
        local total_ops=$(wc -l < "$STATS_FILE")
        local installs=$(grep -c "Installation completed" "$STATS_FILE" 2>/dev/null || echo "0")
        local uninstalls=$(grep -c "Uninstall" "$STATS_FILE" 2>/dev/null || echo "0")
        local restarts=$(grep -c "Service restarted" "$STATS_FILE" 2>/dev/null || echo "0")
        local status_checks=$(grep -c "Status checked" "$STATS_FILE" 2>/dev/null || echo "0")
        
        echo -e "总操作次数: ${GREEN}$total_ops${NC}"
        echo -e "安装次数: ${GREEN}$installs${NC}"
        echo -e "卸载次数: ${GREEN}$uninstalls${NC}"
        echo -e "重启次数: ${GREEN}$restarts${NC}"
        echo -e "状态查询: ${GREEN}$status_checks${NC}"
        
        echo
        echo -e "${CYAN}连接统计 (基于日志):${NC}"
        if [[ -f /var/log/danted.log ]]; then
            local connections=$(grep -c "connect" /var/log/danted.log 2>/dev/null || echo "0")
            local today_conn=$(grep "$(date +%Y/%m/%d)" /var/log/danted.log 2>/dev/null | grep -c "connect" || echo "0")
            echo -e "总连接次数: ${GREEN}$connections${NC}"
            echo -e "今日连接: ${GREEN}$today_conn${NC}"
        else
            echo "暂无连接日志"
        fi
    else
        log_warn "暂无使用统计数据"
    fi
    
    log_usage "Stats viewed"
}

# 显示连接信息
show_connection_info() {
    echo
    echo "=================================================="
    echo -e "${BLUE}SOCKS5 连接信息${NC}"
    echo "=================================================="
    
    if load_install_info; then
        echo -e "${CYAN}连接配置:${NC}"
        echo -e "服务器地址: ${GREEN}$SERVER_IP${NC}"
        echo -e "端口: ${GREEN}$SOCKS_PORT${NC}"
        if [[ $USE_AUTH == true ]]; then
            echo -e "用户名: ${GREEN}$SOCKS_USER${NC}"
            echo -e "密码: ${GREEN}[请查看安装记录]${NC}"
            echo -e "认证: ${GREEN}用户名密码${NC}"
        else
            echo -e "认证: ${GREEN}无需认证${NC}"
        fi
        echo -e "协议: ${GREEN}SOCKS5${NC}"
        
        echo
        echo -e "${CYAN}客户端配置示例:${NC}"
        echo -e "${YELLOW}curl 示例:${NC}"
        if [[ $USE_AUTH == true ]]; then
            echo "curl --socks5-hostname $SOCKS_USER:密码@$SERVER_IP:$SOCKS_PORT http://httpbin.org/ip"
        else
            echo "curl --socks5-hostname $SERVER_IP:$SOCKS_PORT http://httpbin.org/ip"
        fi
        
        echo
        echo -e "${YELLOW}浏览器代理设置:${NC}"
        echo "SOCKS主机: $SERVER_IP"
        echo "端口: $SOCKS_PORT"
        echo "类型: SOCKS v5"
        if [[ $USE_AUTH == true ]]; then
            echo "需要认证: 是"
        else
            echo "需要认证: 否"
        fi
        
        if [[ $USE_AUTH == false ]]; then
            echo
            echo -e "${RED}⚠️  安全提示: 当前为无认证模式，建议：${NC}"
            echo -e "${RED}   1. 仅在可信网络中使用${NC}"
            echo -e "${RED}   2. 配置防火墙限制访问IP${NC}"
            echo -e "${RED}   3. 考虑启用用户认证${NC}"
        fi
    else
        log_error "无法加载连接信息，请检查是否已正确安装"
    fi
    
    log_usage "Connection info viewed"
}

# 重启服务
restart_service() {
    log_info "重启SOCKS5服务..."
    
    if check_installation; then
        systemctl restart danted
        sleep 2
        
        if systemctl is-active --quiet danted; then
            log_success "服务重启成功"
        else
            log_error "服务重启失败"
            systemctl status danted --no-pager
        fi
    else
        log_error "服务未安装"
    fi
    
    log_usage "Service restarted"
}

# 查看实时日志
show_logs() {
    echo -e "${CYAN}显示实时日志 (按 Ctrl+C 退出):${NC}"
    echo
    
    if [[ -f /var/log/danted.log ]]; then
        tail -f /var/log/danted.log
    else
        log_error "日志文件不存在"
        echo "尝试查看系统日志："
        journalctl -u danted -f
    fi
    
    log_usage "Logs viewed"
}

# 修改配置
modify_config() {
    log_info "修改SOCKS5配置..."
    
    if ! check_installation; then
        log_error "服务未安装，无法修改配置"
        return
    fi
    
    if ! load_install_info; then
        log_error "无法加载当前配置信息"
        return
    fi
    
    echo
    echo -e "${CYAN}当前配置:${NC}"
    echo "端口: $SOCKS_PORT"
    echo "认证: $([ "$USE_AUTH" == "true" ] && echo "启用 (用户名: $SOCKS_USER)" || echo "禁用")"
    
    echo
    echo "可修改的选项："
    echo "1) 更改端口"
    echo "2) 修改认证设置"
    echo "3) 完全重新配置"
    echo "0) 返回"
    
    read -p "请选择: " choice
    
    case $choice in
        1)
            read -p "请输入新端口 (当前: $SOCKS_PORT): " new_port
            if [[ -n $new_port ]] && [[ $new_port != $SOCKS_PORT ]]; then
                if netstat -tlnp | grep ":$new_port " > /dev/null; then
                    log_error "端口 $new_port 已被占用"
                    return
                fi
                
                # 更新防火墙
                configure_firewall_for_port $new_port
                
                # 更新配置
                SOCKS_PORT=$new_port
                configure_dante
                save_install_info
                restart_service
                log_success "端口已更新为 $new_port"
            fi
            ;;
        2)
            echo "认证设置："
            echo "1) 启用用户名密码认证"
            echo "2) 禁用认证"
            read -p "请选择: " auth_choice
            
            if [[ $auth_choice == "1" ]]; then
                read -p "用户名: " new_user
                read -s -p "密码: " new_pass
                echo
                
                if [[ -n $new_user ]] && [[ -n $new_pass ]]; then
                    USE_AUTH=true
                    SOCKS_USER=$new_user
                    SOCKS_PASS=$new_pass
                    create_system_user
                    configure_dante
                    save_install_info
                    restart_service
                    log_success "认证设置已更新"
                fi
            elif [[ $auth_choice == "2" ]]; then
                USE_AUTH=false
                SOCKS_USER=""
                configure_dante
                save_install_info
                restart_service
                log_success "已禁用认证"
            fi
            ;;
        3)
            log_info "重新配置所有设置..."
            get_user_input
            create_system_user
            configure_dante
            configure_firewall
            save_install_info
            restart_service
            log_success "配置已更新"
            ;;
        0)
            return
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
    
    log_usage "Configuration modified"
}

# 配置特定端口的防火墙
configure_firewall_for_port() {
    local port=$1
    log_info "为端口 $port 配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        ufw allow $port/tcp
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$port/tcp
        firewall-cmd --reload
    elif command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport $port -j ACCEPT
        if [[ $OS == "centos" ]]; then
            service iptables save 2>/dev/null || true
        else
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
    fi
}

# 完整安装流程
install_socks5() {
    echo
    log_info "开始安装SOCKS5服务器..."
    
    if check_installation; then
        log_warn "检测到已安装的SOCKS5服务器"
        read -p "是否重新安装？(y/N): " reinstall
        if [[ $reinstall != [yY] ]]; then
            log_info "取消安装"
            return
        fi
        log_info "开始重新安装..."
    fi
    
    detect_os
    install_dependencies
    get_server_ip
    get_user_input
    create_system_user
    configure_dante
    configure_firewall
    start_service
    save_install_info
    
    # 测试连接
    test_connection
    
    # 显示安装完成信息
    show_install_complete
}

# 测试连接
test_connection() {
    log_info "测试SOCKS5服务器连接..."
    
    # 检查端口监听
    if netstat -tlnp | grep ":$SOCKS_PORT " > /dev/null; then
        log_success "SOCKS5服务器正在监听端口 $SOCKS_PORT"
    else
        log_error "端口 $SOCKS_PORT 未在监听，请检查服务状态"
        return 1
    fi
    
    # 简单的连接测试
    if command -v curl &> /dev/null; then
        log_info "执行连接测试..."
        if [[ $USE_AUTH == true ]]; then
            timeout 10 curl --socks5-hostname $SOCKS_USER:$SOCKS_PASS@127.0.0.1:$SOCKS_PORT http://httpbin.org/ip &>/dev/null
        else
            timeout 10 curl --socks5-hostname 127.0.0.1:$SOCKS_PORT http://httpbin.org/ip &>/dev/null
        fi
        
        if [[ $? -eq 0 ]]; then
            log_success "连接测试通过"
        else
            log_warn "连接测试失败，但服务可能仍然正常（可能是网络问题）"
        fi
    else
        log_info "curl未安装，跳过连接测试"
    fi
}

# 显示安装完成信息
show_install_complete() {
    echo
    echo "=================================================="
    log_success "SOCKS5服务器安装完成！"
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
    echo -e "管理脚本: ${YELLOW}bash $0${NC}"
    echo
    echo -e "${BLUE}测试命令:${NC}"
    if [[ $USE_AUTH == true ]]; then
        echo -e "${YELLOW}curl --socks5-hostname $SOCKS_USER:$SOCKS_PASS@$SERVER_IP:$SOCKS_PORT http://httpbin.org/ip${NC}"
    else
        echo -e "${YELLOW}curl --socks5-hostname $SERVER_IP:$SOCKS_PORT http://httpbin.org/ip${NC}"
    fi
    echo
    if [[ $USE_AUTH == false ]]; then
        echo -e "${RED}⚠️  安全警告: 当前为无认证模式，任何人都可以使用此代理！${NC}"
        echo -e "${RED}建议在可信网络环境中使用，或配置防火墙限制访问。${NC}"
        echo
    fi
    echo "=================================================="
}

# 主菜单处理
handle_menu() {
    while true; do
        show_menu
        read -p "请选择操作 [0-8]: " choice
        
        case $choice in
            1)
                install_socks5
                ;;
            2)
                uninstall_service
                ;;
            3)
                show_status
                ;;
            4)
                restart_service
                ;;
            5)
                show_usage_stats
                ;;
            6)
                show_connection_info
                ;;
            7)
                modify_config
                ;;
            8)
                show_logs
                ;;
            0)
                log_info "感谢使用SOCKS5管理脚本！"
                log_usage "Script exited"
                exit 0
                ;;
            *)
                log_error "无效选择，请输入 0-8"
                ;;
        esac
        
        echo
        read -p "按回车键继续..." -r
    done
}

# 命令行参数处理
handle_arguments() {
    case "${1:-}" in
        "install"|"-i"|"--install")
            install_socks5
            ;;
        "uninstall"|"-u"|"--uninstall")
            uninstall_service
            ;;
        "status"|"-s"|"--status")
            show_status
            ;;
        "restart"|"-r"|"--restart")
            restart_service
            ;;
        "stats"|"--stats")
            show_usage_stats
            ;;
        "info"|"--info")
            show_connection_info
            ;;
        "logs"|"-l"|"--logs")
            show_logs
            ;;
        "config"|"-c"|"--config")
            modify_config
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        "")
            # 无参数时显示菜单
            handle_menu
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
}

# 显示帮助信息
show_help() {
    echo
    echo "SOCKS5服务器管理脚本 v2.0"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  install, -i, --install     安装SOCKS5服务器"
    echo "  uninstall, -u, --uninstall 卸载SOCKS5服务器"
    echo "  status, -s, --status       查看服务状态"
    echo "  restart, -r, --restart     重启服务"
    echo "  stats, --stats             查看使用统计"
    echo "  info, --info               查看连接信息"
    echo "  logs, -l, --logs           查看实时日志"
    echo "  config, -c, --config       修改配置"
    echo "  help, -h, --help           显示帮助信息"
    echo
    echo "无参数运行时将显示交互式菜单。"
    echo
    echo "示例:"
    echo "  $0 install                 # 安装服务"
    echo "  $0 status                  # 查看状态"
    echo "  $0 logs                    # 查看日志"
    echo
}

# 脚本初始化
init_script() {
    # 检查root权限
    check_root
    
    # 初始化统计
    log_usage "Script started with args: ${*:-'none'}"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
}

# 主函数
main() {
    # 脚本初始化
    init_script
    
    # 处理命令行参数
    handle_arguments "$@"
}

# 信号处理
trap 'echo; log_info "脚本被中断"; log_usage "Script interrupted"; exit 130' INT TERM

# 运行主函数
main "$@"
