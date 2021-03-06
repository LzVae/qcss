#! /bin/bash
# Copyright (c) 2019 zhuxindong

kernel_ubuntu_url="http://kernel.ubuntu.com/~kernel-ppa/mainline/v4.10.2/linux-image-4.10.2-041002-generic_4.10.2-041002.201703120131_amd64.deb"
kernel_ubuntu_file="linux-image-4.10.2-041002-generic_4.10.2-041002.201703120131_amd64.deb"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'


os='ossystem'

check_os() {
    if [[ -f /etc/redhat-release ]]; then
        os="centos"
    elif cat /etc/issue | grep -Eqi "debian"; then
        os="debian"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        os="ubuntu"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
        os="centos"
    elif cat /proc/version | grep -Eqi "debian"; then
        os="debian"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        os="ubuntu"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        os="centos"
    fi
}



# 开启bbr加速start

install_bbr() {
	[[ -d "/proc/vz" ]] && echo -e "[${red}错误${plain}] 你的系统是OpenVZ架构的，不支持开启BBR。" && exit 1
	check_os
	check_bbr_status
	if [ $? -eq 0 ]
	then
		echo -e "[${green}提示${plain}] TCP BBR加速已经开启成功。"
        read -p "是否安装并配置shadowsocks? [y/n]" is_addss
        if [[ ${is_addss} == "y" || ${is_addss} == "Y" ]]; then
            install_ss
        else
            echo -e "[${green}提示${plain}] 取消安装。"
            exit 0
        fi

	fi
	check_kernel_version
	if [ $? -eq 0 ]
	then
		echo -e "[${green}提示${plain}] 你的系统版本高于4.9，直接开启BBR加速。"
		sysctl_config
		echo -e "[${green}提示${plain}] TCP BBR加速开启成功"
        read -p "是否安装并配置shadowsocks? [y/n]" is_addss
        if [[ ${is_addss} == "y" || ${is_addss} == "Y" ]]; then
            install_ss
        else
            echo -e "[${green}提示${plain}] 取消安装。"
            exit 0
        fi
	fi
	    
	if [[ x"${os}" == x"centos" ]]; then
        	install_elrepo
        	yum --enablerepo=elrepo-kernel -y install kernel-ml kernel-ml-devel
        	if [ $? -ne 0 ]; then
            		echo -e "[${red}错误${plain}] 安装内核失败，请自行检查。"
            		exit 1
        	fi
    	elif [[ x"${os}" == x"debian" || x"${os}" == x"ubuntu" ]]; then
        	[[ ! -e "/usr/bin/wget" ]] && apt-get -y -y update && apt-get -y -y install wget
        	#get_latest_version
        	#[ $? -ne 0 ] && echo -e "[${red}错误${plain}] 获取最新内核版本失败，请检查网络" && exit 1
       		 #wget -c -t3 -T60 -O ${deb_kernel_name} ${deb_kernel_url}
        	#if [ $? -ne 0 ]; then
            	#	echo -e "[${red}错误${plain}] 下载${deb_kernel_name}失败，请自行检查。"
            	#	exit 1
       		#fi
        	#dpkg -i ${deb_kernel_name}
        	#rm -fv ${deb_kernel_name}
		wget ${kernel_ubuntu_url}
		if [ $? -ne 0 ]
		then
			echo -e "[${red}错误${plain}] 下载内核失败，请自行检查。"
			exit 1
		fi
		dpkg -i ${kernel_ubuntu_file}
    	else
       	 	echo -e "[${red}错误${plain}] 脚本不支持该操作系统，请修改系统为CentOS/Debian/Ubuntu。"
        	exit 1
    	fi

    	install_config
    	sysctl_config
    	reboot_os
}

install_config() {
    if [[ x"${os}" == x"centos" ]]; then
        if centosversion 6; then
            if [ ! -f "/boot/grub/grub.conf" ]; then
                echo -e "[${red}错误${plain}] 没有找到/boot/grub/grub.conf文件。"
                exit 1
            fi
            sed -i 's/^default=.*/default=0/g' /boot/grub/grub.conf
        elif centosversion 7; then
            if [ ! -f "/boot/grub2/grub.cfg" ]; then
                echo -e "[${red}错误${plain}] 没有找到/boot/grub2/grub.cfg文件。"
                exit 1
            fi
            grub2-set-default 0
        fi
    elif [[ x"${os}" == x"debian" || x"${os}" == x"ubuntu" ]]; then
        /usr/sbin/update-grub
    fi
}

reboot_os() {
    echo
    echo -e "[${green}提示${plain}] 系统需要重启BBR才能生效。"
    read -p "是否立马重启 [y/n]" is_reboot
    if [[ ${is_reboot} == "y" || ${is_reboot} == "Y" ]]; then
        reboot
    else
        echo -e "[${green}提示${plain}] 取消重启。其自行执行reboot命令。"
        exit 0
    fi
}

check_bbr_status() {
    local param=$(sysctl net.ipv4.tcp_available_congestion_control | awk '{print $3}')
    if [[ x"${param}" == x"bbr" ]]; then
        return 0
    else
        return 1
    fi
}


sysctl_config() {
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
}

check_kernel_version() {
    local kernel_version=$(uname -r | cut -d- -f1)
    if version_ge ${kernel_version} 4.9; then
        return 0
    else
        return 1
    fi
}

install_ss() {
    echo -e "安装ss"

    echo -e "安装pip3"
    sudo apt-get -y update 
    sudo apt-get -y install python3-pip

    echo -e "安装shadowsocks"
    sudo pip3 install shadowsocks

    echo -e "[${green}提示${plain}] shadowsocks安装成功"
    install_ssmgr
}

install_ssmgr(){
    sudo ssserver -c /etc/shadowsocks.json -d stop
    sudo ssserver -m aes-256-cfb -p 12345 -k abcedf --manager-address 127.0.0.1:6000 -d stop
    sudo ssserver -m aes-256-cfb -p 12345 -k abcedf --manager-address 127.0.0.1:6000 -d start
    echo -e "[${green}提示${plain}] 开始安装shadowsocks-manager"
    echo -e "[${green}提示${plain}] 安装nodejs"
    sudo apt-get install -y curl
    sudo curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
    sudo apt-get install -y nodejs
    echo -e "[${green}提示${plain}] nodejs安装成功"

    echo -e "[${green}提示${plain}] 开始安装shadowsocks-manager"
    sudo npm i -g shadowsocks-manager --unsafe-perm
    echo -e "[${green}提示${plain}] shadowsocks-manager安装成功"

    sudo rm -rf ~/.ssmgr
    sudo mkdir ~/.ssmgr
    sudo cp ss.yml ~/.ssmgr/ss.yml
    sudo cp webgui.yml ~/.ssmgr/webgui.yml
    echo -e "[${green}提示${plain}] 配置文件拷贝成功"

    sudo apt-get -y install redis-server
    service redis start
    echo -e "[${green}提示${plain}] redis安装成功"

    sudo screen -dmS ssmgr ssmgr -c ~/.ssmgr/ss.yml
    sudo screen -dmS webgui ssmgr -c ~/.ssmgr/webgui.yml

    echo -e "[${green}提示${plain}] shadowsocks-manager安装成功"
    exit 0
}



# 开启bbr加速end

install_bbr