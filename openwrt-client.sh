#!/bin/bash
# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
 echo "Please run as root"
 exit 1
fi

# Install bc based on system package manager
if command -v opkg > /dev/null; then
     opkg install bc
else
    echo "It's not openwrt."
    exit 1
fi

# Function to detect main network interface
get_main_interface() {
   local interfaces=$(ip -o link show | \
       awk -F': ' '$2 !~ /^((lo|docker|veth|br-|virbr|tun|vnet|wg|vmbr|dummy|gre|sit|vlan|lxc|lxd|warp|tap))/{print $2}' | \
       grep -v '@')
   
   local interface_count=$(echo "$interfaces" | wc -l)
   
   # 格式化流量大小的函数
   format_bytes() {
       local bytes=$1
       if [ $bytes -lt 1024 ]; then
           echo "${bytes} B"
       elif [ $bytes -lt 1048576 ]; then # 1024*1024
           echo "$(echo "scale=2; $bytes/1024" | bc) KB"
       elif [ $bytes -lt 1048576 ]; then # 1024*1024
           echo "$(echo "scale=2; $bytes/1024" | bc) KB"
       elif [ $bytes -lt 1073741824 ]; then # 1024*1024*1024
           echo "$(echo "scale=2; $bytes/1024/1024" | bc) MB"
       elif [ $bytes -lt 1099511627776 ]; then # 1024*1024*1024*1024
           echo "$(echo "scale=2; $bytes/1024/1024/1024" | bc) GB"
       else
           echo "$(echo "scale=2; $bytes/1024/1024/1024/1024" | bc) TB"
       fi
   }
   
   # 显示网卡流量的函数
   show_interface_traffic() {
       local interface=$1
       if [ -d "/sys/class/net/$interface" ]; then
           local rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes)
           local tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes)
           echo "   ↓ Received: $(format_bytes $rx_bytes)"
           echo "   ↑ Sent: $(format_bytes $tx_bytes)"
       else
           echo "   无法读取流量信息"
       fi
   }
   
   # 如果没有找到合适的接口或有多个接口时显示所有可用接口
   echo "所有可用的网卡接口:" >&2
   echo "------------------------" >&2
   local i=1
   while read -r interface; do
       echo "$i) $interface" >&2
       show_interface_traffic "$interface" >&2
       i=$((i+1))
   done < <(ip -o link show | grep -v "lo:" | awk -F': ' '{print $2}')
   echo "------------------------" >&2
   
   while true; do
       read -p "请选择网卡，如上方显示异常或没有需要的网卡，请直接填入网卡名: " selection
       
       # 检查是否为数字
       if [[ "$selection" =~ ^[0-9]+$ ]]; then
           # 如果是数字，检查是否在有效范围内
           selected_interface=$(ip -o link show | grep -v "lo:" | sed -n "${selection}p" | awk -F': ' '{print $2}')
           if [ -n "$selected_interface" ]; then
               echo "已选择网卡: $selected_interface" >&2
               echo "$selected_interface"
               break
           else
               echo "无效的选择，请重新输入" >&2
               continue
           fi
       else
           # 直接使用输入的网卡名
           echo "已选择网卡: $selection" >&2
           echo "$selection"
           break
       fi
   done
}

# Check if all arguments are provided
if [ "$#" -ne 3 ]; then
 echo "Usage: $0 <auth_secret> <url> <name>"
 echo "Example: $0 your_secret wss://api.123.321 HK-Akile"
 exit 1
fi

# Get system architecture
ARCH=$(uname -m)
CLIENT_FILE="akile_client-linux-amd64"

# Set appropriate client file based on architecture
if [ "$ARCH" = "x86_64" ]; then
 CLIENT_FILE="akile_client-linux-amd64"
elif [ "$ARCH" = "aarch64" ]; then
 CLIENT_FILE="akile_client-linux-arm64"
elif [ "$ARCH" = "x86_64" ] && [ "$(uname -s)" = "Darwin" ]; then
 CLIENT_FILE="akile_client-darwin-amd64"
else
 echo "Unsupported architecture: $ARCH"
 exit 1
fi

# Assign command line arguments to variables
auth_secret="$1"
url="$2"
monitor_name="$3"

# Get network interface
net_name=$(get_main_interface)
echo "Using network interface: $net_name"

# Create directory and change to it
mkdir -p /etc/ak_monitor/
cd /etc/ak_monitor/

# Download client
wget -O client https://az-kr.sdcom-ghproxy.us.kg/https://github.com/akile-network/akile_monitor/releases/latest/download/$CLIENT_FILE
chmod 777 client

# Create systemd service file
cat > /etc/ak_monitor/start.sh << 'EOF'
cd /etc/ak_monitor/
./client
EOF

# Set proper permissions
chmod 644 /etc/ak_monitor/client.json
chmod 644 /etc/ak_monitor/start.sh
chmod +x /etc/ak_monitor/start.sh

nohup sh /etc/ak_monitor/start.sh > /tmp/output.log 2>/tmp/output.log &
echo "It's running."

