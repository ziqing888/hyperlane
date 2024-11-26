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


if [ ! -w "$(dirname "$LOG_FILE")" ]; then
    error_exit "日志路径不可写，请检查权限或调整路径：$(dirname "$LOG_FILE")"
fi


DB_DIR="/opt/hyperlane_db_base"


if [ ! -d "$DB_DIR" ]; then
    mkdir -p "$DB_DIR" && chmod -R 777 "$DB_DIR" || error_exit "创建数据库目录失败: $DB_DIR"
    log "${GREEN}数据库目录已创建: $DB_DIR${NC}"
else
    log "${GREEN}数据库目录已存在: $DB_DIR${NC}"
fi


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
    else
        CONTAINER_NAME="hyperlane"
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


view_logs() {
    log "${YELLOW}检查运行日志...${NC}"
    docker logs -f hyperlane || error_exit "查看日志失败"
}


main_menu() {
    while true; do
        echo -e "${YELLOW}"
        echo "================= Hyperlane 安装脚本 ================="
        echo "1) 检查系统环境"
        echo "2) 安装 Hyperlane"
        echo "3) 配置并启动 Validator"
        echo "4) 查看运行日志"
        echo "5) 一键完成所有步骤"
        echo "0) 退出"
        echo "====================================================="
        echo -e "${NC}"
        read -p "请输入选项: " choice
        case $choice in
            1) check_requirements ;;
            2) install_hyperlane ;;
            3) configure_and_start_validator ;;
            4) view_logs ;;
            5) 
                check_requirements
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
