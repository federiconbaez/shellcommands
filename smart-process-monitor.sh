#!/bin/bash

#===============================================================================
#
#          FILE: smart-process-monitor.sh
#
#         USAGE: sudo ./smart-process-monitor.sh [opciones]
#
#   DESCRIPTION: Monitor inteligente de procesos para Ubuntu que gestiona
#                automáticamente procesos zombie y de alto consumo de CPU/MEM
#                con aprendizaje adaptativo y notificaciones
#
#       OPTIONS: --config=ARCHIVO  : Ruta al archivo de configuración
#                --gui             : Inicia interfaz TUI (requiere dialog)
#                --service         : Ejecuta como servicio en segundo plano
#                --adaptive        : Activa el modo de aprendizaje adaptativo
#                --help            : Muestra ayuda
#
#        AUTHOR: Claude (https://anthropic.com/claude)
#       CREATED: $(date +%F)
#      REVISION: 2.0
#
#===============================================================================

set -o nounset                              # Trata variables no definidas como error
#set -o errexit                              # Salir inmediatamente si un comando falla

#-------------------------------------------------------------------------------
# CONFIGURACIÓN PREDETERMINADA (PUEDE SOBREESCRIBIRSE EN ARCHIVO DE CONFIGURACIÓN)
#-------------------------------------------------------------------------------
# Configuración de monitoreo
CPU_THRESHOLD=80                # Porcentaje de CPU considerado excesivo
MEM_THRESHOLD=85               # Porcentaje de memoria considerado excesivo
IO_THRESHOLD=70                # Porcentaje de I/O considerado excesivo
MONITORING_INTERVAL=1          # Intervalo de verificación en segundos
SUSTAINED_SECONDS=5            # Tiempo en segundos para confirmar alto uso sostenido
MAX_HISTORY_SIZE=1000          # Número máximo de eventos a mantener en historial

# Configuración de acciones
ACTION_MODE="smart"            # Modos: smart, gentle, aggressive, observe
ZOMBIE_ACTION="kill-parent"    # Modos: kill-parent, ignore, report-only
WHITELIST_SYSTEM_PROCESSES=true    # Proteger procesos críticos del sistema
ADAPTIVE_LEARNING=false        # Aprendizaje adaptativo basado en patrones

# Configuración de interfaz
LOG_FILE="/var/log/smart-process-monitor.log"
LOG_LEVEL=2                    # 0=solo crítico, 1=errores, 2=info, 3=debug, 4=todo
NOTIFY_DESKTOP=true            # Enviar notificaciones de escritorio si está disponible
NOTIFY_USER=true               # Enviar mensaje al usuario cuando se toman acciones
EMAIL_ALERTS=false             # Enviar alertas por correo electrónico
EMAIL_TO=""                    # Dirección de correo para alertas

# Configuración de aprendizaje adaptativo
LEARNING_DB="/var/lib/smart-process-monitor/patterns.db"
THRESHOLD_ADJUSTMENT_RATE=2    # Tasa de ajuste para umbrales basada en aprendizaje
PATTERN_CONFIDENCE_THRESHOLD=75  # Confianza mínima para aplicar un patrón aprendido

# Listas de procesos
PROCESS_WHITELIST=""           # Procesos a ignorar siempre (protegidos)
CRITICAL_SYSTEM_PROCESSES="systemd|init|dbus-daemon|networkd|cron|sshd|login|bash|sh|xinit|Xorg|wayland|gdm|lightdm|kde|gnome"
USER_PRIORITY_PROCESSES=""     # Procesos prioritarios para el usuario

#-------------------------------------------------------------------------------
# VARIABLES GLOBALES
#-------------------------------------------------------------------------------
VERSION="2.0"
CONFIG_FILE=""
GUI_MODE=false
SERVICE_MODE=false
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
DB_DIR="/var/lib/smart-process-monitor"
TEMP_DIR=""
PID_FILE="/var/run/smart-process-monitor.pid"
RUNNING=true
COLORS_ENABLED=true
CURRENT_USER=$(logname 2>/dev/null || echo "$USER")
START_TIME=$(date +%s)
ACTIONS_TAKEN=0
PROCESSES_MONITORED=0
ZOMBIES_HANDLED=0
HIGH_CPU_HANDLED=0
HIGH_MEM_HANDLED=0
WARNINGS_ISSUED=0
TERMINAL_WIDTH=80

# Códigos de color ANSI para terminal
if $COLORS_ENABLED; then
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[0;33m"
    BLUE="\033[0;34m"
    MAGENTA="\033[0;35m"
    CYAN="\033[0;36m"
    BOLD="\033[1m"
    RESET="\033[0m"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    BOLD=""
    RESET=""
fi

#-------------------------------------------------------------------------------
# FUNCIONES DE UTILIDAD Y SALIDA
#-------------------------------------------------------------------------------
display_banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                       ║"
    echo "║     ${CYAN}Smart Process Monitor v${VERSION}${BLUE}                                        ║"
    echo "║     ${GREEN}Sistema Avanzado de Gestión de Procesos para Ubuntu${BLUE}                ║"
    echo "║                                                                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

show_help() {
    display_banner
    echo -e "${BOLD}USO:${RESET} sudo $0 [OPCIONES]"
    echo
    echo -e "${BOLD}DESCRIPCIÓN:${RESET}"
    echo "  Monitorea y gestiona automáticamente procesos zombie y procesos que"
    echo "  consumen recursos excesivos del sistema mediante un enfoque adaptativo."
    echo
    echo -e "${BOLD}OPCIONES:${RESET}"
    echo "  --config=ARCHIVO   Especifica un archivo de configuración alternativo"
    echo "  --gui              Inicia la interfaz de usuario de texto interactiva"
    echo "  --service          Ejecuta como servicio en segundo plano"
    echo "  --adaptive         Activa el aprendizaje adaptativo"
    echo "  --gentle           Usa el modo gentil (intenta SIGTERM antes de SIGKILL)"
    echo "  --aggressive       Usa el modo agresivo (va directo a SIGKILL)"
    echo "  --observe          Solo observa y registra, sin tomar acciones"
    echo "  --no-color         Deshabilita colores en la salida"
    echo "  --help             Muestra esta ayuda"
    echo
    echo -e "${BOLD}EJEMPLOS:${RESET}"
    echo "  sudo $0 --gui              # Inicia con interfaz interactiva"
    echo "  sudo $0 --config=mi.conf   # Usa configuración personalizada"
    echo "  sudo $0 --service          # Ejecuta como servicio"
    echo
    echo -e "${BOLD}AUTOR:${RESET}"
    echo "  Claude (https://anthropic.com/claude)"
    echo
}

# Función para crear un registro con nivel de detalle ajustable
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local level_name=""
    local color_code=""
    
    case "$level" in
        0) level_name="CRITICAL"; color_code="$RED$BOLD" ;;
        1) level_name="ERROR"; color_code="$RED" ;;
        2) level_name="INFO"; color_code="$GREEN" ;;
        3) level_name="DEBUG"; color_code="$BLUE" ;;
        4) level_name="TRACE"; color_code="$CYAN" ;;
        *) level_name="UNKNOWN"; color_code="$YELLOW" ;;
    esac
    
    # Solo registrar mensajes según el nivel de detalle configurado
    if [ "$level" -le "$LOG_LEVEL" ]; then
        if [ -t 1 ] && ! $SERVICE_MODE; then
            # Salida a terminal con colores si estamos en modo interactivo
            echo -e "${color_code}[$timestamp] [${level_name}] $message${RESET}"
        else
            # Salida sin formato para servicios o redirecciones
            echo "[$timestamp] [${level_name}] $message"
        fi
        
        # Registrar en archivo de log independientemente del modo
        echo "[$timestamp] [${level_name}] $message" >> "$LOG_FILE"
    fi
}

# Notificaciones al usuario y correo
notify_user() {
    local message="$1"
    local urgency="${2:-normal}"
    
    # Notificación de escritorio si está habilitada y disponible
    if $NOTIFY_DESKTOP && command -v notify-send >/dev/null && [ -n "$DISPLAY" ]; then
        sudo -u "$CURRENT_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$CURRENT_USER")/bus notify-send --urgency="$urgency" "Smart Process Monitor" "$message" &>/dev/null
    fi
    
    # Envío de correo si está configurado
    if $EMAIL_ALERTS && [ -n "$EMAIL_TO" ] && command -v mail >/dev/null; then
        echo "$message" | mail -s "Smart Process Monitor: Alerta de Sistema" "$EMAIL_TO"
    fi
}

# Gestión de señales para terminación ordenada
setup_signal_handlers() {
    trap 'cleanup_and_exit' SIGINT SIGTERM
    trap 'handle_usr1_signal' SIGUSR1
    trap 'handle_usr2_signal' SIGUSR2
}

handle_usr1_signal() {
    log 2 "Señal USR1 recibida: Recargando configuración"
    load_configuration
}

handle_usr2_signal() {
    log 2 "Señal USR2 recibida: Generando informe de estado"
    generate_status_report
}

cleanup_and_exit() {
    log 2 "Deteniendo Smart Process Monitor..."
    RUNNING=false
    
    # Generar informe de resumen
    generate_summary_report
    
    # Eliminar PID y archivos temporales
    [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
    [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
    
    log 2 "Monitor de procesos finalizado correctamente."
    
    # Salir con código 0
    exit 0
}

#-------------------------------------------------------------------------------
# FUNCIONES PRINCIPALES DE MONITOREO Y ACCIÓN
#-------------------------------------------------------------------------------

# Cargar configuración desde archivo
load_configuration() {
    if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        log 2 "Cargando configuración desde $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        log 2 "Configuración cargada correctamente"
    else
        if [ -n "$CONFIG_FILE" ]; then
            log 1 "El archivo de configuración $CONFIG_FILE no existe. Usando valores predeterminados."
        else
            log 3 "Usando configuración predeterminada"
        fi
    fi
    
    # Ajustar el modo de acción si se especificó en línea de comandos
    case "$ACTION_MODE" in
        gentle|aggressive|observe|smart) ;;
        *) ACTION_MODE="smart" ;;
    esac
}

# Preparar el entorno
initialize_environment() {
    # Verificar permisos de superusuario
    if [ "$(id -u)" -ne 0 ]; then
        echo "Este script debe ejecutarse como superusuario (root)"
        echo "Por favor ejecutar: sudo $0"
        exit 1
    fi
    
    # Detectar ancho del terminal
    if command -v tput >/dev/null; then
        TERMINAL_WIDTH=$(tput cols)
    fi
    
    # Crear directorio de la base de datos si no existe
    if ! [ -d "$DB_DIR" ]; then
        mkdir -p "$DB_DIR"
        chmod 750 "$DB_DIR"
    fi
    
    # Crear directorio para el archivo de log si no existe
    LOG_DIR=$(dirname "$LOG_FILE")
    if ! [ -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        chmod 750 "$LOG_DIR"
    fi
    
    # Crear archivo de log si no existe
    if ! [ -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
        chmod 640 "$LOG_FILE"
    fi
    
    # Crear directorio temporal para datos
    TEMP_DIR=$(mktemp -d)
    chmod 700 "$TEMP_DIR"
    
    # Registrar PID para el servicio
    echo $$ > "$PID_FILE"
    
    # Verificar dependencias
    check_dependencies
    
    # Inicializar base de datos de patrones si está habilitado el aprendizaje adaptativo
    if $ADAPTIVE_LEARNING && ! [ -f "$LEARNING_DB" ]; then
        initialize_pattern_database
    fi
}

# Verificar que todas las dependencias necesarias estén instaladas
check_dependencies() {
    local missing_deps=0
    local optional_missing=0
    
    # Dependencias obligatorias
    for cmd in ps top grep awk sed bc sort uniq; do
        if ! command -v "$cmd" >/dev/null; then
            log 1 "Falta dependencia obligatoria: $cmd"
            missing_deps=$((missing_deps + 1))
        fi
    done
    
    # Dependencias opcionales
    if $GUI_MODE && ! command -v dialog >/dev/null; then
        log 1 "Falta dependencia para modo GUI: dialog. Instalarlo con: sudo apt install dialog"
        optional_missing=$((optional_missing + 1))
    fi
    
    if $NOTIFY_DESKTOP && ! command -v notify-send >/dev/null; then
        log 3 "Falta notify-send para notificaciones de escritorio. Se deshabilitarán las notificaciones."
        NOTIFY_DESKTOP=false
        optional_missing=$((optional_missing + 1))
    fi
    
    if $EMAIL_ALERTS && ! command -v mail >/dev/null; then
        log 1 "Falta 'mail' para enviar alertas por correo. Instalarlo con: sudo apt install mailutils"
        EMAIL_ALERTS=false
        optional_missing=$((optional_missing + 1))
    fi
    
    # Sugerir SQLite si se usa aprendizaje adaptativo
    if $ADAPTIVE_LEARNING && ! command -v sqlite3 >/dev/null; then
        log 1 "Falta sqlite3 para aprendizaje adaptativo. Instalarlo con: sudo apt install sqlite3"
        optional_missing=$((optional_missing + 1))
    fi
    
    if [ "$missing_deps" -gt 0 ]; then
        log 0 "Faltan $missing_deps dependencias obligatorias. Se requiere instalarlas para continuar."
        exit 1
    fi
    
    if [ "$optional_missing" -gt 0 ]; then
        log 1 "Faltan $optional_missing dependencias opcionales. Algunas funciones estarán limitadas."
    fi
}

# Inicializar la base de datos para el modo adaptativo
initialize_pattern_database() {
    if command -v sqlite3 >/dev/null; then
        log 2 "Inicializando base de datos de patrones en $LEARNING_DB"
        
        sqlite3 "$LEARNING_DB" <<EOF
CREATE TABLE IF NOT EXISTS process_patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    process_name TEXT NOT NULL,
    pattern_type TEXT NOT NULL,
    value REAL,
    confidence INTEGER DEFAULT 50,
    occurrences INTEGER DEFAULT 1,
    first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS system_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    process_id INTEGER,
    process_name TEXT,
    details TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_process_name ON process_patterns(process_name);
CREATE INDEX IF NOT EXISTS idx_pattern_type ON process_patterns(pattern_type);
CREATE INDEX IF NOT EXISTS idx_event_type ON system_events(event_type);
EOF
        
        chmod 640 "$LEARNING_DB"
        log 2 "Base de datos de patrones inicializada correctamente"
    else
        log 1 "No se puede inicializar la base de datos: sqlite3 no está instalado"
        ADAPTIVE_LEARNING=false
    fi
}

# Función para manejar procesos zombie
handle_zombies() {
    log 3 "Buscando procesos zombie..."
    
    # Encontrar procesos zombie
    zombie_pids=$(ps aux | awk '$8=="Z" {print $2}')
    
    if [ -z "$zombie_pids" ]; then
        log 4 "No se encontraron procesos zombie."
        return
    fi
    
    # Contar cuántos zombies se encontraron
    zombie_count=$(echo "$zombie_pids" | wc -w)
    log 2 "Se encontraron $zombie_count procesos zombie"
    
    # Procesar cada proceso zombie
    for pid in $zombie_pids; do
        # Obtener el PID del padre
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        
        # Verificar si el ppid existe y es válido
        if [ -z "$ppid" ] || ! ps -p "$ppid" > /dev/null 2>&1; then
            log 3 "No se puede determinar o acceder al proceso padre del zombie PID $pid"
            continue
        fi
        
        # Obtener el nombre del proceso padre
        process_name=$(ps -p "$ppid" -o comm= 2>/dev/null || echo "desconocido")
        process_cmdline=$(ps -p "$ppid" -o cmd= 2>/dev/null | sed 's/\s\+/ /g' | cut -c 1-50)
        process_user=$(ps -p "$ppid" -o user= 2>/dev/null)
        
        log 2 "Zombie PID $pid detectado - Padre: $ppid ($process_name) Usuario: $process_user"
        
        # Verificar si el proceso está en la lista blanca o es del sistema
        if is_whitelisted_process "$process_name"; then
            log 2 "Proceso '$process_name' ($ppid) está en lista blanca, ignorando zombie hijo ($pid)"
            continue
        fi
        
        # Incrementar contador de zombies manejados
        ZOMBIES_HANDLED=$((ZOMBIES_HANDLED + 1))
        
        # Determinar acción basada en el modo configurado
        case "$ZOMBIE_ACTION" in
            kill-parent)
                log 2 "Intentando terminar proceso padre $ppid ($process_name) para liberar zombie $pid"
                
                if [ "$ACTION_MODE" = "aggressive" ]; then
                    # Modo agresivo: directamente SIGKILL
                    log 2 "Modo agresivo: Enviando SIGKILL a $ppid"
                    kill -9 "$ppid" 2>/dev/null
                else
                    # Modo normal/gentil: intentar SIGTERM primero
                    log 2 "Enviando SIGTERM a proceso padre $ppid"
                    kill -15 "$ppid" 2>/dev/null
                    
                    # Esperar un momento y verificar si el zombie todavía existe
                    sleep 2
                    if ps -p "$pid" > /dev/null 2>&1; then
                        log 2 "Zombie $pid persiste. Enviando SIGKILL al padre $ppid"
                        kill -9 "$ppid" 2>/dev/null
                    else
                        log 2 "Zombie $pid eliminado exitosamente con SIGTERM"
                    fi
                fi
                
                # Verificar el resultado final
                sleep 1
                if ! ps -p "$pid" > /dev/null 2>&1; then
                    log 2 "Zombie $pid eliminado exitosamente"
                    ACTIONS_TAKEN=$((ACTIONS_TAKEN + 1))
                    
                    # Notificar al usuario si corresponde
                    if $NOTIFY_USER; then
                        notify_user "Proceso zombie (PID $pid) eliminado - Padre: $process_name ($ppid)" "normal"
                    fi
                else
                    log 1 "No se pudo eliminar el zombie $pid incluso después de matar al padre"
                    WARNINGS_ISSUED=$((WARNINGS_ISSUED + 1))
                fi
                
                # Registrar evento en la base de datos si el aprendizaje adaptativo está activado
                if $ADAPTIVE_LEARNING; then
                    record_system_event "zombie_killed" "$pid" "$process_name" "Parent: $ppid, User: $process_user"
                fi
                ;;
                
            report-only)
                log 2 "Modo reporte: Zombie detectado - PID $pid, Padre $ppid ($process_name)"
                if $NOTIFY_USER; then
                    notify_user "Proceso zombie detectado - PID $pid, Padre: $process_name ($ppid)" "low"
                fi
                ;;
                
            ignore)
                log 3 "Modo ignorar: Zombie $pid ignorado"
                ;;
        esac
    done
}

#!/bin/bash

# Función para monitorear y manejar procesos con alto consumo de recursos
handle_high_resource_processes() {
    log 3 "Monitoreando procesos con alto consumo de recursos..."
    
    # Crear archivos temporales para los snapshots
    for i in $(seq 1 "$SUSTAINED_SECONDS"); do
        local snapshot_file="$TEMP_DIR/snapshot_$i.txt"
        
        # Capturar salida de top para uso de CPU y memoria
        top -b -n 1 -o +%CPU | grep -v "^$" | tail -n +8 | \
            awk '{printf "%s %s %s %s %s\n", $1, $2, $9, $10, $12}' > "$snapshot_file"
        
        # Si no es la última iteración, esperar para la próxima medición
        if [ "$i" -lt "$SUSTAINED_SECONDS" ]; then
            sleep "$MONITORING_INTERVAL"
        fi
    done
    
    # Analizar los resultados para encontrar procesos con uso sostenido alto de recursos
    log 3 "Analizando datos de uso de recursos sostenido..."
    
    # Crear una lista de todos los PIDs únicos en todos los snapshots
    all_pids=$(cat "$TEMP_DIR"/snapshot_*.txt | awk '{print $1}' | sort -u)
    
    for pid in $all_pids; do
        # Saltarse el PID de este script
        if [ "$pid" -eq "$$" ]; then
            continue
        fi
        
        # Verificar si el proceso todavía existe
        if ! ps -p "$pid" > /dev/null 2>&1; then
            continue
        fi
        
        # Obtener información detallada del proceso
        process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "desconocido")
        process_user=$(ps -p "$pid" -o user= 2>/dev/null || echo "desconocido")
        process_start=$(ps -p "$pid" -o lstart= 2>/dev/null || echo "desconocido")
        process_cmdline=$(ps -p "$pid" -o cmd= 2>/dev/null | sed 's/\s\+/ /g' | cut -c 1-50)
        
        # Incrementar contador de procesos monitoreados
        PROCESSES_MONITORED=$((PROCESSES_MONITORED + 1))
        
        # Verificar si el proceso está en la lista blanca
        if is_whitelisted_process "$process_name"; then
            log 4 "Proceso '$process_name' ($pid) está en lista blanca, ignorando"
            continue
        fi
        
        # Aplicar umbrales ajustados si el aprendizaje adaptativo está habilitado
        local cpu_threshold=$CPU_THRESHOLD
        local mem_threshold=$MEM_THRESHOLD
        
        if $ADAPTIVE_LEARNING; then
            adjusted_thresholds=$(get_adjusted_thresholds "$process_name")
            if [ -n "$adjusted_thresholds" ]; then
                # Formato esperado: "cpu_threshold mem_threshold"
                cpu_threshold=$(echo "$adjusted_thresholds" | awk '{print $1}')
                mem_threshold=$(echo "$adjusted_thresholds" | awk '{print $2}')
                log 3 "Umbrales ajustados para '$process_name': CPU=$cpu_threshold%, MEM=$mem_threshold%"
            fi
        fi
        
        # Contar en cuántos snapshots el proceso excede los umbrales
        high_cpu_count=0
        high_mem_count=0
        total_cpu=0
        total_mem=0
        
        for i in $(seq 1 "$SUSTAINED_SECONDS"); do
            snapshot_file="$TEMP_DIR/snapshot_$i.txt"
            if grep -q "^$pid " "$snapshot_file"; then
                # Formato: PID USER CPU MEM COMMAND
                snapshot_data=$(grep "^$pid " "$snapshot_file")
                cpu_usage=$(echo "$snapshot_data" | awk '{print $3}')
                mem_usage=$(echo "$snapshot_data" | awk '{print $4}')
                
                # Acumular para promedio
                total_cpu=$(echo "$total_cpu + $cpu_usage" | bc)
                total_mem=$(echo "$total_mem + $mem_usage" | bc)
                
                # Verificar CPU alta
                if (( $(echo "$cpu_usage >= $cpu_threshold" | bc -l) )); then
                    high_cpu_count=$((high_cpu_count + 1))
                fi
                
                # Verificar memoria alta
                if (( $(echo "$mem_usage >= $mem_threshold" | bc -l) )); then
                    high_mem_count=$((high_mem_count + 1))
                fi
            fi
        done
        
        # Calcular promedios
        avg_cpu=$(echo "scale=1; $total_cpu / $SUSTAINED_SECONDS" | bc)
        avg_mem=$(echo "scale=1; $total_mem / $SUSTAINED_SECONDS" | bc)
        
        # Determinar si hay uso sostenido alto
        high_cpu_sustained=$([ "$high_cpu_count" -eq "$SUSTAINED_SECONDS" ] && echo true || echo false)
        high_mem_sustained=$([ "$high_mem_count" -eq "$SUSTAINED_SECONDS" ] && echo true || echo false)
        
        # Procesar procesos con alto uso sostenido
        if $high_cpu_sustained || $high_mem_sustained; then
            # Construir mensaje detallado
            local resource_type=""
            local resource_value=""
            local resource_threshold=""
            
            if $high_cpu_sustained; then
                resource_type="CPU"
                resource_value="$avg_cpu%"
                resource_threshold="$cpu_threshold%"
                HIGH_CPU_HANDLED=$((HIGH_CPU_HANDLED + 1))
            elif $high_mem_sustained; then
                resource_type="memoria"
                resource_value="$avg_mem%"
                resource_threshold="$mem_threshold%"
                HIGH_MEM_HANDLED=$((HIGH_MEM_HANDLED + 1))
            fi
            
            log 2 "Proceso $pid ($process_name) de usuario $process_user tiene uso alto sostenido de $resource_type: $resource_value (umbral: $resource_threshold)"
            
            # Si está en modo observación, solo registrar
            if [ "$ACTION_MODE" = "observe" ]; then
                log 2 "Modo observación: No se tomará acción sobre $process_name ($pid)"
                if $NOTIFY_USER; then
                    notify_user "Alto uso de $resource_type detectado: $process_name ($pid) - $resource_value" "low"
                fi
                continue
            fi
            
            # Determinar si es un proceso crítico del sistema
            if $WHITELIST_SYSTEM_PROCESSES && is_critical_system_process "$process_name"; then
                log 2 "Proceso crítico del sistema '$process_name' ($pid) con alto uso de $resource_type. No se tomará acción."
                WARNINGS_ISSUED=$((WARNINGS_ISSUED + 1))
                
                if $NOTIFY_USER; then
                    notify_user "Advertencia: Proceso crítico $process_name con alto uso de $resource_type: $resource_value" "critical"
                fi
                
                # Registrar el evento para aprendizaje adaptativo
                if $ADAPTIVE_LEARNING; then
                    record_system_event "high_resource_critical" "$pid" "$process_name" "$resource_type=$resource_value"
                fi
                
                continue
            fi
            
            # Registrar para aprendizaje adaptativo antes de tomar acción
            if $ADAPTIVE_LEARNING; then
                record_system_event "high_resource_detected" "$pid" "$process_name" "$resource_type=$resource_value"
                update_process_pattern "$process_name" "$resource_type" "$resource_value"
            fi
            
            # Tomar acción según el modo configurado
            if [ "$ACTION_MODE" = "aggressive" ]; then
                # Modo agresivo: directamente SIGKILL
                log 2 "Modo agresivo: Enviando SIGKILL a proceso $pid ($process_name) por alto uso de $resource_type"
                kill -9 "$pid" 2>/dev/null
                sleep 1
            else
                # Modo normal/gentil: intentar SIGTERM primero
                log 2 "Enviando SIGTERM a proceso $pid ($process_name) por alto uso de $resource_type"
                kill -15 "$pid" 2>/dev/null
                
                # Esperar un momento y verificar si el proceso todavía existe
                sleep 2
                if ps -p "$pid" > /dev/null 2>&1; then
                    if [ "$ACTION_MODE" = "gentle" ]; then
                        # En modo gentil, enviar una segunda señal TERM y luego simplemente advertir
                        log 2 "Modo gentil: Proceso $pid no respondió a SIGTERM. Enviando otra señal TERM..."
                        kill -15 "$pid" 2>/dev/null
                        sleep 3
                        
                        if ps -p "$pid" > /dev/null 2>&1; then
                            log 1 "Advertencia: El proceso $process_name ($pid) no responde a señales TERM"
                            WARNINGS_ISSUED=$((WARNINGS_ISSUED + 1))
                            
                            if $NOTIFY_USER; then
                                notify_user "Proceso $process_name no responde a señales de terminación" "critical"
                            fi
                        fi
                    else
                        # En modo normal o smart, usar SIGKILL si SIGTERM no funcionó
                        log 2 "Proceso $pid no respondió a SIGTERM. Aplicando SIGKILL..."
                        kill -9 "$pid" 2>/dev/null
                        sleep 1
                    fi
                fi
            fi
            
            # Verificar el resultado final
            if ! ps -p "$pid" > /dev/null 2>&1; then
                log 2 "Proceso $pid ($process_name) terminado exitosamente por alto uso de $resource_type"
                ACTIONS_TAKEN=$((ACTIONS_TAKEN + 1))
                
                # Notificar al usuario
                if $NOTIFY_USER; then
                    notify_user "Proceso terminado: $process_name - Alto uso de $resource_type: $resource_value" "normal"
                fi
                
                # Registrar el evento para aprendizaje adaptativo
                if $ADAPTIVE_LEARNING; then
                    record_system_event "process_terminated" "$pid" "$process_name" "Reason: high $resource_type ($resource_value)"
                fi
            else
                log 1 "No se pudo terminar el proceso $pid ($process_name) incluso después de SIGKILL"
                WARNINGS_ISSUED=$((WARNINGS_ISSUED + 1))
                
                if $NOTIFY_USER; then
                    notify_user "¡Advertencia! No se pudo terminar proceso $process_name ($pid)" "critical"
                fi
            fi
        fi
    done
    
    # Limpiar archivos temporales de snapshots
    rm -f "$TEMP_DIR"/snapshot_*.txt
}

# Determinar si un proceso está en la lista blanca
is_whitelisted_process() {
    local process_name="$1"
    
    # Verificar lista blanca explícita
    if [ -n "$PROCESS_WHITELIST" ]; then
        if [[ "$process_name" =~ ^($PROCESS_WHITELIST)$ ]]; then
            return 0  # Está en la lista blanca
        fi
    fi
    
    # Verificar si es un proceso del sistema crítico (cuando está habilitada la protección)
    if $WHITELIST_SYSTEM_PROCESSES && is_critical_system_process "$process_name"; then
        return 0  # Es un proceso del sistema crítico
    fi
    
    # Si llegamos aquí, no está en la lista blanca
    return 1
}

# Determinar si un proceso es crítico para el sistema
is_critical_system_process() {
    local process_name="$1"
    
    if [ -n "$CRITICAL_SYSTEM_PROCESSES" ] && [[ "$process_name" =~ ^($CRITICAL_SYSTEM_PROCESSES)$ ]]; then
        return 0  # Es un proceso crítico del sistema
    fi
    
    # Verificar si el proceso pertenece a root y es esencial
    if [ "$(ps -o user= -p "$(pgrep -x "$process_name" | head -n1)" 2>/dev/null)" = "root" ]; then
        # Verificar si está en directorios del sistema
        if [ -x "/sbin/$process_name" ] || [ -x "/usr/sbin/$process_name" ] || 
           [ -x "/bin/$process_name" ] || [ -x "/usr/bin/$process_name" ]; then
            return 0  # Es un proceso del sistema
        fi
    fi
    
    return 1  # No es un proceso crítico
}

#-------------------------------------------------------------------------------
# FUNCIONES DE APRENDIZAJE ADAPTATIVO
#-------------------------------------------------------------------------------

# Registrar un evento del sistema en la base de datos
record_system_event() {
    if ! $ADAPTIVE_LEARNING || ! command -v sqlite3 >/dev/null; then
        return
    fi
    
    local event_type="$1"
    local process_id="$2"
    local process_name="$3"
    local details="$4"
    
    # Escapar comillas simples para SQL
    process_name="${process_name//\'/\'\'}"
    details="${details//\'/\'\'}"
    
    sqlite3 "$LEARNING_DB" <<EOF
INSERT INTO system_events (event_type, process_id, process_name, details) 
VALUES ('$event_type', $process_id, '$process_name', '$details');

-- Mantener el historial dentro del límite configurado
DELETE FROM system_events 
WHERE id NOT IN (
    SELECT id FROM system_events 
    ORDER BY timestamp DESC 
    LIMIT $MAX_HISTORY_SIZE
);
EOF
}

# Actualizar o crear un patrón de proceso en la base de datos
update_process_pattern() {
    if ! $ADAPTIVE_LEARNING || ! command -v sqlite3 >/dev/null; then
        return
    fi
    
    local process_name="$1"
    local pattern_type="$2"
    local value="$3"
    
    # Escapar comillas simples para SQL
    process_name="${process_name//\'/\'\'}"
    
    # Verificar si ya existe un patrón para este proceso y tipo
    local existing=$(sqlite3 "$LEARNING_DB" "SELECT id, value, confidence, occurrences FROM process_patterns WHERE process_name='$process_name' AND pattern_type='$pattern_type' LIMIT 1;")
    
    if [ -n "$existing" ]; then
        # Existe, actualizar
        local id=$(echo "$existing" | cut -d'|' -f1)
        local old_value=$(echo "$existing" | cut -d'|' -f2)
        local confidence=$(echo "$existing" | cut -d'|' -f3)
        local occurrences=$(echo "$existing" | cut -d'|' -f4)
        
        # Calcular nuevo valor promedio
        local new_value=$(echo "scale=2; ($old_value * $occurrences + $value) / ($occurrences + 1)" | bc)
        
        # Actualizar confianza (aumenta con más ocurrencias)
        local new_confidence=$(echo "scale=0; $confidence + (100 - $confidence) / 10" | bc)
        if [ "$new_confidence" -gt 100 ]; then
            new_confidence=100
        fi
        
        # Actualizar registro
        sqlite3 "$LEARNING_DB" <<EOF
UPDATE process_patterns 
SET value=$new_value, 
    confidence=$new_confidence, 
    occurrences=occurrences+1, 
    last_seen=CURRENT_TIMESTAMP 
WHERE id=$id;
EOF
    else
        # No existe, insertar nuevo
        sqlite3 "$LEARNING_DB" <<EOF
INSERT INTO process_patterns (process_name, pattern_type, value, confidence, occurrences) 
VALUES ('$process_name', '$pattern_type', $value, 50, 1);
EOF
    fi
}

# Obtener umbrales ajustados para un proceso basado en patrones aprendidos
get_adjusted_thresholds() {
    if ! $ADAPTIVE_LEARNING || ! command -v sqlite3 >/dev/null; then
        return
    fi
    
    local process_name="$1"
    
    # Escapar comillas simples para SQL
    process_name="${process_name//\'/\'\'}"
    
    # Obtener patrones de CPU y memoria con confianza suficiente
    local cpu_pattern=$(sqlite3 "$LEARNING_DB" "SELECT value FROM process_patterns WHERE process_name='$process_name' AND pattern_type='CPU' AND confidence >= $PATTERN_CONFIDENCE_THRESHOLD ORDER BY last_seen DESC LIMIT 1;")
    
    local mem_pattern=$(sqlite3 "$LEARNING_DB" "SELECT value FROM process_patterns WHERE process_name='$process_name' AND pattern_type='memoria' AND confidence >= $PATTERN_CONFIDENCE_THRESHOLD ORDER BY last_seen DESC LIMIT 1;")
    
    # Si no hay patrones con suficiente confianza, usar los umbrales predeterminados
    if [ -z "$cpu_pattern" ]; then
        cpu_pattern=$CPU_THRESHOLD
    else
        # Ajustar el umbral con un margen basado en el valor aprendido
        cpu_pattern=$(echo "scale=1; $cpu_pattern * (1 + $THRESHOLD_ADJUSTMENT_RATE/100)" | bc)
        
        # Asegurar que no sea menor que el umbral mínimo ni mayor que 100
        if (( $(echo "$cpu_pattern < $CPU_THRESHOLD" | bc -l) )); then
            cpu_pattern=$CPU_THRESHOLD
        elif (( $(echo "$cpu_pattern > 100" | bc -l) )); then
            cpu_pattern=100
        fi
    fi
    
    if [ -z "$mem_pattern" ]; then
        mem_pattern=$MEM_THRESHOLD
    else
        # Ajustar el umbral con un margen basado en el valor aprendido
        mem_pattern=$(echo "scale=1; $mem_pattern * (1 + $THRESHOLD_ADJUSTMENT_RATE/100)" | bc)
        
        # Asegurar que no sea menor que el umbral mínimo ni mayor que 100
        if (( $(echo "$mem_pattern < $MEM_THRESHOLD" | bc -l) )); then
            mem_pattern=$MEM_THRESHOLD
        elif (( $(echo "$mem_pattern > 100" | bc -l) )); then
            mem_pattern=100
        fi
    fi
    
    # Devolver los umbrales ajustados
    echo "$cpu_pattern $mem_pattern"
}

#-------------------------------------------------------------------------------
# FUNCIONES DE INTERFAZ Y REPORTES
#-------------------------------------------------------------------------------

# Generar un informe de estado del sistema
generate_status_report() {
    local report_file="$TEMP_DIR/status_report.txt"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local uptime=$(uptime -p)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    local mem_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    local load_avg=$(cat /proc/loadavg | awk '{print $1 " " $2 " " $3}')
    
    # Calcular tiempo de ejecución de este script
    local runtime=$(($(date +%s) - START_TIME))
    local runtime_formatted=$(printf '%02d:%02d:%02d' $((runtime/3600)) $((runtime%3600/60)) $((runtime%60)))
    
    # Crear informe
    {
        echo "======== INFORME DE ESTADO DEL SISTEMA ========"
        echo "Timestamp: $timestamp"
        echo "Uptime: $uptime"
        echo "Carga del sistema: $load_avg"
        echo "Uso de CPU: $cpu_usage%"
        echo "Uso de memoria: ${mem_usage%.*}%"
        echo
        echo "======== ESTADÍSTICAS DEL MONITOR ========"
        echo "Tiempo de ejecución: $runtime_formatted"
        echo "Procesos monitoreados: $PROCESSES_MONITORED"
        echo "Acciones tomadas: $ACTIONS_TAKEN"
        echo "Zombies manejados: $ZOMBIES_HANDLED"
        echo "Procesos CPU alta manejados: $HIGH_CPU_HANDLED"
        echo "Procesos memoria alta manejados: $HIGH_MEM_HANDLED"
        echo "Advertencias: $WARNINGS_ISSUED"
        echo
        echo "======== PROCESOS TOP CPU ========"
        ps -eo pid,pcpu,pmem,nlwp,user,comm --sort=-pcpu | head -n 11
        echo
        echo "======== PROCESOS TOP MEMORIA ========"
        ps -eo pid,pmem,pcpu,nlwp,user,comm --sort=-pmem | head -n 11
        echo
        echo "======== ÚLTIMOS EVENTOS ========"
        
        # Mostrar últimos eventos si está habilitado el aprendizaje adaptativo
        if $ADAPTIVE_LEARNING && command -v sqlite3 >/dev/null; then
            sqlite3 -header -column "$LEARNING_DB" "SELECT event_type, process_name, datetime(timestamp, 'localtime') as time, details FROM system_events ORDER BY timestamp DESC LIMIT 10;"
        else
            echo "Aprendizaje adaptativo no está habilitado o SQLite no está disponible."
        fi
    } > "$report_file"
    
    # Mostrar el informe si estamos en modo interactivo
    if [ -t 1 ] && ! $SERVICE_MODE; then
        cat "$report_file"
    fi
    
    # Enviar notificación con resumen
    if $NOTIFY_USER; then
        notify_user "Informe de estado generado: $ACTIONS_TAKEN acciones, $ZOMBIES_HANDLED zombies, $HIGH_CPU_HANDLED CPU alta" "low"
    fi
    
    log 2 "Informe de estado generado en $report_file"
    
    # Enviar informe por correo si está configurado
    if $EMAIL_ALERTS && [ -n "$EMAIL_TO" ] && command -v mail >/dev/null; then
        cat "$report_file" | mail -s "Smart Process Monitor: Informe de Estado" "$EMAIL_TO"
    fi
}

# Generar informe de resumen al salir
generate_summary_report() {
    local runtime=$(($(date +%s) - START_TIME))
    local runtime_formatted=$(printf '%02d:%02d:%02d' $((runtime/3600)) $((runtime%3600/60)) $((runtime%60)))
    
    log 2 "=== RESUMEN DE EJECUCIÓN ==="
    log 2 "Tiempo de ejecución: $runtime_formatted"
    log 2 "Procesos monitoreados: $PROCESSES_MONITORED"
    log 2 "Acciones tomadas: $ACTIONS_TAKEN"
    log 2 "Zombies manejados: $ZOMBIES_HANDLED"
    log 2 "Procesos CPU alta manejados: $HIGH_CPU_HANDLED"
    log 2 "Procesos memoria alta manejados: $HIGH_MEM_HANDLED"
    log 2 "Advertencias: $WARNINGS_ISSUED"
    
    # Enviar notificación con resumen
    if $NOTIFY_USER; then
        notify_user "Monitor finalizado - Resumen: $ACTIONS_TAKEN acciones tomadas durante $runtime_formatted" "normal"
    fi
}

# Función para mostrar interfaz TUI (Text User Interface)
show_gui_interface() {
    if ! command -v dialog >/dev/null; then
        log 1 "No se puede mostrar la interfaz TUI: 'dialog' no está instalado"
        log 1 "Instale dialog con: sudo apt install dialog"
        log 1 "Continuando en modo consola..."
        return 1
    fi
    
    # Configuración inicial
    dialog --backtitle "Smart Process Monitor v$VERSION" \
           --title "Iniciando" \
           --infobox "Iniciando monitor de procesos...\nPor favor espere..." 5 40
    sleep 2
    
    # Bucle principal de UI
    while $RUNNING; do
        # Generar datos actualizados
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
        local mem_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
        local load_avg=$(cat /proc/loadavg | awk '{print $1}')
        local zombie_count=$(ps aux | awk '$8=="Z"' | wc -l)
        local runtime=$(($(date +%s) - START_TIME))
        local runtime_formatted=$(printf '%02d:%02d:%02d' $((runtime/3600)) $((runtime%3600/60)) $((runtime%60)))
        
        # Lista de procesos top por CPU
        local top_processes=$(ps -eo pid,pcpu,pmem,user,comm --sort=-pcpu | head -n 11)
        
        # Mostrar menú principal
        local choice
        dialog --clear --colors --backtitle "Smart Process Monitor v$VERSION" \
               --title "Panel de Control" \
               --ok-label "Seleccionar" --cancel-label "Salir" \
               --menu "\nEstadísticas del Sistema:
\Z1CPU:\Z0 ${cpu_usage%.*}%  |  \Z1Memoria:\Z0 ${mem_usage%.*}%  |  \Z1Carga:\Z0 $load_avg  |  \Z1Zombies:\Z0 $zombie_count
\Z1Tiempo de ejecución:\Z0 $runtime_formatted
\Z1Procesos monitoreados:\Z0 $PROCESSES_MONITORED  |  \Z1Acciones tomadas:\Z0 $ACTIONS_TAKEN
\Z1Modo:\Z0 $ACTION_MODE  |  \Z1Adaptativo:\Z0 $ADAPTIVE_LEARNING
" 18 78 8 \
               "1" "Ver procesos en tiempo real" \
               "2" "Generar informe detallado" \
               "3" "Configuración" \
               "4" "Ver estadísticas de acciones" \
               "5" "Ver log" \
               "6" "Ajustar umbrales" \
               "7" "Gestión de listas blancas" \
               "8" "Sobre Smart Process Monitor" 2>"$TEMP_DIR/dialog_result"
        
        # Obtener resultado
        choice=$?
        local menu_choice
        [ -f "$TEMP_DIR/dialog_result" ] && menu_choice=$(cat "$TEMP_DIR/dialog_result")
        
        # Procesar selección
        if [ $choice -eq 0 ]; then
            case $menu_choice in
                1) # Ver procesos en tiempo real
                    show_live_processes_dialog
                    ;;
                2) # Generar informe detallado
                    generate_status_report
                    dialog --backtitle "Smart Process Monitor v$VERSION" \
                           --title "Informe del Sistema" \
                           --textbox "$TEMP_DIR/status_report.txt" 24 80
                    ;;
                3) # Configuración
                    show_configuration_dialog
                    ;;
                4) # Ver estadísticas de acciones
                    show_action_statistics
                    ;;
                5) # Ver log
                    dialog --backtitle "Smart Process Monitor v$VERSION" \
                           --title "Archivo de Log" \
                           --textbox "$LOG_FILE" 24 80
                    ;;
                6) # Ajustar umbrales
                    adjust_thresholds_dialog
                    ;;
                7) # Gestión de listas blancas
                    manage_whitelist_dialog
                    ;;
                8) # Sobre
                    dialog --backtitle "Smart Process Monitor v$VERSION" \
                           --title "Sobre Smart Process Monitor" \
                           --msgbox "Smart Process Monitor v$VERSION\n\nSistema avanzado para gestión inteligente de procesos en Ubuntu\n\n• Monitor de procesos zombie\n• Control de procesos con alto consumo\n• Aprendizaje adaptativo\n• Interfaz TUI interactiva\n\nAutor: Claude (https://anthropic.com/claude)\n" 14 60
                    ;;
            esac
        else
            # Confirmar salida
            dialog --backtitle "Smart Process Monitor v$VERSION" \
                  --title "Confirmar" \
                  --yesno "¿Realmente desea salir del monitor?" 6 40
            if [ $? -eq 0 ]; then
                RUNNING=false
            fi
        fi
    done
    
    # Limpiar terminal al salir
    clear
    return 0
}

# Mostrar procesos en tiempo real (diálogo)
show_live_processes_dialog() {
    local refresh_interval=3
    local running=true
    
    while $running; do
        # Obtener datos actualizados
        local process_list=$(ps -eo pid,pcpu,pmem,user,comm --sort=-pcpu | head -n 20)
        
        # Mostrar diálogo con actualización en tiempo real
        dialog --backtitle "Smart Process Monitor v$VERSION" \
               --title "Procesos en Tiempo Real (Ordenados por CPU)" \
               --begin 3 3 \
               --tailboxbg <(echo "$process_list"; sleep "$refresh_interval") 18 70 \
               --and-widget \
               --begin 22 3 \
               --ok-label "Volver" \
               --msgbox "Actualizando cada $refresh_interval segundos. Presione OK para volver." 3 40
        
        running=false
    done
}

# Dialogo para mostrar estadísticas de acciones
show_action_statistics() {
    # Generar datos estadísticos
    local stats="=== ESTADÍSTICAS DE ACCIONES ===\n\n"
    stats+="Procesos monitoreados: $PROCESSES_MONITORED\n"
    stats+="Acciones totales tomadas: $ACTIONS_TAKEN\n"
    stats+="Procesos zombie gestionados: $ZOMBIES_HANDLED\n"
    stats+="Procesos CPU alta gestionados: $HIGH_CPU_HANDLED\n"
    stats+="Procesos memoria alta gestionados: $HIGH_MEM_HANDLED\n"
    stats+="Advertencias emitidas: $WARNINGS_ISSUED\n\n"
    
    # Mostrar estadísticas de patrones aprendidos si está habilitado
    if $ADAPTIVE_LEARNING && command -v sqlite3 >/dev/null; then
        stats+="=== PATRONES APRENDIDOS ===\n\n"
        local pattern_stats=$(sqlite3 -header -column "$LEARNING_DB" "SELECT process_name, pattern_type, value, confidence, occurrences FROM process_patterns WHERE confidence > 70 ORDER BY confidence DESC, occurrences DESC LIMIT 20;")
        stats+="$pattern_stats\n\n"
    fi
    
    # Mostrar diálogo
    dialog --backtitle "Smart Process Monitor v$VERSION" \
           --title "Estadísticas de Acciones" \
           --msgbox "$stats" 24 78
}

# Diálogo para ajustar umbrales
adjust_thresholds_dialog() {
    # Mostrar valores actuales
    local values
    values=$(dialog --backtitle "Smart Process Monitor v$VERSION" \
                  --title "Ajustar Umbrales" \
                  --form "Ajuste los umbrales para detección de procesos:\n" 15 60 6 \
                  "Umbral de CPU (%):" 1 1 "$CPU_THRESHOLD" 1 30 5 0 \
                  "Umbral de Memoria (%):" 2 1 "$MEM_THRESHOLD" 2 30 5 0 \
                  "Tiempo sostenido (seg):" 3 1 "$SUSTAINED_SECONDS" 3 30 5 0 \
                  "Intervalo (seg):" 4 1 "$MONITORING_INTERVAL" 4 30 5 0 \
                  2>"$TEMP_DIR/form_values")
    
    # Procesar valores si se presionó OK
    if [ $? -eq 0 ]; then
        # Leer valores nuevos
        mapfile -t form_values < "$TEMP_DIR/form_values"
        
        # Validar y aplicar valores
        local new_cpu="${form_values[0]}"
        local new_mem="${form_values[1]}"
        local new_sustained="${form_values[2]}"
        local new_interval="${form_values[3]}"
        
        # Validar que sean números
        if [[ "$new_cpu" =~ ^[0-9]+$ ]] && [[ "$new_mem" =~ ^[0-9]+$ ]] && 
           [[ "$new_sustained" =~ ^[0-9]+$ ]] && [[ "$new_interval" =~ ^[0-9]+$ ]]; then
            
            # Aplicar con límites seguros
            CPU_THRESHOLD=$(( new_cpu > 0 ? (new_cpu < 100 ? new_cpu : 99) : 1 ))
            MEM_THRESHOLD=$(( new_mem > 0 ? (new_mem < 100 ? new_mem : 99) : 1 ))
            SUSTAINED_SECONDS=$(( new_sustained > 1 ? (new_sustained < 60 ? new_sustained : 60) : 1 ))
            MONITORING_INTERVAL=$(( new_interval > 0 ? (new_interval < 10 ? new_interval : 10) : 1 ))
            
            log 2 "Umbrales actualizados: CPU=$CPU_THRESHOLD%, MEM=$MEM_THRESHOLD%, TIEMPO=$SUSTAINED_SECONDS seg, INTERVALO=$MONITORING_INTERVAL seg"
            
            dialog --backtitle "Smart Process Monitor v$VERSION" \
                   --title "Umbrales Actualizados" \
                   --msgbox "Los umbrales han sido actualizados exitosamente." 6 50
        else
            dialog --backtitle "Smart Process Monitor v$VERSION" \
                   --title "Error" \
                   --msgbox "Error: Todos los valores deben ser números enteros positivos." 6 60
        fi
    fi
}

# Diálogo para gestionar lista blanca
manage_whitelist_dialog() {
    # Mostrar lista blanca actual
    dialog --backtitle "Smart Process Monitor v$VERSION" \
           --title "Lista Blanca Actual" \
           --inputbox "Procesos en lista blanca (separados por |):\nEjemplo: firefox|chrome|java\n" 10 60 "$PROCESS_WHITELIST" \
           2>"$TEMP_DIR/whitelist_result"
    
    # Procesar resultado si se presionó OK
    if [ $? -eq 0 ]; then
        PROCESS_WHITELIST=$(cat "$TEMP_DIR/whitelist_result")
        log 2 "Lista blanca actualizada: $PROCESS_WHITELIST"
        
        dialog --backtitle "Smart Process Monitor v$VERSION" \
               --title "Lista Blanca Actualizada" \
               --msgbox "La lista blanca ha sido actualizada exitosamente." 6 50
    fi
}

# Diálogo para configuración
show_configuration_dialog() {
    # Valores para checklist
    local adaptive_check=$ADAPTIVE_LEARNING
    local whitelist_sys_check=$WHITELIST_SYSTEM_PROCESSES
    local notify_check=$NOTIFY_USER
    local desktop_notify_check=$NOTIFY_DESKTOP
    local email_check=$EMAIL_ALERTS
    
    # Crear diálogo con checklist para opciones booleanas
    dialog --backtitle "Smart Process Monitor v$VERSION" \
           --title "Configuración" \
           --separate-output \
           --checklist "Seleccione las opciones a habilitar:" 15 60 8 \
           "ADAPTIVE_LEARNING" "Aprendizaje adaptativo" $adaptive_check \
           "WHITELIST_SYSTEM" "Proteger procesos del sistema" $whitelist_sys_check \
           "NOTIFY_USER" "Notificaciones al usuario" $notify_check \
           "NOTIFY_DESKTOP" "Notificaciones de escritorio" $desktop_notify_check \
           "EMAIL_ALERTS" "Alertas por correo" $email_check \
           2>"$TEMP_DIR/checklist_result"
    
    # Procesar resultados si se presionó OK
    if [ $? -eq 0 ]; then
        # Resetear todas las opciones a false
        ADAPTIVE_LEARNING=false
        WHITELIST_SYSTEM_PROCESSES=false
        NOTIFY_USER=false
        NOTIFY_DESKTOP=false
        EMAIL_ALERTS=false
        
        # Activar solo las seleccionadas
        if [ -s "$TEMP_DIR/checklist_result" ]; then
            while IFS= read -r option; do
                case "$option" in
                    "ADAPTIVE_LEARNING") ADAPTIVE_LEARNING=true ;;
                    "WHITELIST_SYSTEM") WHITELIST_SYSTEM_PROCESSES=true ;;
                    "NOTIFY_USER") NOTIFY_USER=true ;;
                    "NOTIFY_DESKTOP") NOTIFY_DESKTOP=true ;;
                    "EMAIL_ALERTS") EMAIL_ALERTS=true ;;
                esac
            done < "$TEMP_DIR/checklist_result"
        fi
        
        log 2 "Configuración actualizada: ADAPTIVE=$ADAPTIVE_LEARNING, WHITELIST_SYS=$WHITELIST_SYSTEM_PROCESSES, NOTIFY=$NOTIFY_USER"
        
        # Si se activó el aprendizaje adaptativo, verificar base de datos
        if $ADAPTIVE_LEARNING && ! [ -f "$LEARNING_DB" ]; then
            initialize_pattern_database
        fi
        
        # Si se activaron las alertas por correo, pedir dirección
        if $EMAIL_ALERTS; then
            dialog --backtitle "Smart Process Monitor v$VERSION" \
                   --title "Configuración de Correo" \
                   --inputbox "Ingrese la dirección de correo para alertas:" 8 50 "$EMAIL_TO" \
                   2>"$TEMP_DIR/email_result"
            
            if [ $? -eq 0 ]; then
                EMAIL_TO=$(cat "$TEMP_DIR/email_result")
                log 2 "Dirección de correo actualizada: $EMAIL_TO"
            fi
        fi
        
        # Mostrar mensaje de confirmación
        dialog --backtitle "Smart Process Monitor v$VERSION" \
               --title "Configuración Actualizada" \
               --msgbox "La configuración ha sido actualizada exitosamente." 6 50
    fi
    
    # Seleccionar modo de acción
    dialog --backtitle "Smart Process Monitor v$VERSION" \
           --title "Modo de Acción" \
           --radiolist "Seleccione el modo de acción para procesos problemáticos:" 12 70 4 \
           "smart" "Inteligente (balance entre protección y rendimiento)" $([[ "$ACTION_MODE" == "smart" ]] && echo "on" || echo "off") \
           "gentle" "Gentil (prioriza estabilidad, menos agresivo)" $([[ "$ACTION_MODE" == "gentle" ]] && echo "on" || echo "off") \
           "aggressive" "Agresivo (prioriza rendimiento, más drástico)" $([[ "$ACTION_MODE" == "aggressive" ]] && echo "on" || echo "off") \
           "observe" "Observar (solo monitoreo, sin acciones)" $([[ "$ACTION_MODE" == "observe" ]] && echo "on" || echo "off") \
           2>"$TEMP_DIR/action_mode"
    
    if [ $? -eq 0 ]; then
        ACTION_MODE=$(cat "$TEMP_DIR/action_mode")
        log 2 "Modo de acción actualizado: $ACTION_MODE"
    fi
}

#-------------------------------------------------------------------------------
# FUNCIÓN PRINCIPAL Y CICLO PRINCIPAL
#-------------------------------------------------------------------------------

# Función principal
main() {
    # Procesar argumentos
    process_arguments "$@"
    
    # Mostrar banner de información
    if [ -t 1 ] && ! $SERVICE_MODE; then
        display_banner
    fi
    
    # Inicializar entorno
    initialize_environment
    
    # Cargar configuración
    load_configuration
    
    # Configurar manejadores de señales
    setup_signal_handlers
    
    # Si se especificó modo GUI, mostrar interfaz
    if $GUI_MODE; then
        show_gui_interface
        cleanup_and_exit
        return
    fi
    
    # Mostrar mensajes iniciales en modo consola
    if [ -t 1 ] && ! $SERVICE_MODE; then
        log 2 "Iniciando Smart Process Monitor v$VERSION"
        log 2 "Modo de acción: $ACTION_MODE"
        log 2 "Umbrales - CPU: $CPU_THRESHOLD%, Memoria: $MEM_THRESHOLD%, Sostenido: $SUSTAINED_SECONDS seg"
        log 2 "Aprendizaje adaptativo: $ADAPTIVE_LEARNING"
        log 2 "Presione Ctrl+C para detener"
        echo
    fi
    
    # Bucle principal
    while $RUNNING; do
        # Manejar procesos zombie
        handle_zombies
        
        # Manejar procesos con alto consumo de recursos
        handle_high_resource_processes
        
        # Generar informe cada cierto tiempo si estamos en modo servicio
        if $SERVICE_MODE; then
            # Calcular si es hora de un informe periódico (cada 6 horas)
            local current_time=$(date +%s)
            local elapsed_time=$((current_time - START_TIME))
            
            if [ $((elapsed_time % (6 * 3600))) -lt $((MONITORING_INTERVAL * 2)) ]; then
                generate_status_report
            fi
        fi
        
        # Esperar antes de la siguiente iteración
        sleep $MONITORING_INTERVAL
    done
}

# Procesar argumentos de línea de comandos
process_arguments() {
    # Establecer valores predeterminados
    CONFIG_FILE=""
    GUI_MODE=false
    SERVICE_MODE=false
    
    # Procesar argumentos
    for arg in "$@"; do
        case $arg in
            --config=*)
                CONFIG_FILE="${arg#*=}"
                ;;
            --gui)
                GUI_MODE=true
                ;;
            --service)
                SERVICE_MODE=true
                ;;
            --adaptive)
                ADAPTIVE_LEARNING=true
                ;;
            --gentle)
                ACTION_MODE="gentle"
                ;;
            --aggressive)
                ACTION_MODE="aggressive"
                ;;
            --observe)
                ACTION_MODE="observe"
                ;;
            --no-color)
                COLORS_ENABLED=false
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Opción desconocida: $arg"
                echo "Use --help para ver las opciones disponibles"
                exit 1
                ;;
        esac
    done
}

# Iniciar el script si se ejecuta directamente
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi