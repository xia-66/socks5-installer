# 🔥 SOCKS5 服务器一键安装脚本

> 快速在 Linux 服务器上部署 SOCKS5 代理服务器

---

## 📋 系统要求

- **操作系统**: Ubuntu 18.04+ / Debian 9+ / CentOS 7+
- **权限要求**: Root 权限
- **网络要求**: 稳定的网络连接

---

## ⚡ 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xia-66/socks5-installer/main/install.sh)
```

---

## ✨ 功能特性

| 特性 | 说明 |
|------|------|
| 🐧 **多系统支持** | 支持 Ubuntu/Debian/CentOS |
| 🔍 **智能检测** | 自动检测系统环境 |
| 🔐 **认证方式** | 支持用户名密码认证 |
| 🚀 **免认证模式** | 支持无认证快速模式 |
| 🛡️ **防火墙配置** | 自动配置防火墙规则 |
| ⚙️ **服务管理** | SystemD 服务管理 |
| 🔧 **错误诊断** | 详细的错误诊断功能 |

---

## 📖 使用说明

### 🚀 安装过程

1. **选择端口** - 默认端口 `1080`
2. **选择认证方式** - 用户名密码认证或无认证模式
3. **设置凭据** - 设置用户名密码（认证模式）
4. **自动配置** - 脚本自动完成安装和配置

### 🛠️ 服务管理

```bash
# 启动服务
systemctl start danted

# 停止服务
systemctl stop danted

# 重启服务
systemctl restart danted

# 查看状态
systemctl status danted

# 查看日志
tail -f /var/log/danted.log
```

### 💻 客户端配置

| 配置项 | 值 |
|--------|-----|
| **代理类型** | SOCKS5 |
| **服务器地址** | 你的服务器 IP |
| **端口** | 安装时设置的端口 |
| **认证** | 根据安装时选择 |

---

## 🔧 故障排除

### 检查配置文件
```bash
# 测试配置
danted -v -f /etc/danted.conf
```

### 检查端口状态
```bash
# 检查端口占用
netstat -tlnp | grep 端口号
```

### 查看详细日志
```bash
# 实时查看服务日志
journalctl -u danted -f
```

---

## 🔒 安全建议

> ⚠️ **重要提醒**: 请务必遵循以下安全建议

- 🔐 **启用认证** - 强烈建议使用用户名密码认证
- 🔄 **定期更换** - 定期更换密码保证安全
- 🛡️ **防火墙配置** - 配置防火墙限制访问来源
- 📊 **流量监控** - 定期监控服务器流量使用情况
- 🚫 **禁止滥用** - 请勿用于违法违规活动

---

## 📞 技术支持

如果您在使用过程中遇到任何问题，请通过以下方式寻求帮助：

- 📝 **提交 Issue** - [GitHub Issues](https://github.com/xia-66/socks5-installer/issues)
- 📧 **联系作者** - 发送邮件至 heiyu@linux.do

---


**⭐ 如果这个项目对您有帮助，请给个 Star 支持一下！**

