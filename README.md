# SOCKS5服务器一键安装脚本

快速在Linux服务器上部署SOCKS5代理服务器

## 系统要求

- Ubuntu 18.04+ / Debian 9+ / CentOS 7+
- Root权限
- 网络连接

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/你的用户名/socks5-installer/main/install.sh)
功能特性

✅ 支持Ubuntu/Debian/CentOS
✅ 自动检测系统环境
✅ 支持用户名密码认证
✅ 支持无认证模式
✅ 自动配置防火墙
✅ SystemD服务管理
✅ 详细的错误诊断

使用说明
安装过程

选择端口（默认1080）
选择认证方式
设置用户名密码（可选）
自动完成安装配置

服务管理
bash# 启动服务
systemctl start danted

# 停止服务
systemctl stop danted

# 重启服务
systemctl restart danted

# 查看状态
systemctl status danted

# 查看日志
tail -f /var/log/danted.log
客户端配置

代理类型：SOCKS5
服务器：你的服务器IP
端口：安装时设置的端口
认证：根据安装时选择

故障排除
bash# 测试配置
danted -v -f /etc/danted.conf

# 检查端口
netstat -tlnp | grep 端口号

# 查看详细日志
journalctl -u danted -f
安全建议

建议使用用户名密码认证
定期更换密码
配置防火墙限制访问
监控服务器流量

支持
如有问题请提交Issue或联系作者。
