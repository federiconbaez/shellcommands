#!/bin/bash

# ===================================================================================
# GitMaster - Funciones de utilidad
# ===================================================================================
# Archivo de utilidades para GitMaster CLI
# Contiene todas las funciones auxiliares y comunes utilizadas en el script principal
# Versión: 2.0.0
# Fecha: 01-04-2025
# ===================================================================================

# Colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Variables globales para configuración
GITMASTER_VERSION="2.0.0"
GITMASTER_CONFIG_DIR="$HOME/.gitmaster"
GITMASTER_CONFIG_FILE="$GITMASTER_CONFIG_DIR/config.json"
GITMASTER_CACHE_DIR="$GITMASTER_CONFIG_DIR/cache"
GITMASTER_TEMP_DIR="$GITMASTER_CONFIG_DIR/temp"
GITHUB_API_URL="https://api.github.com"
DEFAULT_PROTOCOL="https"
MAX_CACHE_AGE=3600 # 1 hora en segundos

# ===================================================================================
# Función para mostrar la cabecera de la aplicación
# ===================================================================================
show_header() {
    echo -e "${CYAN}"
    echo -e "╔═════════════════════════════════════════════════════════════════╗"
    echo -e "║ ${BOLD}GitMaster v$GITMASTER_VERSION${NC}${CYAN}                                          ║"
    echo -e "║ La herramienta definitiva para dominar GitHub desde la terminal ║"
    echo -e "╚═════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# ===================================================================================
# Funciones para mensajes e impresión
# ===================================================================================

# Función para mostrar mensajes informativos
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Función para mostrar mensajes de éxito
success() {
    echo -e "${GREEN}[ÉXITO]${NC} $1"
}

# Función para mostrar mensajes de advertencia
warning() {
    echo -e "${YELLOW}[ADVERTENCIA]${NC} $1"
}

# Función para mostrar mensajes de error
error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Función para mostrar mensajes de depuración
debug() {
    if [ "${GITMASTER_DEBUG:-false}" = "true" ]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $1"
    fi
}

# Función para mostrar progreso
show_spinner() {
    local pid=$1
    local message="${2:-Procesando...}"
    local delay=0.1
    local spinstr='|/-\'
    
    echo -ne "${CYAN}$message ${NC}"
    
    while [ "$(ps a | awk '{print $1}' | grep -w $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    
    printf "    \b\b\b\b"
}

# Función para mostrar una tabla
print_table_header() {
    local header="$1"
    local columns="$2"
    local widths=("${@:3}")
    
    # Construir línea de encabezado
    local header_line="${CYAN}┌"
    local column_headers="${CYAN}│${NC}"
    local separator_line="${CYAN}├"
    
    local i=0
    for col in $columns; do
        local width=${widths[$i]}
        local padding=$(( width - ${#col} ))
        
        # Crear separadores para la línea superior
        header_line+=$(printf "%0.s─" $(seq 1 $(( width + 2 ))))
        header_line+="┬"
        
        # Crear separadores para la línea intermedia
        separator_line+=$(printf "%0.s─" $(seq 1 $(( width + 2 ))))
        separator_line+="┼"
        
        # Crear encabezados de columna con padding
        column_headers+=" ${BOLD}$col${NC}${CYAN}"
        column_headers+=$(printf "%0.s " $(seq 1 $padding))
        column_headers+="│${NC}"
        
        i=$((i + 1))
    done
    
    # Cerrar líneas
    header_line="${header_line%?}┐${NC}"
    separator_line="${separator_line%?}┤${NC}"
    
    # Imprimir tabla
    echo -e "\n${CYAN}${BOLD}$header${NC}"
    echo -e "$header_line"
    echo -e "$column_headers"
    echo -e "$separator_line"
}

print_table_row() {
    local values=("$@")
    local color_codes=()
    local actual_values=()
    
    # Extraer códigos de color y valores reales
    for ((i=0; i<${#values[@]}; i++)); do
        if [[ "${values[$i]}" =~ ^\\\033\[[0-9;]+m ]]; then
            color_codes[$i]=$(echo "${values[$i]}" | grep -o '\\033\[[0-9;]*m')
            actual_values[$i]=$(echo "${values[$i]}" | sed 's/\\033\[[0-9;]*m//g')
        else
            color_codes[$i]=""
            actual_values[$i]="${values[$i]}"
        fi
    done
    
    local row="${CYAN}│${NC}"
    for ((i=0; i<${#actual_values[@]}; i++)); do
        local value="${actual_values[$i]}"
        if [ -n "${color_codes[$i]}" ]; then
            row+=" ${color_codes[$i]}$value${NC} "
        else
            row+=" $value "
        fi
        row+="${CYAN}│${NC}"
    done
    
    echo -e "$row"
}

print_table_footer() {
    local widths=("$@")
    
    local footer_line="${CYAN}└"
    
    for width in "${widths[@]}"; do
        footer_line+=$(printf "%0.s─" $(seq 1 $(( width + 2 ))))
        footer_line+="┴"
    done
    
    footer_line="${footer_line%?}┘${NC}"
    echo -e "$footer_line"
}

# ===================================================================================
# Funciones de inicialización y configuración
# ===================================================================================

# Crear directorios de configuración si no existen
init_config_dirs() {
    mkdir -p "$GITMASTER_CONFIG_DIR"
    mkdir -p "$GITMASTER_CACHE_DIR"
    mkdir -p "$GITMASTER_TEMP_DIR"
    
    if [ ! -f "$GITMASTER_CONFIG_FILE" ]; then
        echo '{
            "theme": "default",
            "default_protocol": "https",
            "cache_enabled": true,
            "max_cache_age": 3600,
            "default_license": "mit",
            "github": {
                "token": "",
                "username": "",
                "email": ""
            },
            "templates": {
                "readme": "default",
                "gitignore": "default",
                "license": "mit"
            },
            "git_flow": {
                "enabled": true,
                "main_branch": "main",
                "develop_branch": "develop",
                "feature_prefix": "feature/",
                "release_prefix": "release/",
                "hotfix_prefix": "hotfix/",
                "bugfix_prefix": "bugfix/"
            }
        }' > "$GITMASTER_CONFIG_FILE"
    fi
}

# Verificar dependencias
check_dependencies() {
    local dependencies=("git" "curl" "jq" "awk" "sed" "grep" "tr")
    local missing=()
    
    info "Verificando dependencias..."
    
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        error "Faltan las siguientes dependencias:"
        for cmd in "${missing[@]}"; do
            echo "  - $cmd"
        done
        echo -e "${YELLOW}Por favor, instala las dependencias faltantes e intenta de nuevo.${NC}"
        return 1
    fi
    
    success "Todas las dependencias están instaladas."
    return 0
}

# Cargar configuración
load_config() {
    debug "Cargando configuración desde $GITMASTER_CONFIG_FILE"
    if [ ! -f "$GITMASTER_CONFIG_FILE" ]; then
        error "Archivo de configuración no encontrado. Ejecuta 'gitmaster config init' para crear uno."
        return 1
    fi
    
    # Cargar token de GitHub
    GITHUB_TOKEN=$(jq -r '.github.token' "$GITMASTER_CONFIG_FILE")
    GITHUB_USERNAME=$(jq -r '.github.username' "$GITMASTER_CONFIG_FILE")
    GITHUB_EMAIL=$(jq -r '.github.email' "$GITMASTER_CONFIG_FILE")
    
    # Cargar otras configuraciones
    DEFAULT_PROTOCOL=$(jq -r '.default_protocol' "$GITMASTER_CONFIG_FILE")
    MAX_CACHE_AGE=$(jq -r '.max_cache_age' "$GITMASTER_CONFIG_FILE")
    
    # Comprobar si se debe usar el token de entorno en lugar del de configuración
    if [ -n "$GITHUB_TOKEN_ENV" ]; then
        debug "Usando token de GitHub desde variable de entorno"
        GITHUB_TOKEN="$GITHUB_TOKEN_ENV"
    fi
    
    return 0
}

# Verificar token de GitHub
check_github_token() {
    if [ -z "$GITHUB_TOKEN" ]; then
        error "No se ha configurado el token de GitHub."
        echo "Configura tu token con alguna de estas opciones:"
        echo "  1. Exportar variable de entorno: export GITHUB_TOKEN=tu_token_aquí"
        echo "  2. Configurar en gitmaster: gitmaster config set github.token tu_token_aquí"
        return 1
    fi
    
    # Verificar si el token es válido haciendo una petición a la API
    debug "Verificando validez del token de GitHub"
    local response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API_URL/user")
    
    if [ "$response" -ne 200 ]; then
        error "El token de GitHub no es válido o ha expirado."
        return 1
    fi
    
    success "Token de GitHub verificado correctamente."
    return 0
}

# ===================================================================================
# Funciones de API de GitHub
# ===================================================================================

# Función base para hacer peticiones a la API de GitHub
github_api_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local headers="${4:-}"
    
    local url="$GITHUB_API_URL$endpoint"
    local curl_args=("-s" "-X" "$method" "-H" "Authorization: token $GITHUB_TOKEN" "-H" "Accept: application/vnd.github.v3+json")
    
    # Añadir headers adicionales si se proporcionan
    if [ -n "$headers" ]; then
        IFS=',' read -ra header_array <<< "$headers"
        for header in "${header_array[@]}"; do
            curl_args+=("-H" "$header")
        done
    fi
    
    # Añadir datos si se proporcionan
    if [ -n "$data" ]; then
        curl_args+=("-H" "Content-Type: application/json" "-d" "$data")
    fi
    
    # Hacer la petición y devolver el resultado
    debug "Petición API: $method $url"
    curl "${curl_args[@]}" "$url"
}

# Obtener información del usuario autenticado
get_user_info() {
    if ! check_github_token; then
        return 1
    fi
    
    info "Obteniendo información del usuario..."
    github_api_request "GET" "/user"
}

# Obtener nombre de usuario autenticado
get_username() {
    if [ -n "$GITHUB_USERNAME" ]; then
        echo "$GITHUB_USERNAME"
        return 0
    fi
    
    if ! check_github_token; then
        return 1
    fi
    
    local username=$(github_api_request "GET" "/user" | jq -r '.login')
    if [ "$username" = "null" ] || [ -z "$username" ]; then
        error "No se pudo obtener el nombre de usuario."
        return 1
    fi
    
    echo "$username"
}

# Obtener URL del repositorio actual
get_current_repo() {
    local remote_url=$(git config --get remote.origin.url)
    local repo_name=$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+/[^/]+)(.git)?$|\1|')
    
    if [ -z "$repo_name" ]; then
        error "No se pudo determinar el repositorio actual."
        return 1
    fi
    
    echo "$repo_name"
}

# Función para obtener la rama actual
get_current_branch() {
    git symbolic-ref --short HEAD 2>/dev/null
}

# ===================================================================================
# Funciones para caché y persistencia
# ===================================================================================

# Guardar en caché
cache_save() {
    local key="$1"
    local data="$2"
    local cache_file="$GITMASTER_CACHE_DIR/${key//\//_}"
    
    echo "$data" > "$cache_file"
    touch "$cache_file"  # Actualizar timestamp
}

# Cargar desde caché
cache_load() {
    local key="$1"
    local max_age="${2:-$MAX_CACHE_AGE}"
    local cache_file="$GITMASTER_CACHE_DIR/${key//\//_}"
    
    if [ -f "$cache_file" ]; then
        local file_age=$(($(date +%s) - $(stat -c %Y "$cache_file")))
        if [ "$file_age" -lt "$max_age" ]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    return 1
}

# Limpiar caché
cache_clear() {
    local key="$1"
    
    if [ -z "$key" ]; then
        rm -rf "$GITMASTER_CACHE_DIR"/*
        mkdir -p "$GITMASTER_CACHE_DIR"
        success "Caché limpiada completamente."
    else
        local cache_file="$GITMASTER_CACHE_DIR/${key//\//_}"
        if [ -f "$cache_file" ]; then
            rm "$cache_file"
            success "Caché para '$key' eliminada."
        else
            warning "No se encontró caché para '$key'."
        fi
    fi
}

# Comprobar si la caché está activada
is_cache_enabled() {
    local cache_enabled=$(jq -r '.cache_enabled' "$GITMASTER_CONFIG_FILE")
    [ "$cache_enabled" = "true" ]
}

# ===================================================================================
# Utilidades para Git
# ===================================================================================

# Verificar si un directorio es un repositorio git
is_git_repo() {
    local dir="${1:-.}"
    [ -d "$dir/.git" ]
}

# Verificar si hay cambios sin commit
has_uncommitted_changes() {
    git status --porcelain | grep -q .
}

# Obtener URL remota del repositorio
get_remote_url() {
    local remote="${1:-origin}"
    git config --get remote."$remote".url
}

# Construir una URL de repositorio completa
build_repo_url() {
    local repo="$1"
    local protocol="${2:-$DEFAULT_PROTOCOL}"
    
    # Si ya es una URL completa, devolverla
    if [[ "$repo" =~ ^(https?|git@) ]]; then
        echo "$repo"
        return 0
    fi
    
    # Si tiene formato username/repo
    if [[ "$repo" =~ ^[^/]+/[^/]+$ ]]; then
        if [ "$protocol" = "ssh" ]; then
            echo "git@github.com:$repo.git"
        else
            echo "https://github.com/$repo.git"
        fi
        return 0
    fi
    
    # Si solo es el nombre del repo, añadir el username
    local username=$(get_username)
    if [ "$protocol" = "ssh" ]; then
        echo "git@github.com:$username/$repo.git"
    else
        echo "https://github.com/$username/$repo.git"
    fi
}

# ===================================================================================
# Exportar funciones
# ===================================================================================

# Exportar todas las funciones para que estén disponibles en el script principal
export -f show_header
export -f info success warning error debug
export -f show_spinner
export -f print_table_header print_table_row print_table_footer
export -f init_config_dirs check_dependencies load_config check_github_token
export -f github_api_request get_user_info get_username
export -f get_current_repo get_current_branch
export -f cache_save cache_load cache_clear is_cache_enabled
export -f is_git_repo has_uncommitted_changes get_remote_url build_repo_url