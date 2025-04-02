#!/bin/bash

#===============================================================================
#
#          FILE: install-smart-process-monitor.sh
#
#         USAGE: sudo ./install-smart-process-monitor.sh [opciones]
#
#   DESCRIPTION: Instalador para el Monitor Inteligente de Procesos v2.0
#
#       OPTIONS: --no-service    : No instalar como servicio
#                --no-gui        : No instalar dependencias de GUI
#                --help          : Mostrar ayuda
#
#        AUTHOR: Claude (https://anthropic.com/claude)
#       CREATED: $(date +%F)
#
#===============================================================================

set -o nounset

# Configuración
SCRIPT_NAME="smart-process-monitor.sh"
SCRIPT_DEST="/usr/local/bin/$SCRIPT_NAME"
SERVICE_NAME="smart-process-monitor.service"
SERVICE_DEST="/etc/systemd/system/$SERVICE_NAME"
CONFIG_DIR="/etc/smart-process-monitor"
CONFIG_FILE="$CONFIG_DIR/config.conf"
INSTALL_SERVICE=true
INSTALL_GUI=true
INSTALL_ALL_DEPS=true

# Colores para salida
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
BOLD="\033[1m"
RESET="\033[0m"

# Verificar permisos de superusuario
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}${BOLD}Error: Este script debe ejecutarse como superusuario (root)${RESET}"
    echo "Por favor ejecutar: sudo $0"
    exit 1
fi

# Mostrar banner
show_banner() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                       ║"
    echo "║     ${GREEN}Instalador del Monitor Inteligente de Procesos v2.0${BLUE}              ║"
    echo "║     Sistema Avanzado de Gestión de Procesos para Ubuntu               ║"
    echo "║                                                                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# Mostrar ayuda
show_help() {
    show_banner
    echo -e "${BOLD}USO:${RESET} sudo $0 [OPCIONES]"
    echo
    echo -e "${BOLD}DESCRIPCIÓN:${RESET}"
    echo "  Instala el Monitor Inteligente de Procesos v2.0 en el sistema"
    echo
    echo -e "${BOLD}OPCIONES:${RESET}"
    echo "  --no-service     No instalar como servicio systemd"
    echo "  --no-gui         No instalar dependencias para GUI"
    echo "  --minimal        Instalar solo dependencias esenciales"
    echo "  --help           Mostrar esta ayuda"
    echo
    echo -e "${BOLD}AUTOR:${RESET}"
    echo "  Claude (https://anthropic.com/claude)"
    echo
    exit 0
}

# Función para instalar dependencias
install_dependencies() {
    echo -e "${BLUE}${BOLD}Instalando dependencias...${RESET}"
    
    # Dependencias esenciales
    apt-get update
    apt-get install -y bc procps psmisc
    
    # Dependencias opcionales
    if $INSTALL_ALL_DEPS; then
        echo -e "${BLUE}Instalando dependencias adicionales...${RESET}"
        apt-get install -y sqlite3 mailutils
    fi
    
    # Dependencias para GUI
    if $INSTALL_GUI; then
        echo -e "${BLUE}Instalando dependencias para GUI...${RESET}"
        apt-get install -y dialog libnotify-bin
    fi
    
    echo -e "${GREEN}${BOLD}✓ Dependencias instaladas correctamente${RESET}"
}

# Crear el archivo del servicio systemd
create_service_file() {
    echo -e "${BLUE}${BOLD}Creando archivo de servicio systemd...${RESET}"
    
    cat > "$SERVICE_DEST" << EOL
[Unit]
Description=Monitor Inteligente de Procesos v2.0
Documentation=https://anthropic.com/claude
After=network.target

[Service]
Type=simple
ExecStart=$SCRIPT_DEST --service --config=$CONFIG_FILE
Restart=on-failure
RestartSec=30
KillMode=process
Nice=-5

[Install]
WantedBy=multi-user.target
EOL
    
    chmod 644 "$SERVICE_DEST"
    echo -e "${GREEN}${BOLD}✓ Archivo de servicio creado correctamente${RESET}"
}

# Crear configuración por defecto
create_default_config() {
    echo -e "${BLUE}${BOLD}Creando configuración por defecto...${RESET}"
    
    # Crear directorio si no existe
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        chmod 755 "$CONFIG_DIR"
    fi
    
    # Crear archivo de configuración
    cat > "$CONFIG_FILE" << EOL
# Configuración para el Monitor Inteligente de Procesos v2.0
# Creado por el instalador: $(date '+%Y-%m-%d %H:%M:%S')

# Configuración de monitoreo
CPU_THRESHOLD=80
MEM_THRESHOLD=85
IO_THRESHOLD=70
MONITORING_INTERVAL=1
SUSTAINED_SECONDS=5
MAX_HISTORY_SIZE=1000

# Configuración de acciones
ACTION_MODE="smart"
ZOMBIE_ACTION="kill-parent"
WHITELIST_SYSTEM_PROCESSES=true
ADAPTIVE_LEARNING=true

# Configuración de interfaz
LOG_FILE="/var/log/smart-process-monitor.log"
LOG_LEVEL=2
NOTIFY_DESKTOP=true
NOTIFY_USER=true
EMAIL_ALERTS=false
EMAIL_TO=""

# Listas de procesos
PROCESS_WHITELIST="firefox|chrome|thunderbird|code|gimp|libreoffice|vim|nano"
EOL
    
    chmod 644 "$CONFIG_FILE"
    echo -e "${GREEN}${BOLD}✓ Configuración creada correctamente${RESET}"
}

# Copiar los archivos del script al destino
install_script_files() {
    echo -e "${BLUE}${BOLD}Instalando archivos del script...${RESET}"
    
    # Combinar los archivos del script
    cat "Monitor Inteligente de Procesos v2.0.sh" "Monitor Inteligente de Procesos v2.0 (Continuación).sh" "Monitor Inteligente de Procesos v2.0 (Parte Final).sh" > "$SCRIPT_DEST"
    
    # Asegurar permisos de ejecución
    chmod 755 "$SCRIPT_DEST"
    
    echo -e "${GREEN}${BOLD}✓ Script instalado correctamente en $SCRIPT_DEST${RESET}"
}

# Crear directorios de datos
create_data_directories() {
    echo -e "${BLUE}${BOLD}Creando directorios de datos...${RESET}"
    
    # Directorio para la base de datos
    mkdir -p "/var/lib/smart-process-monitor"
    chmod 750 "/var/lib/smart-process-monitor"
    
    # Directorio para logs
    mkdir -p "/var/log"
    touch "/var/log/smart-process-monitor.log"
    chmod 640 "/var/log/smart-process-monitor.log"
    
    echo -e "${GREEN}${BOLD}✓ Directorios de datos creados correctamente${RESET}"
}

# Activar e iniciar el servicio
enable_service() {
    if $INSTALL_SERVICE; then
        echo -e "${BLUE}${BOLD}Activando e iniciando el servicio...${RESET}"
        systemctl daemon-reload
        systemctl enable "$SERVICE_NAME"
        systemctl start "$SERVICE_NAME"
        echo -e "${GREEN}${BOLD}✓ Servicio activado e iniciado correctamente${RESET}"
    fi
}

# Crear enlaces simbólicos para comandos de conveniencia
create_symlinks() {
    echo -e "${BLUE}${BOLD}Creando enlaces simbólicos...${RESET}"
    
    # Crear enlaces para comandos de conveniencia
    ln -sf "$SCRIPT_DEST" "/usr/local/bin/spm"
    ln -sf "$SCRIPT_DEST" "/usr/local/bin/procmon"
    
    echo -e "${GREEN}${BOLD}✓ Enlaces simbólicos creados: spm, procmon${RESET}"
}

# Procesar argumentos de línea de comandos
for arg in "$@"; do
    case $arg in
        --no-service)
            INSTALL_SERVICE=false
            ;;
        --no-gui)
            INSTALL_GUI=false
            ;;
        --minimal)
            INSTALL_ALL_DEPS=false
            ;;
        --help)
            show_help
            ;;
        *)
            echo -e "${RED}Opción desconocida: $arg${RESET}"
            echo "Use --help para ver las opciones disponibles"
            exit 1
            ;;
    esac
done

# Proceso principal de instalación
show_banner
echo -e "${YELLOW}Iniciando instalación del Monitor Inteligente de Procesos v2.0...${RESET}"
echo

# Instalar dependencias
install_dependencies

# Instalar archivos
install_script_files
create_data_directories
create_default_config

# Configurar servicio si corresponde
if $INSTALL_SERVICE; then
    create_service_file
    enable_service
fi

# Crear enlaces simbólicos
create_symlinks

# Mostrar resumen final
echo
echo -e "${GREEN}${BOLD}✅ Instalación completada exitosamente${RESET}"
echo
echo -e "${YELLOW}${BOLD}Resumen de la instalación:${RESET}"
echo -e "  • Script instalado en: ${BOLD}$SCRIPT_DEST${RESET}"
echo -e "  • Configuración: ${BOLD}$CONFIG_FILE${RESET}"
echo -e "  • Log: ${BOLD}/var/log/smart-process-monitor.log${RESET}"
echo -e "  • Base de datos: ${BOLD}/var/lib/smart-process-monitor/patterns.db${RESET}"
echo -e "  • Comandos disponibles: ${BOLD}smart-process-monitor.sh, spm, procmon${RESET}"
echo

if $INSTALL_SERVICE; then
    echo -e "${YELLOW}${BOLD}Comandos útiles para gestionar el servicio:${RESET}"
    echo -e "  • Ver estado: ${BOLD}systemctl status $SERVICE_NAME${RESET}"
    echo -e "  • Iniciar: ${BOLD}systemctl start $SERVICE_NAME${RESET}"
    echo -e "  • Detener: ${BOLD}systemctl stop $SERVICE_NAME${RESET}"
    echo -e "  • Ver logs: ${BOLD}journalctl -u $SERVICE_NAME${RESET}"
    echo
fi

echo -e "${YELLOW}${BOLD}Para ejecutar con interfaz gráfica:${RESET}"
echo -e "  ${BOLD}sudo spm --gui${RESET}"
echo
echo -e "${BLUE}Gracias por instalar el Monitor Inteligente de Procesos v2.0${RESET}"
echo -e "${BLUE}Autor: Claude (https://anthropic.com/claude)${RESET}"