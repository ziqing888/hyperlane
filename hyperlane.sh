#!/bin/bash

LOG_FILE="/var/log/hyperlane_setup.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' 


curl -s https://raw.githubusercontent.com/ziqing888/logo.sh/main/logo.sh | bash

log() {
    echo -e "$1"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $1" >> $LOG_FILE
}

error_exit() {
    log "${RED}Error: $1${NC}"
    exit 1
}


if [ "$EUID" -ne 0 ]; then
    log "${RED}请以 root 权限运行此脚本！${NC}"
    exit 1
fi

# 检查日志路径是否可写
if [ ! -w "$(dirname "$LOG_FILE")" ]; then
    error_exit "日志路径不可写，请检查权限或调整路径：$(dirname "$LOG_FILE")"
fi

# 设置全局变量
DB_DIR="/opt/hyperlane_db_base"

# 确保路径存在并赋予适当权限
if [ ! -d "$DB_DIR" ]; then
    mkdir -p "$DB_DIR" && chmod -R 777 "$DB_DIR" || error_exit "创建数据库目录失败: $DB_DIR"
    log "${GREEN}数据库目录已创建: $DB_DIR${NC}"
else
    log "${GREEN}数据库目录已存在: $DB_DIR${NC}"
fi

# 检查系统环境
check_requirements() {
    log "${YELLOW}检查系统环境...${NC}"
    CPU=$(grep -c ^processor /proc/cpuinfo)
    RAM=$(free -m | awk '/Mem:/ { print $2 }')
    DISK=$(df -h / | awk '/\// { print $4 }' | sed 's/G//g')

    log "CPU核心数: $CPU"
    log "可用内存: ${RAM}MB"
    log "可用磁盘空间: ${DISK}GB"

    if [ "$CPU" -lt 2 ]; then
        error_exit "CPU核心数不足 (至少需要2核心)"
    fi

    if [ "$RAM" -lt 2000 ]; then
        error_exit "内存不足 (至少需要2GB)"
    fi

    if [ "${DISK%.*}" -lt 20 ]; then
        error_exit "磁盘空间不足 (至少需要20GB)"
    fi

    log "${GREEN}系统环境满足最低要求。${NC}"
}

# 安装 Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        log "${YELLOW}安装 Docker...${NC}"
        sudo apt-get update
        sudo apt-get install -y docker.io || error_exit "安装 Docker 失败"
        sudo systemctl start docker || error_exit "启动 Docker 服务失败"
        sudo systemctl enable docker || error_exit "设置 Docker 开机自启失败"
        log "${GREEN}Docker 已成功安装并启动！${NC}"
    else
        log "${GREEN}Docker 已安装，跳过此步骤。${NC}"
    fi
}

# 安装 Node.js 和 NVM
install_nvm_and_node() {
    if ! command -v nvm &> /dev/null; then
        log "${YELLOW}安装 NVM...${NC}"
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash || error_exit "安装 NVM 失败"
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        log "${GREEN}NVM 已成功安装！${NC}"
    else
        log "${GREEN}NVM 已安装，跳过此步骤。${NC}"
    fi

    if ! command -v node &> /dev/null; then
        log "${YELLOW}安装 Node.js v20...${NC}"
        nvm install 20 || error_exit "安装 Node.js 失败"
        log "${GREEN}Node.js 已成功安装！${NC}"
    else
        log "${GREEN}Node.js 已安装，跳过此步骤。${NC}"
    fi
}

# 安装 Foundry
install_foundry() {
    if ! command -v foundryup &> /dev/null; then
        log "${YELLOW}安装 Foundry...${NC}"
        curl -L https://foundry.paradigm.xyz | bash || error_exit "安装 Foundry 失败"
        source ~/.bashrc
        foundryup || error_exit "初始化 Foundry 失败"
        log "${GREEN}Foundry 已成功安装！${NC}"
    else
        log "${GREEN}Foundry 已安装，跳过此步骤。${NC}"
    fi
}

# 安装 Hyperlane
install_hyperlane() {
    if ! command -v hyperlane &> /dev/null; then
        log "${YELLOW}安装 Hyperlane CLI...${NC}"
        npm install -g @hyperlane-xyz/cli || error_exit "安装 Hyperlane CLI 失败"
        log "${GREEN}Hyperlane CLI 已成功安装！${NC}"
    else
        log "${GREEN}Hyperlane CLI 已安装，跳过此步骤。${NC}"
    fi

    if ! docker images | grep -q 'gcr.io/abacus-labs-dev/hyperlane-agent'; then
        log "${YELLOW}拉取 Hyperlane 镜像...${NC}"
        docker pull --platform linux/amd64 gcr.io/abacus-labs-dev/hyperlane-agent:agents-v1.0.0 || error_exit "拉取 Hyperlane 镜像失败"
        log "${GREEN}Hyperlane 镜像已成功拉取！${NC}"
    else
        log "${GREEN}Hyperlane 镜像已存在，跳过此步骤。${NC}"
    fi
}

# 配置并启动 Validator
configure_and_start_validator() {
    log "${YELLOW}配置并启动 Validator...${NC}"
    
    read -p "请输入 Validator Name: " VALIDATOR_NAME
    
    while true; do
        read -s -p "请输入 Private Key (格式：0x+64位十六进制字符): " PRIVATE_KEY
        echo ""
        if [[ ! $PRIVATE_KEY =~ ^0x[0-9a-fA-F]{64}$ ]]; then
            log "${RED}无效的 Private Key 格式！请确保输入以 '0x' 开头，并且后接 64 位十六进制字符。${NC}"
        else
            break
        fi
    done
    
    read -p "请输入 RPC URL: " RPC_URL

    CONTAINER_NAME="hyperlane"

    if docker ps -a --format '{{.Names}}' | grep -q "^hyperlane$"; then
        log "${YELLOW}发现已有容器名称为 'hyperlane' 的实例。${NC}"
        read -p "是否删除旧的容器并继续？(y/n): " choice
        if [[ "$choice" == "y" ]]; then
            docker rm -f hyperlane || error_exit "无法删除旧容器。"
            log "${GREEN}旧容器已删除，继续启动新的容器。${NC}"
        else
            read -p "请输入新容器名称: " NEW_CONTAINER_NAME
            if [[ -z "$NEW_CONTAINER_NAME" ]]; then
                error_exit "容器名称不能为空！"
            fi
            CONTAINER_NAME=$NEW_CONTAINER_NAME
        fi
    fi

    docker run -d \
        -it \
        --name "$CONTAINER_NAME" \
        --mount type=bind,source="$DB_DIR",target=/hyperlane_db_base \
        gcr.io/abacus-labs-dev/hyperlane-agent:agents-v1.0.0 \
        ./validator \
        --db /hyperlane_db_base \
        --originChainName base \
        --reorgPeriod 1 \
        --validator.id "$VALIDATOR_NAME" \
        --checkpointSyncer.type localStorage \
        --checkpointSyncer.folder base \
        --checkpointSyncer.path /hyperlane_db_base/base_checkpoints \
        --validator.key "$PRIVATE_KEY" \
        --chains.base.signer.key "$PRIVATE_KEY" \
        --chains.base.customRpcUrls "$RPC_URL" || error_exit "启动 Validator 失败"

    log "${GREEN}Validator 已配置并启动！容器名称：$CONTAINER_NAME${NC}"
}

# 查看运行日志
view_logs() {
    log "${YELLOW}检查运行日志...${NC}"
    if docker ps -a --format '{{.Names}}' | grep -q "^hyperlane$"; then
        docker logs -f hyperlane || error_exit "查看日志失败"
    else
        error_exit "容器 'hyperlane' 不存在，请确认是否启动！"
    fi
}

# 主菜单
main_menu() {
    while true; do
        echo -e "${YELLOW}"
        echo "================= Hyperlane 安装脚本 ================="
        echo "1) 检查系统环境"
        echo "2) 安装所有依赖 (Docker, Node.js, Foundry)"
        echo "3) 安装 Hyperlane"
        echo "4) 配置并启动 Validator"
        echo "5) 查看运行日志"
        echo "6) 一键完成所有步骤"
        echo "0) 退出"
        echo "====================================================="
        echo -e "${NC}"
        read -p "请输入选项: " choice
        case $choice in
            1) check_requirements ;;
            2) install_docker && install_nvm_and_node && install_foundry ;;
            3) install_hyperlane ;;
            4) configure_and_start_validator ;;
            5) view_logs ;;
            6) 
                check_requirements
                install_docker
                install_nvm_and_node
                install_foundry
                install_hyperlane
                configure_and_start_validator
                view_logs
                ;;
            0) exit 0 ;;
            *) log "${RED}无效选项，请重试！${NC}" ;;
        esac
    done
}

main_menu
