#!/bin/bash

# ███████╗ ██████╗ ██╗████████╗███╗   ███╗ █████╗ ███████╗████████╗███████╗██████╗ 
# ██╔════╝██╔════╝ ██║╚══██╔══╝████╗ ████║██╔══██╗██╔════╝╚══██╔══╝██╔════╝██╔══██╗
# ██║     ██║  ███╗██║   ██║   ██╔████╔██║███████║███████╗   ██║   █████╗  ██████╔╝
# ██║     ██║   ██║██║   ██║   ██║╚██╔╝██║██╔══██║╚════██║   ██║   ██╔══╝  ██╔══██╗
# ╚██████╗╚██████╔╝██║   ██║   ██║ ╚═╝ ██║██║  ██║███████║   ██║   ███████╗██║  ██║
#  ╚═════╝ ╚═════╝ ╚═╝   ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
#
# GitMaster - Herramienta avanzada para GitHub
# Creado por: Claude 3.7 Sonnet - Un asistente de Anthropic con capacidades de razonamiento avanzadas
# Versión: 2.0.0
# Fecha: 01-04-2025
#
# Una herramienta de línea de comandos para interactuar con GitHub de manera avanzada
# Características:
# - Gestión completa de repositorios (crear, clonar, eliminar)
# - Flujo de trabajo Git con GitFlow integrado
# - Búsqueda avanzada de repositorios y usuarios
# - Análisis de tendencias y estadísticas
# - Gestión de issues y pull requests
# - Integración con GitHub Actions
# - Análisis de código y seguridad
# - Y mucho más...

# ===================================================================================
# Configuración y Variables
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

# Variables globales
GITMASTER_VERSION="2.0.0"
GITMASTER_CONFIG_DIR="$HOME/.gitmaster"
GITMASTER_CONFIG_FILE="$GITMASTER_CONFIG_DIR/config.json"
GITMASTER_CACHE_DIR="$GITMASTER_CONFIG_DIR/cache"
GITMASTER_TEMP_DIR="$GITMASTER_CONFIG_DIR/temp"
GITHUB_API_URL="https://api.github.com"
DEFAULT_PROTOCOL="https"
MAX_CACHE_AGE=3600 # 1 hora en segundos

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

# ===================================================================================
# Funciones de utilidad y mensajes
# ===================================================================================

# Función para mostrar la cabecera de la aplicación
show_header() {
    echo -e "${CYAN}"
    echo -e "╔═════════════════════════════════════════════════════════════════╗"
    echo -e "║ ${BOLD}GitMaster v$GITMASTER_VERSION${NC}${CYAN}                                          ║"
    echo -e "║ La herramienta definitiva para dominar GitHub desde la terminal ║"
    echo -e "╚═════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

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

# ===================================================================================
# Verificación de dependencias y configuración
# ===================================================================================

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
        exit 1
    fi
    
    success "Todas las dependencias están instaladas."
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

# ===================================================================================
# Funciones para gestión de repositorios
# ===================================================================================

# Crear un nuevo repositorio en GitHub
create_repo() {
    if ! check_github_token; then
        return 1
    fi
    
    local repo_name="$1"
    local description="$2"
    local is_private="${3:-false}"
    local has_issues="${4:-true}"
    local has_wiki="${5:-true}"
    local has_projects="${6:-true}"
    local license="${7:-mit}"
    local gitignore="${8:-}"
    
    if [ -z "$repo_name" ]; then
        error "Debe proporcionar un nombre para el repositorio."
        return 1
    fi
    
    if [ -z "$description" ]; then
        description="Repositorio creado con GitMaster CLI"
    fi
    
    # Convertir a booleano para API
    if [[ "$is_private" =~ ^(true|t|yes|y|private|priv|1)$ ]]; then
        is_private="true"
    else
        is_private="false"
    fi
    
    info "Creando repositorio: $repo_name (privado: $is_private)"
    
    local data="{
        \"name\": \"$repo_name\",
        \"description\": \"$description\",
        \"private\": $is_private,
        \"has_issues\": $has_issues,
        \"has_wiki\": $has_wiki,
        \"has_projects\": $has_projects,
        \"auto_init\": true
    }"
    
    # Añadir license template si se proporciona
    if [ -n "$license" ] && [ "$license" != "none" ]; then
        data=$(echo "$data" | jq --arg license "$license" '. + {"license_template": $license}')
    fi
    
    # Añadir gitignore template si se proporciona
    if [ -n "$gitignore" ] && [ "$gitignore" != "none" ]; then
        data=$(echo "$data" | jq --arg gitignore "$gitignore" '. + {"gitignore_template": $gitignore}')
    fi
    
    local response=$(github_api_request "POST" "/user/repos" "$data")
    local repo_url=$(echo "$response" | jq -r '.html_url')
    
    if [ "$repo_url" = "null" ] || [ -z "$repo_url" ]; then
        error "Error al crear el repositorio. Respuesta:"
        echo "$response" | jq '.'
        return 1
    fi
    
    success "Repositorio creado: $repo_url"
    
    echo "$repo_url"
}

# Eliminar un repositorio
delete_repo() {
    if ! check_github_token; then
        return 1
    fi
    
    local username=$(get_username)
    local repo_name="$1"
    
    if [ -z "$repo_name" ]; then
        error "Debe proporcionar un nombre de repositorio."
        return 1
    fi
    
    # Confirmar eliminación
    read -p "¿Estás seguro de que deseas eliminar el repositorio '$username/$repo_name'? Esta acción no se puede deshacer. (s/N): " confirm
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        info "Operación cancelada."
        return 0
    fi
    
    info "Eliminando repositorio: $username/$repo_name"
    
    local response=$(github_api_request "DELETE" "/repos/$username/$repo_name")
    local status=$?
    
    if [ $status -eq 0 ] && [ -z "$response" ]; then
        success "Repositorio eliminado correctamente."
        return 0
    else
        error "Error al eliminar el repositorio. Respuesta:"
        echo "$response" | jq '.' 2>/dev/null || echo "$response"
        return 1
    fi
}

# Listar repositorios del usuario
list_repos() {
    if ! check_github_token; then
        return 1
    fi
    
    local username=$(get_username)
    local type="${1:-all}" # all, owner, member
    local sort="${2:-updated}" # created, updated, pushed, full_name
    local direction="${3:-desc}" # asc, desc
    local per_page="${4:-100}"
    local page="${5:-1}"
    
    info "Obteniendo repositorios ($type) para el usuario $username..."
    
    local endpoint="/user/repos?type=$type&sort=$sort&direction=$direction&per_page=$per_page&page=$page"
    local repos=$(github_api_request "GET" "$endpoint")
    
    if [ $? -ne 0 ] || [ -z "$repos" ]; then
        error "Error al obtener repositorios."
        return 1
    fi
    
    # Mostrar repositorios en formato tabla
    echo -e "\n${CYAN}${BOLD}Repositorios de $username${NC}"
    echo -e "${CYAN}┌──────────────────────────────────┬───────────┬────────────────────┬─────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Nombre                          ${NC}${CYAN}│ ${BOLD}Privado   ${NC}${CYAN}│ ${BOLD}Última actualización${NC}${CYAN} │ ${BOLD}Estrellas    ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├──────────────────────────────────┼───────────┼────────────────────┼─────────────┤${NC}"
    
    echo "$repos" | jq -r '.[] | [.name, .private, .updated_at, .stargazers_count] | @tsv' | while IFS=$'\t' read -r name private updated stars; do
        # Formatear fecha
        updated=$(date -d "$updated" '+%Y-%m-%d %H:%M:%S')
        
        # Formatear privado
        if [ "$private" = "true" ]; then
            private="${YELLOW}Sí${NC}"
        else
            private="${GREEN}No${NC}"
        fi
        
        # Formatear estrellas
        if [ "$stars" -gt 0 ]; then
            stars="${YELLOW}$stars ⭐${NC}"
        else
            stars="0"
        fi
        
        printf "│ %-32s │ %-9s │ %-18s │ %-11s │\n" "$name" "$private" "$updated" "$stars"
    done
    
    echo -e "${CYAN}└──────────────────────────────────┴───────────┴────────────────────┴─────────────┘${NC}"
    
    local total=$(echo "$repos" | jq '. | length')
    echo -e "\nTotal: $total repositorios"
}

# Clonar un repositorio y configurarlo
clone_repo() {
    local repo_url="$1"
    local directory="$2"
    local configure="${3:-true}"
    
    if [ -z "$repo_url" ]; then
        error "Debe proporcionar una URL de repositorio."
        return 1
    fi
    
    # Si solo se proporciona el nombre del repositorio, construir la URL completa
    if [[ ! "$repo_url" =~ ^(https?|git@) ]]; then
        # Verificar si tiene el formato username/repo
        if [[ "$repo_url" =~ ^[^/]+/[^/]+$ ]]; then
            repo_url="https://github.com/$repo_url.git"
        else
            local username=$(get_username)
            repo_url="https://github.com/$username/$repo_url.git"
        fi
    fi
    
    if [ -z "$directory" ]; then
        directory=$(basename "$repo_url" .git)
    fi
    
    info "Clonando repositorio: $repo_url en $directory"
    
    # Función para ejecutar en segundo plano y mostrar spinner
    clone_with_progress() {
        git clone --progress "$1" "$2" > "$GITMASTER_TEMP_DIR/clone_output.log" 2>&1
        return $?
    }
    
    # Clonar en segundo plano y mostrar spinner
    clone_with_progress "$repo_url" "$directory" &
    local pid=$!
    show_spinner $pid "Clonando repositorio..."
    wait $pid
    local status=$?
    
    if [ $status -eq 0 ]; then
        success "Repositorio clonado correctamente en: $directory"
        
        if [ "$configure" = "true" ]; then
            cd "$directory" || return 1
            info "Configurando repositorio..."
            
            # Configurar git flow si está habilitado
            local git_flow_enabled=$(jq -r '.git_flow.enabled' "$GITMASTER_CONFIG_FILE")
            if [ "$git_flow_enabled" = "true" ]; then
                info "Configurando Git Flow..."
                
                local main_branch=$(jq -r '.git_flow.main_branch' "$GITMASTER_CONFIG_FILE")
                local develop_branch=$(jq -r '.git_flow.develop_branch' "$GITMASTER_CONFIG_FILE")
                
                # Verificar si la rama develop existe, si no, crearla desde main
                if ! git show-ref --verify --quiet "refs/heads/$develop_branch"; then
                    info "Creando rama $develop_branch desde $main_branch..."
                    git checkout -b "$develop_branch" || warning "No se pudo crear la rama $develop_branch"
                fi
                
                # Configurar opciones de git flow
                git config gitflow.branch.master "$main_branch"
                git config gitflow.branch.develop "$develop_branch"
                git config gitflow.prefix.feature "$(jq -r '.git_flow.feature_prefix' "$GITMASTER_CONFIG_FILE")"
                git config gitflow.prefix.release "$(jq -r '.git_flow.release_prefix' "$GITMASTER_CONFIG_FILE")"
                git config gitflow.prefix.hotfix "$(jq -r '.git_flow.hotfix_prefix' "$GITMASTER_CONFIG_FILE")"
                git config gitflow.prefix.bugfix "$(jq -r '.git_flow.bugfix_prefix' "$GITMASTER_CONFIG_FILE")"
            fi
            
            # Configuración general de git
            git config pull.rebase true
            
            success "Configuración completada."
        fi
    else
        error "Error al clonar el repositorio."
        cat "$GITMASTER_TEMP_DIR/clone_output.log"
        return 1
    fi
}

# Inicializar un repositorio local y subirlo a GitHub
init_and_push() {
    local repo_name="$1"
    local description="$2"
    local is_private="${3:-false}"
    local license="${4:-mit}"
    local gitignore="${5:-}"
    
    if [ -z "$repo_name" ]; then
        repo_name=$(basename "$(pwd)")
        warning "No se proporcionó nombre de repositorio. Usando: $repo_name"
    fi
    
    # Inicializar repositorio local si no existe
    if [ ! -d ".git" ]; then
        info "Inicializando repositorio local..."
        git init
    else
        info "El repositorio local ya está inicializado."
    fi
    
    # Crear archivo README.md si no existe
    if [ ! -f "README.md" ]; then
        info "Creando archivo README.md..."
        
        # Crear README con plantilla
        cat > "README.md" << EOF
# $repo_name

$description

## Descripción

Este proyecto fue creado y es mantenido con [GitMaster CLI](https://github.com/anthropic/gitmaster).

## Instalación

\`\`\`bash
# Clonar el repositorio
git clone https://github.com/$(get_username)/$repo_name.git
cd $repo_name

# Instalar dependencias
# ...
\`\`\`

## Uso

\`\`\`bash
# Ejemplos de uso
# ...
\`\`\`

## Licencia

Este proyecto está licenciado bajo la licencia $license.
EOF
    fi
    
    # Crear .gitignore si no existe y se especificó una plantilla
    if [ ! -f ".gitignore" ] && [ -n "$gitignore" ] && [ "$gitignore" != "none" ]; then
        info "Creando archivo .gitignore con plantilla $gitignore..."
        
        # Obtener plantilla de gitignore de GitHub
        curl -s "https://raw.githubusercontent.com/github/gitignore/master/${gitignore}.gitignore" > ".gitignore"
        
        # Añadir gitignore personalizado para GitMaster
        cat >> ".gitignore" << EOF

# GitMaster específico
.gitmaster/
EOF
    fi
    
    # Hacer commit inicial si es necesario
    if git status --porcelain | grep -q '^??'; then
        info "Realizando commit inicial..."
        git add .
        git commit -m "Initial commit"
    fi
    
    # Crear repositorio en GitHub
    local repo_url=$(create_repo "$repo_name" "$description" "$is_private" "true" "true" "true" "$license" "$gitignore")
    
    if [ -z "$repo_url" ]; then
        error "No se pudo crear el repositorio en GitHub."
        return 1
    fi
    
    # Configurar remoto y subir
    info "Configurando remoto y subiendo código..."
    
    # Obtener la URL del repositorio en formato SSH o HTTPS según configuración
    local remote_url
    if [ "$DEFAULT_PROTOCOL" = "ssh" ]; then
        remote_url=$(echo "$repo_url" | sed 's|https://github.com/|git@github.com:|')
    else
        remote_url="$repo_url.git"
    fi
    
    git remote add origin "$remote_url"
    
    # Determinar la rama principal
    local main_branch=$(jq -r '.git_flow.main_branch' "$GITMASTER_CONFIG_FILE")
    git branch -M "$main_branch"
    
    # Subir al repositorio remoto
    git push -u origin "$main_branch"
    
    # Configurar Git Flow si está habilitado
    local git_flow_enabled=$(jq -r '.git_flow.enabled' "$GITMASTER_CONFIG_FILE")
    if [ "$git_flow_enabled" = "true" ]; then
        info "Configurando Git Flow..."
        
        local develop_branch=$(jq -r '.git_flow.develop_branch' "$GITMASTER_CONFIG_FILE")
        
        # Crear rama develop
        git checkout -b "$develop_branch"
        
        # Configurar opciones de git flow
        git config gitflow.branch.master "$main_branch"
        git config gitflow.branch.develop "$develop_branch"
        git config gitflow.prefix.feature "$(jq -r '.git_flow.feature_prefix' "$GITMASTER_CONFIG_DIR/config.json")"
        git config gitflow.prefix.release "$(jq -r '.git_flow.release_prefix' "$GITMASTER_CONFIG_DIR/config.json")"
        git config gitflow.prefix.hotfix "$(jq -r '.git_flow.hotfix_prefix' "$GITMASTER_CONFIG_DIR/config.json")"
        git config gitflow.prefix.bugfix "$(jq -r '.git_flow.bugfix_prefix' "$GITMASTER_CONFIG_DIR/config.json")"
        
        # Subir rama develop
        git push -u origin "$develop_branch"
    fi
    
    success "Repositorio inicializado y subido a GitHub: $repo_url"
}

# ===================================================================================
# Funciones de búsqueda y exploración
# ===================================================================================

# Buscar repositorios por palabras clave
search_repos() {
    if ! check_github_token; then
        return 1
    fi
    
    local query="$1"
    local sort="${2:-stars}" # stars, forks, updated
    local order="${3:-desc}" # asc, desc
    local per_page="${4:-10}"
    local page="${5:-1}"
    
    if [ -z "$query" ]; then
        error "Debe proporcionar una consulta de búsqueda."
        return 1
    fi
    
    info "Buscando repositorios: \"$query\""
    
    local encoded_query=$(echo "$query" | jq -s -R -r @uri)
    local endpoint="/search/repositories?q=$encoded_query&sort=$sort&order=$order&per_page=$per_page&page=$page"
    local response=$(github_api_request "GET" "$endpoint")
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        error "Error al buscar repositorios."
        return 1
    fi
    
    local total_count=$(echo "$response" | jq '.total_count')
    
    # Mostrar resultados en formato tabla
    echo -e "\n${CYAN}${BOLD}Resultados de búsqueda para \"$query\" (Total: $total_count)${NC}"
    echo -e "${CYAN}┌──────────────────────────────────┬──────────────────────┬─────────┬─────────┬───────────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Repositorio                      ${NC}${CYAN}│ ${BOLD}Propietario         ${NC}${CYAN}│ ${BOLD}Estrellas${NC}${CYAN} │ ${BOLD}Forks   ${NC}${CYAN}│ ${BOLD}Actualizado      ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├──────────────────────────────────┼──────────────────────┼─────────┼─────────┼───────────────────┤${NC}"
    
    echo "$response" | jq -r '.items[] | [.full_name, .owner.login, .stargazers_count, .forks_count, .updated_at] | @tsv' | while IFS=$'\t' read -r full_name owner stars forks updated; do
        # Separar nombre del repositorio del propietario
        local repo_name="${full_name#*/}"
        
        # Formatear fecha
        updated=$(date -d "$updated" '+%Y-%m-%d')
        
        # Formatear estrellas y forks
        stars="${stars} ⭐"
        forks="${forks} 🍴"
        
        printf "│ %-32s │ %-20s │ %-9s │ %-9s │ %-17s │\n" "$repo_name" "$owner" "$stars" "$forks" "$updated"
    done
    
     echo -e "${CYAN}└──────────────────────────────────┴──────────────────────┴─────────┴─────────┴───────────────────┘${NC}"
    
    # Si hay más resultados, mostrar paginación
    if [ "$total_count" -gt "$per_page" ]; then
        local total_pages=$(( ($total_count + $per_page - 1) / $per_page ))
        echo -e "\nPágina $page de $total_pages"
        
        if [ "$page" -lt "$total_pages" ]; then
            echo -e "Para ver más resultados: ${YELLOW}gitmaster search repo \"$query\" $sort $order $per_page $((page + 1))${NC}"
        fi
    fi
}

# Buscar usuarios por nombre o correo electrónico
search_users() {
    if ! check_github_token; then
        return 1
    fi
    
    local query="$1"
    local sort="${2:-repositories}" # followers, repositories, joined
    local order="${3:-desc}" # asc, desc
    local per_page="${4:-10}"
    local page="${5:-1}"
    
    if [ -z "$query" ]; then
        error "Debe proporcionar una consulta de búsqueda."
        return 1
    fi
    
    info "Buscando usuarios: \"$query\""
    
    local encoded_query=$(echo "$query" | jq -s -R -r @uri)
    local endpoint="/search/users?q=$encoded_query&sort=$sort&order=$order&per_page=$per_page&page=$page"
    local response=$(github_api_request "GET" "$endpoint")
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        error "Error al buscar usuarios."
        return 1
    fi
    
    local total_count=$(echo "$response" | jq '.total_count')
    
    # Mostrar resultados en formato tabla
    echo -e "\n${CYAN}${BOLD}Resultados de búsqueda para \"$query\" (Total: $total_count)${NC}"
    echo -e "${CYAN}┌──────────────────────────────────┬─────────────────┬──────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Usuario                          ${NC}${CYAN}│ ${BOLD}Tipo            ${NC}${CYAN}│ ${BOLD}Perfil                               ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├──────────────────────────────────┼─────────────────┼──────────────────────────────────────┤${NC}"
    
    echo "$response" | jq -r '.items[] | [.login, .type, .html_url] | @tsv' | while IFS=$'\t' read -r login type html_url; do
        # Formatear tipo de usuario
        if [ "$type" = "User" ]; then
            type="${GREEN}Usuario${NC}"
        else
            type="${BLUE}Organización${NC}"
        fi
        
        printf "│ %-32s │ %-15s │ %-38s │\n" "$login" "$type" "$html_url"
    done
    
    echo -e "${CYAN}└──────────────────────────────────┴─────────────────┴──────────────────────────────────────┘${NC}"
    
    # Si hay más resultados, mostrar paginación
    if [ "$total_count" -gt "$per_page" ]; then
        local total_pages=$(( ($total_count + $per_page - 1) / $per_page ))
        echo -e "\nPágina $page de $total_pages"
        
        if [ "$page" -lt "$total_pages" ]; then
            echo -e "Para ver más resultados: ${YELLOW}gitmaster search user \"$query\" $sort $order $per_page $((page + 1))${NC}"
        fi
    fi
}

# Obtener información detallada de un usuario
get_user_details() {
    if ! check_github_token; then
        return 1
    fi
    
    local username="$1"
    
    if [ -z "$username" ]; then
        error "Debe proporcionar un nombre de usuario."
        return 1
    fi
    
    info "Obteniendo información detallada del usuario: $username"
    
    local user_data=$(github_api_request "GET" "/users/$username")
    
    if [ $? -ne 0 ] || [ -z "$user_data" ] || [[ "$user_data" == *"Not Found"* ]]; then
        error "Usuario no encontrado o error al obtener información."
        return 1
    fi
    
    # Extraer información
    local login=$(echo "$user_data" | jq -r '.login')
    local name=$(echo "$user_data" | jq -r '.name // "N/A"')
    local company=$(echo "$user_data" | jq -r '.company // "N/A"')
    local location=$(echo "$user_data" | jq -r '.location // "N/A"')
    local email=$(echo "$user_data" | jq -r '.email // "N/A"')
    local bio=$(echo "$user_data" | jq -r '.bio // "N/A"')
    local public_repos=$(echo "$user_data" | jq -r '.public_repos')
    local followers=$(echo "$user_data" | jq -r '.followers')
    local following=$(echo "$user_data" | jq -r '.following')
    local created_at=$(date -d "$(echo "$user_data" | jq -r '.created_at')" '+%Y-%m-%d')
    local updated_at=$(date -d "$(echo "$user_data" | jq -r '.updated_at')" '+%Y-%m-%d')
    local type=$(echo "$user_data" | jq -r '.type')
    local html_url=$(echo "$user_data" | jq -r '.html_url')
    
    # Mostrar información
    echo -e "\n${CYAN}${BOLD}Información de $login${NC}\n"
    
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Perfil de GitHub${NC}                                                         ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC} Nombre:      ${GREEN}$name${NC}"
    echo -e "${CYAN}│${NC} Empresa:     ${GREEN}$company${NC}"
    echo -e "${CYAN}│${NC} Ubicación:   ${GREEN}$location${NC}"
    echo -e "${CYAN}│${NC} Email:       ${GREEN}$email${NC}"
    echo -e "${CYAN}│${NC} Tipo:        ${GREEN}$type${NC}"
    echo -e "${CYAN}│${NC} Creado:      ${GREEN}$created_at${NC}"
    echo -e "${CYAN}│${NC} Actualizado: ${GREEN}$updated_at${NC}"
    echo -e "${CYAN}│${NC} URL:         ${GREEN}$html_url${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│ ${BOLD}Estadísticas${NC}                                                             ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC} Repositorios públicos: ${YELLOW}$public_repos${NC}"
    echo -e "${CYAN}│${NC} Seguidores:            ${YELLOW}$followers${NC}"
    echo -e "${CYAN}│${NC} Siguiendo:             ${YELLOW}$following${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│ ${BOLD}Bio${NC}                                                                      ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC} $bio"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────────────┘${NC}"
    
    # Preguntar si desea obtener los repositorios del usuario
    read -p "¿Desea ver los repositorios de este usuario? (s/N): " show_repos
    if [[ "$show_repos" =~ ^[Ss]$ ]]; then
        list_user_repos "$username"
    fi
}

# Listar repositorios de un usuario específico
list_user_repos() {
    if ! check_github_token; then
        return 1
    fi
    
    local username="$1"
    local sort="${2:-updated}" # created, updated, pushed, full_name
    local direction="${3:-desc}" # asc, desc
    local per_page="${4:-10}"
    local page="${5:-1}"
    
    if [ -z "$username" ]; then
        error "Debe proporcionar un nombre de usuario."
        return 1
    fi
    
    info "Obteniendo repositorios para el usuario $username..."
    
    local endpoint="/users/$username/repos?sort=$sort&direction=$direction&per_page=$per_page&page=$page"
    local repos=$(github_api_request "GET" "$endpoint")
    
    if [ $? -ne 0 ] || [ -z "$repos" ] || [[ "$repos" == *"Not Found"* ]]; then
        error "Usuario no encontrado o error al obtener repositorios."
        return 1
    fi
    
    # Verificar si hay repositorios
    local repos_count=$(echo "$repos" | jq length)
    if [ "$repos_count" -eq 0 ]; then
        info "El usuario $username no tiene repositorios públicos."
        return 0
    fi
    
    # Mostrar repositorios en formato tabla
    echo -e "\n${CYAN}${BOLD}Repositorios de $username${NC}"
    echo -e "${CYAN}┌──────────────────────────────────┬───────────┬────────────────────┬─────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Nombre                          ${NC}${CYAN}│ ${BOLD}Lenguaje  ${NC}${CYAN}│ ${BOLD}Última actualización${NC}${CYAN} │ ${BOLD}Estrellas    ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├──────────────────────────────────┼───────────┼────────────────────┼─────────────┤${NC}"
    
    echo "$repos" | jq -r '.[] | [.name, .language, .updated_at, .stargazers_count] | @tsv' | while IFS=$'\t' read -r name language updated stars; do
        # Formatear fecha
        updated=$(date -d "$updated" '+%Y-%m-%d %H:%M:%S')
        
        # Formatear lenguaje
        if [ "$language" = "null" ] || [ -z "$language" ]; then
            language="N/A"
        fi
        
        # Formatear estrellas
        if [ "$stars" -gt 0 ]; then
            stars="${YELLOW}$stars ⭐${NC}"
        else
            stars="0"
        fi
        
        printf "│ %-32s │ %-9s │ %-18s │ %-11s │\n" "$name" "$language" "$updated" "$stars"
    done
    
    echo -e "${CYAN}└──────────────────────────────────┴───────────┴────────────────────┴─────────────┘${NC}"
    
    # Si hay más resultados, mostrar paginación
    if [ "$repos_count" -eq "$per_page" ]; then
        echo -e "\nMostrando página $page"
        echo -e "Para ver más resultados: ${YELLOW}gitmaster user repos $username $sort $direction $per_page $((page + 1))${NC}"
    fi
}

# Ver los proyectos más populares y tendencias en GitHub
trending_repos() {
    if ! check_github_token; then
        return 1
    fi
    
    local language="${1:-}" # Lenguaje específico o vacío para todos
    local since="${2:-daily}" # daily, weekly, monthly
    local limit="${3:-10}" # Número de resultados a mostrar
    
    info "Obteniendo repositorios en tendencia${language:+ para $language}..."
    
    # Construir consulta para búsqueda
    local query="stars:>100"
    
    # Añadir filtro de lenguaje si se especifica
    if [ -n "$language" ]; then
        query+=" language:$language"
    fi
    
    # Añadir filtro de fecha según el periodo
    case "$since" in
        daily)
            query+=" created:>$(date -d "yesterday" '+%Y-%m-%d')"
            ;;
        weekly)
            query+=" created:>$(date -d "7 days ago" '+%Y-%m-%d')"
            ;;
        monthly)
            query+=" created:>$(date -d "30 days ago" '+%Y-%m-%d')"
            ;;
        *)
            query+=" created:>$(date -d "yesterday" '+%Y-%m-%d')"
            ;;
    esac
    
    local encoded_query=$(echo "$query" | jq -s -R -r @uri)
    local endpoint="/search/repositories?q=$encoded_query&sort=stars&order=desc&per_page=$limit"
    local response=$(github_api_request "GET" "$endpoint")
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        error "Error al obtener repositorios en tendencia."
        return 1
    fi
    
    local total_count=$(echo "$response" | jq '.total_count')
    
    # Mostrar resultados en formato tabla
    echo -e "\n${CYAN}${BOLD}Repositorios en tendencia ($since)${NC} ${language:+- Lenguaje: $language}"
    echo -e "${CYAN}┌──────────────────────────────────┬──────────────────────┬─────────┬─────────┬───────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Repositorio                      ${NC}${CYAN}│ ${BOLD}Propietario         ${NC}${CYAN}│ ${BOLD}Estrellas${NC}${CYAN} │ ${BOLD}Forks   ${NC}${CYAN}│ ${BOLD}Lenguaje      ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├──────────────────────────────────┼──────────────────────┼─────────┼─────────┼───────────────┤${NC}"
    
    echo "$response" | jq -r '.items[] | [.full_name, .owner.login, .stargazers_count, .forks_count, .language] | @tsv' | while IFS=$'\t' read -r full_name owner stars forks lang; do
        # Separar nombre del repositorio del propietario
        local repo_name="${full_name#*/}"
        
        # Formatear estrellas y forks
        stars="${stars} ⭐"
        forks="${forks} 🍴"
        
        # Formatear lenguaje
        if [ "$lang" = "null" ] || [ -z "$lang" ]; then
            lang="N/A"
        fi
        
        printf "│ %-32s │ %-20s │ %-9s │ %-9s │ %-13s │\n" "$repo_name" "$owner" "$stars" "$forks" "$lang"
    done
    
    echo -e "${CYAN}└──────────────────────────────────┴──────────────────────┴─────────┴─────────┴───────────────┘${NC}"
}

# ===================================================================================
# Funciones de gestión de ramas y flujo de trabajo
# ===================================================================================

# Crear una nueva rama y cambiar a ella
create_branch() {
    local branch_name="$1"
    local base_branch="$2"
    
    if [ -z "$branch_name" ]; then
        error "Debe proporcionar un nombre para la rama."
        return 1
    fi
    
    if [ -z "$base_branch" ]; then
        base_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
        
        if [ -z "$base_branch" ]; then
            error "No se pudo determinar la rama actual."
            return 1
        fi
        
        info "Usando rama actual como base: $base_branch"
    fi
    
    info "Cambiando a la rama base: $base_branch"
    if ! git checkout "$base_branch"; then
        error "No se pudo cambiar a la rama base: $base_branch"
        return 1
    fi
    
    info "Actualizando desde el repositorio remoto..."
    if ! git pull --rebase origin "$base_branch"; then
        warning "No se pudo actualizar desde el repositorio remoto. Continuando de todos modos..."
    fi
    
    info "Creando nueva rama: $branch_name desde $base_branch"
    if git checkout -b "$branch_name"; then
        success "Rama creada correctamente: $branch_name"
        
        # Preguntar si desea subir la rama al remoto
        read -p "¿Desea subir esta rama al repositorio remoto? (s/N): " push_branch
        if [[ "$push_branch" =~ ^[Ss]$ ]]; then
            info "Subiendo rama al repositorio remoto..."
            if git push -u origin "$branch_name"; then
                success "Rama subida correctamente al repositorio remoto."
            else
                error "Error al subir la rama al repositorio remoto."
            fi
        fi
    else
        error "Error al crear la rama: $branch_name"
        return 1
    fi
}

# Iniciar una nueva feature
start_feature() {
    local feature_name="$1"
    local base_branch="$2"
    
    if [ -z "$feature_name" ]; then
        error "Debe proporcionar un nombre para la feature."
        return 1
    fi
    
    # Cargar prefijo de feature desde la configuración
    local feature_prefix=$(jq -r '.git_flow.feature_prefix' "$GITMASTER_CONFIG_FILE")
    
    if [ -z "$base_branch" ]; then
        # Cargar rama develop desde la configuración
        base_branch=$(jq -r '.git_flow.develop_branch' "$GITMASTER_CONFIG_FILE")
    fi
    
    local branch_name="${feature_prefix}${feature_name}"
    
    info "Iniciando nueva feature: $feature_name"
    create_branch "$branch_name" "$base_branch"
}

# Completar una feature
complete_feature() {
    local feature_name="$1"
    local target_branch="$2"
    
    # Cargar prefijo de feature desde la configuración
    local feature_prefix=$(jq -r '.git_flow.feature_prefix' "$GITMASTER_CONFIG_FILE")
    
    # Si se proporciona el nombre completo de la rama, extraer solo el nombre de la feature
    if [[ "$feature_name" == "$feature_prefix"* ]]; then
        feature_name="${feature_name#$feature_prefix}"
    fi
    
    local branch_name="${feature_prefix}${feature_name}"
    
    # Verificar si la rama existe
    if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
        error "La rama de feature '$branch_name' no existe."
        return 1
    fi
    
    if [ -z "$target_branch" ]; then
        # Cargar rama develop desde la configuración
        target_branch=$(jq -r '.git_flow.develop_branch' "$GITMASTER_CONFIG_FILE")
    fi
    
    info "Completando feature: $feature_name"
    
    # Asegurarse de que estamos en la rama de la feature
    info "Cambiando a la rama de feature: $branch_name"
    if ! git checkout "$branch_name"; then
        error "No se pudo cambiar a la rama de feature."
        return 1
    fi
    
    # Comprobar si hay cambios sin commit
    if git status --porcelain | grep -q .; then
        error "Hay cambios sin commit en la rama. Por favor, haz commit o stash de los cambios antes de completar la feature."
        return 1
    fi
    
    # Actualizar rama target
    info "Actualizando rama $target_branch desde el repositorio remoto..."
    git checkout "$target_branch"
    if ! git pull --rebase origin "$target_branch"; then
        warning "No se pudo actualizar la rama $target_branch desde el repositorio remoto. Continuando de todos modos..."
    fi
    
    # Volver a la rama de feature y rebasar con la rama target
    info "Rebasando feature con $target_branch..."
    git checkout "$branch_name"
    if ! git rebase "$target_branch"; then
        error "Error al rebasar la feature con $target_branch. Por favor, resuelve los conflictos manualmente."
        return 1
    fi
    
    # Hacer merge de la feature en la rama target
    info "Haciendo merge de la feature en $target_branch..."
    git checkout "$target_branch"
    if ! git merge --no-ff "$branch_name" -m "Merge feature '$feature_name'"; then
        error "Error al hacer merge de la feature en $target_branch. Por favor, resuelve los conflictos manualmente."
        return 1
    fi
    
    # Subir cambios a la rama target
    info "Subiendo cambios a $target_branch..."
    if ! git push origin "$target_branch"; then
        error "Error al subir cambios a $target_branch."
        return 1
    fi
    
    # Preguntar si desea eliminar la rama de feature
    read -p "¿Desea eliminar la rama de feature? (s/N): " delete_branch
    if [[ "$delete_branch" =~ ^[Ss]$ ]]; then
        info "Eliminando rama de feature..."
        git branch -d "$branch_name"
        
        # Verificar si la rama está en el remoto
        if git ls-remote --heads origin "$branch_name" | grep -q "$branch_name"; then
            read -p "¿Desea eliminar la rama remota también? (s/N): " delete_remote
            if [[ "$delete_remote" =~ ^[Ss]$ ]]; then
                git push origin --delete "$branch_name"
            fi
        fi
    fi
    
    success "Feature completada: $feature_name"
}

# Iniciar una nueva release
start_release() {
    local version="$1"
    local base_branch="$2"
    
    if [ -z "$version" ]; then
        error "Debe proporcionar un número de versión para la release."
        return 1
    fi
    
    # Cargar prefijo de release desde la configuración
    local release_prefix=$(jq -r '.git_flow.release_prefix' "$GITMASTER_CONFIG_FILE")
    
    if [ -z "$base_branch" ]; then
        # Cargar rama develop desde la configuración
        base_branch=$(jq -r '.git_flow.develop_branch' "$GITMASTER_CONFIG_FILE")
    fi
    
    local branch_name="${release_prefix}${version}"
    
    info "Iniciando nueva release: $version"
    create_branch "$branch_name" "$base_branch"
    
    # Preguntar si desea actualizar la versión en archivos
    read -p "¿Desea actualizar el número de versión en los archivos del proyecto? (s/N): " update_version
    if [[ "$update_version" =~ ^[Ss]$ ]]; then
        read -p "Por favor, ingrese los archivos a actualizar (separados por espacios): " files_to_update
        
        IFS=' ' read -ra files_array <<< "$files_to_update"
        for file in "${files_array[@]}"; do
            if [ -f "$file" ]; then
                info "Actualizando versión en $file..."
                # Intentar actualizar la versión en diferentes formatos
                sed -i "s/version[[:space:]]*=[[:space:]]*\"[0-9.]*\"/version = \"$version\"/g" "$file"
                sed -i "s/VERSION[[:space:]]*=[[:space:]]*\"[0-9.]*\"/VERSION = \"$version\"/g" "$file"
                sed -i "s/\"version\":[[:space:]]*\"[0-9.]*\"/\"version\": \"$version\"/g" "$file"
            else
                warning "El archivo $file no existe."
            fi
        done
        
        git add .
        git commit -m "Actualizar versión a $version"
    fi
    
    success "Release iniciada: $version"
}

# Completar una release
complete_release() {
    local version="$1"
    
    # Cargar prefijos y ramas desde la configuración
    local release_prefix=$(jq -r '.git_flow.release_prefix' "$GITMASTER_CONFIG_FILE")
    local main_branch=$(jq -r '.git_flow.main_branch' "$GITMASTER_CONFIG_FILE")
    local develop_branch=$(jq -r '.git_flow.develop_branch' "$GITMASTER_CONFIG_FILE")
    
    # Si se proporciona el nombre completo de la rama, extraer solo la versión
    if [[ "$version" == "$release_prefix"* ]]; then
        version="${version#$release_prefix}"
    fi
    
    local branch_name="${release_prefix}${version}"
    
    # Verificar si la rama existe
    if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
        error "La rama de release '$branch_name' no existe."
        return 1
    fi
    
    info "Completando release: $version"
    
    # Asegurarse de que estamos en la rama de la release
    info "Cambiando a la rama de release: $branch_name"
    if ! git checkout "$branch_name"; then
        error "No se pudo cambiar a la rama de release."
        return 1
    fi
    
    # Comprobar si hay cambios sin commit
    if git status --porcelain | grep -q .; then
        error "Hay cambios sin commit en la rama. Por favor, haz commit o stash de los cambios antes de completar la release."
        return 1
    fi
    
    # Hacer merge en la rama principal
    info "Haciendo merge de la release en $main_branch..."
    git checkout "$main_branch"
    git pull --rebase origin "$main_branch"
    
    if ! git merge --no-ff "$branch_name" -m "Merge release '$version'"; then
        error "Error al hacer merge de la release en $main_branch. Por favor, resuelve los conflictos manualmente."
        return 1
    fi
    
    # Crear tag para la versión
    info "Creando tag para la versión $version..."
    git tag -a "v$version" -m "Release version $version"
    
    # Hacer merge en la rama de desarrollo
    info "Haciendo merge de la release en $develop_branch..."
    git checkout "$develop_branch"
    git pull --rebase origin "$develop_branch"
    
    if ! git merge --no-ff "$branch_name" -m "Merge release '$version' back into $develop_branch"; then
        error "Error al hacer merge de la release en $develop_branch. Por favor, resuelve los conflictos manualmente."
        return 1
    fi
    
    # Subir cambios
    info "Subiendo cambios a $main_branch..."
    git checkout "$main_branch"
    git push origin "$main_branch"
    
    info "Subiendo cambios a $develop_branch..."
    git checkout "$develop_branch"
    git push origin "$develop_branch"
    
    info "Subiendo tags..."
    git push origin --tags
    
    # Preguntar si desea crear una release en GitHub
    read -p "¿Desea crear una release en GitHub? (s/N): " create_github_release
    if [[ "$create_github_release" =~ ^[Ss]$ ]]; then
        create_github_release "$version"
    fi
    
    # Preguntar si desea eliminar la rama de release
    read -p "¿Desea eliminar la rama de release? (s/N): " delete_branch
    if [[ "$delete_branch" =~ ^[Ss]$ ]]; then
        info "Eliminando rama de release..."
        git branch -d "$branch_name"
        
        # Verificar si la rama está en el remoto
        if git ls-remote --heads origin "$branch_name" | grep -q "$branch_name"; then
            read -p "¿Desea eliminar la rama remota también? (s/N): " delete_remote
            if [[ "$delete_remote" =~ ^[Ss]$ ]]; then
                git push origin --delete "$branch_name"
            fi
        fi
    fi
    
    success "Release completada: $version"
}

# Crear una release en GitHub
create_github_release() {
    if ! check_github_token; then
        return 1
    fi
    
    local version="$1"
    local tag_name="${2:-v$version}"
    local release_name="${3:-Release $version}"
    local body="${4:-}"
    local draft="${5:-false}"
    local prerelease="${6:-false}"

    # Obtener el nombre del repositorio actual
    local remote_url=$(git config --get remote.origin.url)
    local repo_name=$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+/[^/]+)(.git)?$|\1|')
    
    if [ -z "$repo_name" ]; then
        error "No se pudo determinar el nombre del repositorio."
        return 1
    fi
    
    info "Creando release $version para el repositorio $repo_name..."
    
    # Generar cuerpo de la release automáticamente si no se proporciona
    if [ -z "$body" ]; then
        local previous_tag=$(git describe --abbrev=0 --tags "v$version^" 2>/dev/null)
        
        if [ -n "$previous_tag" ]; then
            info "Generando notas de la release automáticamente desde $previous_tag hasta $tag_name..."
            body=$(git log --pretty=format:"* %s (%h)" "$previous_tag..$tag_name")
        else
            info "No se encontró tag anterior, usando todos los commits hasta ahora..."
            body=$(git log --pretty=format:"* %s (%h)" -n 20)
        fi
    fi
    
    # Crear la release en GitHub
    local data="{
        \"tag_name\": \"$tag_name\",
        \"target_commitish\": \"$(git rev-parse HEAD)\",
        \"name\": \"$release_name\",
        \"body\": \"$body\",
        \"draft\": $draft,
        \"prerelease\": $prerelease
    }"
    
    local response=$(github_api_request "POST" "/repos/$repo_name/releases" "$data")
    local html_url=$(echo "$response" | jq -r '.html_url')
    
    if [ "$html_url" = "null" ] || [ -z "$html_url" ]; then
        error "Error al crear la release. Respuesta:"
        echo "$response" | jq '.'
        return 1
    fi
    
    success "Release creada: $html_url"
}

# ===================================================================================
# Funciones para issues y pull requests
# ===================================================================================

# Listar issues de un repositorio
list_issues() {
    if ! check_github_token; then
        return 1
    fi
    
    local repo="${1:-}"
    local state="${2:-open}" # open, closed, all
    local sort="${3:-created}" # created, updated, comments
    local direction="${4:-desc}" # asc, desc
    local per_page="${5:-10}"
    local page="${6:-1}"
    
    # Si no se proporciona un repositorio, usar el repositorio actual
    if [ -z "$repo" ]; then
        local remote_url=$(git config --get remote.origin.url)
        repo=$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+/[^/]+)(.git)?$|\1|')
        
        if [ -z "$repo" ]; then
            error "No se pudo determinar el repositorio. Por favor, especifique uno."
            return 1
        fi
        
        info "Usando repositorio actual: $repo"
    fi
    
    info "Obteniendo issues para el repositorio $repo (estado: $state)..."
    
    local endpoint="/repos/$repo/issues?state=$state&sort=$sort&direction=$direction&per_page=$per_page&page=$page"
    local response=$(github_api_request "GET" "$endpoint")
    
    if [ $? -ne 0 ] || [ -z "$response" ] || [[ "$response" == *"Not Found"* ]]; then
        error "Repositorio no encontrado o error al obtener issues."
        return 1
    fi
    
    # Verificar si hay issues
    local issues_count=$(echo "$response" | jq length)
    if [ "$issues_count" -eq 0 ]; then
        info "No hay issues con el estado '$state' en el repositorio $repo."
        return 0
    fi
    
    # Mostrar issues en formato tabla
    echo -e "\n${CYAN}${BOLD}Issues de $repo (estado: $state)${NC}"
    echo -e "${CYAN}┌────┬──────────────────────────────────┬────────────┬─────────────────┬────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}#ID ${NC}${CYAN}│ ${BOLD}Título                           ${NC}${CYAN}│ ${BOLD}Autor      ${NC}${CYAN}│ ${BOLD}Fecha           ${NC}${CYAN}│ ${BOLD}Labels ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├────┼──────────────────────────────────┼────────────┼─────────────────┼────────┤${NC}"
    
    echo "$response" | jq -r '.[] | [.number, .title, .user.login, .created_at, (.labels | map(.name) | join(", "))] | @tsv' | while IFS=$'\t' read -r number title author created labels; do
        # Truncar título si es demasiado largo
        if [ ${#title} -gt 32 ]; then
            title="${title:0:29}..."
        fi
        
        # Formatear fecha
        created=$(date -d "$created" '+%Y-%m-%d %H:%M')
        
        # Truncar autor si es demasiado largo
        if [ ${#author} -gt 10 ]; then
            author="${author:0:7}..."
        fi
        
        # Truncar labels si son demasiadas
        if [ ${#labels} -gt 8 ]; then
            labels="${labels:0:5}..."
        fi
        
        printf "│ %-2s │ %-32s │ %-10s │ %-17s │ %-6s │\n" "$number" "$title" "$author" "$created" "$labels"
    done
    
    echo -e "${CYAN}└────┴──────────────────────────────────┴────────────┴─────────────────┴────────┘${NC}"
    
    # Si hay más resultados, mostrar paginación
    if [ "$issues_count" -eq "$per_page" ]; then
        echo -e "\nMostrando página $page"
        echo -e "Para ver más resultados: ${YELLOW}gitmaster issues $repo $state $sort $direction $per_page $((page + 1))${NC}"
    fi
}

# Crear un nuevo issue
create_issue() {
    if ! check_github_token; then
        return 1
    fi
    
    local repo="${1:-}"
    local title="$2"
    local body="$3"
    local labels="$4"
    local assignees="$5"
    
    # Si no se proporciona un repositorio, usar el repositorio actual
    if [ -z "$repo" ]; then
        local remote_url=$(git config --get remote.origin.url)
        repo=$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+/[^/]+)(.git)?$|\1|')
        
        if [ -z "$repo" ]; then
            error "No se pudo determinar el repositorio. Por favor, especifique uno."
            return 1
        fi
        
        info "Usando repositorio actual: $repo"
    fi
    
    # Solicitar título si no se proporciona
    if [ -z "$title" ]; then
        read -p "Título del issue: " title
        
        if [ -z "$title" ]; then
            error "El título es obligatorio."
            return 1
        fi
    fi
    
    # Solicitar cuerpo si no se proporciona
    if [ -z "$body" ]; then
        info "Ingrese el cuerpo del issue (presione Ctrl+D en una nueva línea para finalizar):"
        body=$(cat)
    fi
    
    # Crear datos del issue
    local data="{\"title\": \"$title\", \"body\": \"$body\"}"
    
    # Añadir labels si se proporcionan
    if [ -n "$labels" ]; then
        # Convertir lista separada por comas a array JSON
        local labels_array="[$(echo "$labels" | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')]"
        data=$(echo "$data" | jq --argjson labels "$labels_array" '. + {labels: $labels}')
    fi
    
    # Añadir assignees si se proporcionan
    if [ -n "$assignees" ]; then
        # Convertir lista separada por comas a array JSON
        local assignees_array="[$(echo "$assignees" | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')]"
        data=$(echo "$data" | jq --argjson assignees "$assignees_array" '. + {assignees: $assignees}')
    fi
    
    info "Creando issue en el repositorio $repo..."
    
    local response=$(github_api_request "POST" "/repos/$repo/issues" "$data")
    local issue_url=$(echo "$response" | jq -r '.html_url')
    local issue_number=$(echo "$response" | jq -r '.number')
    
    if [ "$issue_url" = "null" ] || [ -z "$issue_url" ]; then
        error "Error al crear el issue. Respuesta:"
        echo "$response" | jq '.'
        return 1
    fi
    
    success "Issue #$issue_number creado: $issue_url"
}

# Cerrar un issue
close_issue() {
    if ! check_github_token; then
        return 1
    fi
    
    local repo="${1:-}"
    local issue_number="$2"
    
    # Si no se proporciona un repositorio, usar el repositorio actual
    if [ -z "$repo" ]; then
        local remote_url=$(git config --get remote.origin.url)
        repo=$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+/[^/]+)(.git)?$|\1|')
        
        if [ -z "$repo" ]; then
            error "No se pudo determinar el repositorio. Por favor, especifique uno."
            return 1
        fi
        
        info "Usando repositorio actual: $repo"
    fi
    
    # Solicitar número de issue si no se proporciona
    if [ -z "$issue_number" ]; then
        read -p "Número de issue a cerrar: " issue_number
        
        if [ -z "$issue_number" ]; then
            error "El número de issue es obligatorio."
            return 1
        fi
    fi
    
    info "Cerrando issue #$issue_number en el repositorio $repo..."
    
    local data="{\"state\": \"closed\"}"
    local response=$(github_api_request "PATCH" "/repos/$repo/issues/$issue_number" "$data")
    local issue_url=$(echo "$response" | jq -r '.html_url')
    
    if [ "$issue_url" = "null" ] || [ -z "$issue_url" ]; then
        error "Error al cerrar el issue. Respuesta:"
        echo "$response" | jq '.'
        return 1
    fi
    
    success "Issue #$issue_number cerrado: $issue_url"
}

# Listar pull requests de un repositorio
list_pulls() {
    if ! check_github_token; then
        return 1
    fi
    
    local repo="${1:-}"
    local state="${2:-open}" # open, closed, all
    local sort="${3:-created}" # created, updated, popularity, long-running
    local direction="${4:-desc}" # asc, desc
    local per_page="${5:-10}"
    local page="${6:-1}"
    
    # Si no se proporciona un repositorio, usar el repositorio actual
    if [ -z "$repo" ]; then
        local remote_url=$(git config --get remote.origin.url)
        repo=$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+/[^/]+)(.git)?$|\1|')
        
        if [ -z "$repo" ]; then
            error "No se pudo determinar el repositorio. Por favor, especifique uno."
            return 1
        fi
        
        info "Usando repositorio actual: $repo"
    fi
    
    info "Obteniendo pull requests para el repositorio $repo (estado: $state)..."
    
    local endpoint="/repos/$repo/pulls?state=$state&sort=$sort&direction=$direction&per_page=$per_page&page=$page"
    local response=$(github_api_request "GET" "$endpoint")
    
    if [ $? -ne 0 ] || [ -z "$response" ] || [[ "$response" == *"Not Found"* ]]; then
        error "Repositorio no encontrado o error al obtener pull requests."
        return 1
    fi
    
    # Verificar si hay pull requests
    local pulls_count=$(echo "$response" | jq length)
    if [ "$pulls_count" -eq 0 ]; then
        info "No hay pull requests con el estado '$state' en el repositorio $repo."
        return 0
    fi
    
    # Mostrar pull requests en formato tabla
    echo -e "\n${CYAN}${BOLD}Pull Requests de $repo (estado: $state)${NC}"
    echo -e "${CYAN}┌────┬──────────────────────────────────┬────────────┬────────────┬────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}#ID ${NC}${CYAN}│ ${BOLD}Título                           ${NC}${CYAN}│ ${BOLD}Autor      ${NC}${CYAN}│ ${BOLD}Rama origen${NC}${CYAN} │ ${BOLD}Rama destino${NC}${CYAN} │${NC}"
    echo -e "${CYAN}├────┼──────────────────────────────────┼────────────┼────────────┼────────────┤${NC}"
    
    echo "$response" | jq -r '.[] | [.number, .title, .user.login, .head.ref, .base.ref] | @tsv' | while IFS=$'\t' read -r number title author head_ref base_ref; do
        # Truncar título si es demasiado largo
        if [ ${#title} -gt 32 ]; then
            title="${title:0:29}..."
        fi
        
        # Truncar autor si es demasiado largo
        if [ ${#author} -gt 10 ]; then
            author="${author:0:7}..."
        fi
        
        # Truncar nombres de ramas si son demasiado largos
        if [ ${#head_ref} -gt 10 ]; then
            head_ref="${head_ref:0:7}..."
        fi
        
        if [ ${#base_ref} -gt 10 ]; then
            base_ref="${base_ref:0:7}..."
        fi
        
        printf "│ %-2s │ %-32s │ %-10s │ %-10s │ %-10s │\n" "$number" "$title" "$author" "$head_ref" "$base_ref"
    done
    
    echo -e "${CYAN}└────┴──────────────────────────────────┴────────────┴────────────┴────────────┘${NC}"
    
    # Si hay más resultados, mostrar paginación
    if [ "$pulls_count" -eq "$per_page" ]; then
        echo -e "\nMostrando página $page"
        echo -e "Para ver más resultados: ${YELLOW}gitmaster pulls $repo $state $sort $direction $per_page $((page + 1))${NC}"
    fi
}

# Crear un pull request
create_pull_request() {
    if ! check_github_token; then
        return 1
    fi
    
    local repo="${1:-}"
    local head="$2"
    local base="$3"
    local title="$4"
    local body="$5"
    
    # Si no se proporciona un repositorio, usar el repositorio actual
    if [ -z "$repo" ]; then
        local remote_url=$(git config --get remote.origin.url)
        repo=$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+/[^/]+)(.git)?$|\1|')
        
        if [ -z "$repo" ]; then
            error "No se pudo determinar el repositorio. Por favor, especifique uno."
            return 1
        fi
        
        info "Usando repositorio actual: $repo"
    fi
    
    # Si no se proporciona rama de origen (head), usar la rama actual
    if [ -z "$head" ]; then
        head=$(git symbolic-ref --short HEAD 2>/dev/null)
        
        if [ -z "$head" ]; then
            error "No se pudo determinar la rama actual."
            return 1
        fi
        
        info "Usando rama actual como origen: $head"
    fi
    
    # Si no se proporciona rama de destino (base), usar la rama principal configurada
    if [ -z "$base" ]; then
        base=$(jq -r '.git_flow.main_branch' "$GITMASTER_CONFIG_FILE")
        info "Usando rama principal como destino: $base"
    fi
    
    # Solicitar título si no se proporciona
    if [ -z "$title" ]; then
        # Generar título automáticamente a partir del último commit si no se proporciona
        title=$(git log -1 --pretty=%B | head -n 1)
        
        info "Usando título del último commit: $title"
        read -p "¿Desea modificar el título? (s/N): " modify_title
        
        if [[ "$modify_title" =~ ^[Ss]$ ]]; then
            read -p "Nuevo título: " new_title
            if [ -n "$new_title" ]; then
                title="$new_title"
            fi
        fi
    fi
    
    # Solicitar cuerpo si no se proporciona
    if [ -z "$body" ]; then
        # Generar cuerpo automáticamente a partir de los commits
        info "Generando descripción del PR automáticamente..."
        
        # Encontrar el punto de bifurcación entre las ramas
        local merge_base=$(git merge-base "$head" "$base")
        
        # Obtener los commits entre el punto de bifurcación y HEAD
        body="## Cambios incluidos\n\n"
        body+=$(git log --pretty=format:"* %s (%h)" "$merge_base..$head")
        
        info "Cuerpo generado. ¿Desea modificarlo?"
        echo -e "$body"
        read -p "¿Desea modificar la descripción? (s/N): " modify_body
        
        if [[ "$modify_body" =~ ^[Ss]$ ]]; then
            info "Ingrese la nueva descripción (presione Ctrl+D en una nueva línea para finalizar):"
            body=$(cat)
        fi
    fi
    
    info "Creando pull request de '$head' a '$base' en el repositorio $repo..."
    
    local data="{
        \"title\": \"$title\",
        \"body\": \"$body\",
        \"head\": \"$head\",
        \"base\": \"$base\"
    }"
    
    local response=$(github_api_request "POST" "/repos/$repo/pulls" "$data")
    local pr_url=$(echo "$response" | jq -r '.html_url')
    local pr_number=$(echo "$response" | jq -r '.number')
    
    if [ "$pr_url" = "null" ] || [ -z "$pr_url" ]; then
        error "Error al crear el pull request. Respuesta:"
        echo "$response" | jq '.'
        return 1
    fi
    
    success "Pull request #$pr_number creado: $pr_url"
}

# ===================================================================================
# Funciones de análisis de código y estadísticas
# ===================================================================================

# Analizar contribuciones al repositorio
analyze_contributions() {
    local repo_path="${1:-.}"
    local since="$2"
    local until="$3"
    local authors_count="${4:-10}"
    
    if [ ! -d "$repo_path/.git" ]; then
        error "El directorio '$repo_path' no es un repositorio Git."
        return 1
    fi
    
    # Preparar parámetros de fecha
    local date_params=""
    if [ -n "$since" ]; then
        date_params+=" --since=\"$since\""
    fi
    
    if [ -n "$until" ]; then
        date_params+=" --until=\"$until\""
    fi
    
    info "Analizando contribuciones al repositorio..."
    
    # Cambiar al directorio del repositorio
    cd "$repo_path" || return 1
    
    # Mostrar estadísticas generales
    echo -e "\n${CYAN}${BOLD}Estadísticas generales del repositorio${NC}"
    echo -e "${CYAN}┌─────────────────────────────────┬───────────────────────────┐${NC}"
    
    # Total de commits
    local total_commits=$(eval git rev-list --count HEAD $date_params)
    echo -e "${CYAN}│${NC} Total de commits               ${CYAN}│${NC} ${GREEN}$total_commits${NC}"
    
    # Total de archivos
    local total_files=$(git ls-files | wc -l)
    echo -e "${CYAN}│${NC} Total de archivos              ${CYAN}│${NC} ${GREEN}$total_files${NC}"
    
    # Total de líneas
    local total_lines=$(git ls-files | xargs wc -l 2>/dev/null | tail -n 1 | awk '{print $1}')
    echo -e "${CYAN}│${NC} Total de líneas de código      ${CYAN}│${NC} ${GREEN}$total_lines${NC}"
    
    # Primer commit
    local first_commit_date=$(git log --reverse --format="%ad" --date=short | head -1)
    echo -e "${CYAN}│${NC} Primer commit                  ${CYAN}│${NC} ${GREEN}$first_commit_date${NC}"
    
    # Último commit
    local last_commit_date=$(git log -1 --format="%ad" --date=short)
    echo -e "${CYAN}│${NC} Último commit                  ${CYAN}│${NC} ${GREEN}$last_commit_date${NC}"
    
    # Total de contribuyentes
    local total_contributors=$(git shortlog -sn --no-merges | wc -l)
    echo -e "${CYAN}│${NC} Total de contribuyentes        ${CYAN}│${NC} ${GREEN}$total_contributors${NC}"
    
    echo -e "${CYAN}└─────────────────────────────────┴───────────────────────────┘${NC}"
    
    # Mostrar principales contribuyentes
    echo -e "\n${CYAN}${BOLD}Principales contribuyentes${NC}"
    echo -e "${CYAN}┌──────┬──────────────────────────────────┬───────────┬─────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Rango ${NC}${CYAN}│ ${BOLD}Autor                            ${NC}${CYAN}│ ${BOLD}Commits   ${NC}${CYAN}│ ${BOLD}Porcentaje  ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├──────┼──────────────────────────────────┼───────────┼─────────────┤${NC}"
    
    # Obtener lista de autores con número de commits
    eval git shortlog -sn --no-merges $date_params | head -n "$authors_count" | awk '{
        rank = NR
        commits = $1
        author = substr($0, index($0, $2))
        printf "│ %-4s │ %-32s │ %-9s │ %-9.1f%%   │\n", rank, author, commits, (commits/'$total_commits')*100
    }'
    
    echo -e "${CYAN}└──────┴──────────────────────────────────┴───────────┴─────────────┘${NC}"
    
    # Mostrar actividad por día de la semana
    echo -e "\n${CYAN}${BOLD}Actividad por día de la semana${NC}"
    echo -e "${CYAN}┌────────────┬───────────┬────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Día         ${NC}${CYAN}│ ${BOLD}Commits   ${NC}${CYAN}│ ${BOLD}Gráfico                                 ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├────────────┼───────────┼────────────────────────────────────────────┤${NC}"
    
    # Obtener commits por día de la semana
    local days=("Lunes" "Martes" "Miércoles" "Jueves" "Viernes" "Sábado" "Domingo")
    local max_commits=0
    
    for i in {1..7}; do
        local count=$(eval git log --no-merges $date_params --format="%ad" --date=format:%u | grep -c "^$i$")
        if [ "$count" -gt "$max_commits" ]; then
            max_commits=$count
        fi
    done
    
    for i in {1..7}; do
        local count=$(eval git log --no-merges $date_params --format="%ad" --date=format:%u | grep -c "^$i$")
        local percent=$((count * 100 / max_commits))
        local bar=""
        
        # Crear barra de progreso
        for ((j=0; j<percent/2; j++)); do
            bar="${bar}█"
        done
        
        printf "${CYAN}│${NC} %-10s ${CYAN}│${NC} %-9s ${CYAN}│${NC} ${GREEN}%-40s${NC} ${CYAN}│${NC}\n" "${days[$i-1]}" "$count" "$bar"
    done
    
    echo -e "${CYAN}└────────────┴───────────┴────────────────────────────────────────────┘${NC}"
    
    # Analizar actividad a lo largo del tiempo
    echo -e "\n${CYAN}${BOLD}Actividad a lo largo del tiempo (últimos 12 meses)${NC}"
    echo -e "${CYAN}┌──────────┬───────────┬────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Mes       ${NC}${CYAN}│ ${BOLD}Commits   ${NC}${CYAN}│ ${BOLD}Gráfico                                 ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├──────────┼───────────┼────────────────────────────────────────────┤${NC}"
    
    # Obtener commits por mes para los últimos 12 meses
    local months=("Ene" "Feb" "Mar" "Abr" "May" "Jun" "Jul" "Ago" "Sep" "Oct" "Nov" "Dic")
    local max_month_commits=0
    local current_month=$(date +%m)
    local current_year=$(date +%Y)
    
    for i in {0..11}; do
        local month=$(( (current_month - i - 1 + 12) % 12 + 1 ))
        local year=$current_year
        if [ "$month" -gt "$current_month" ]; then
            year=$((year - 1))
        fi
        
        local month_name="${months[$month-1]}"
        local count=$(git log --no-merges --after="$year-$month-01" --before="$year-$month-31" --format="%H" | wc -l)
        
        if [ "$count" -gt "$max_month_commits" ]; then
            max_month_commits=$count
        fi
        
        local month_data[$i]="$month_name $year:$count"
    done
    
    # Mostrar gráfico de actividad por mes
    for i in {11..0}; do
        IFS=':' read -r name count <<< "${month_data[$i]}"
        
        if [ "$max_month_commits" -eq 0 ]; then
            local percent=0
        else
            local percent=$((count * 100 / max_month_commits))
        fi
        
        local bar=""
        
        # Crear barra de progreso
        for ((j=0; j<percent/2; j++)); do
            bar="${bar}█"
        done
        
        printf "${CYAN}│${NC} %-10s ${CYAN}│${NC} %-9s ${CYAN}│${NC} ${GREEN}%-40s${NC} ${CYAN}│${NC}\n" "$name" "$count" "$bar"
    done
    
    echo -e "${CYAN}└──────────┴───────────┴────────────────────────────────────────────┘${NC}"
    
    # Mostrar tipos de archivos en el repositorio
    echo -e "\n${CYAN}${BOLD}Distribución de tipos de archivos${NC}"
    echo -e "${CYAN}┌──────────────┬──────────┬────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Extensión    ${NC}${CYAN}│ ${BOLD}Archivos  ${NC}${CYAN}│ ${BOLD}Gráfico                                 ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├──────────────┼──────────┼────────────────────────────────────────────┤${NC}"
    
    # Obtener conteos de tipos de archivos
    local file_types=$(git ls-files | grep -v "^$" | awk -F. '{print $NF}' | sort | uniq -c | sort -rn | head -10)
    local max_files=$(echo "$file_types" | head -1 | awk '{print $1}')
    
    echo "$file_types" | while read -r count ext; do
        if [ "$max_files" -eq 0 ]; then
            local percent=0
        else
            local percent=$((count * 100 / max_files))
        fi
        
        local bar=""
        
        # Crear barra de progreso
        for ((j=0; j<percent/2; j++)); do
            bar="${bar}█"
        done
        
        if [ "$ext" = "" ]; then
            ext="(sin ext.)"
        fi
        
        printf "${CYAN}│${NC} %-12s ${CYAN}│${NC} %-8s ${CYAN}│${NC} ${GREEN}%-40s${NC} ${CYAN}│${NC}\n" ".$ext" "$count" "$bar"
    done
    
    echo -e "${CYAN}└──────────────┴──────────┴────────────────────────────────────────────┘${NC}"
    
    return 0
}

# Analizar tamaño y complejidad de archivos
analyze_file_sizes() {
    local repo_path="${1:-.}"
    local limit="${2:-10}"
    
    if [ ! -d "$repo_path/.git" ]; then
        error "El directorio '$repo_path' no es un repositorio Git."
        return 1
    fi
    
    info "Analizando tamaño de archivos en el repositorio..."
    
    # Cambiar al directorio del repositorio
    cd "$repo_path" || return 1
    
    # Mostrar archivos más grandes
    echo -e "\n${CYAN}${BOLD}Archivos más grandes${NC}"
    echo -e "${CYAN}┌───────────────┬────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Tamaño        ${NC}${CYAN}│ ${BOLD}Archivo                                                ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├───────────────┼────────────────────────────────────────────────────────────┤${NC}"
    
    git ls-files | xargs du -b 2>/dev/null | sort -nr | head -n "$limit" | while read -r size file; do
        # Convertir bytes a unidades legibles
        if [ "$size" -gt 1048576 ]; then
            readable_size=$(echo "scale=2; $size/1048576" | bc)
            unit="MB"
        elif [ "$size" -gt 1024 ]; then
            readable_size=$(echo "scale=2; $size/1024" | bc)
            unit="KB"
        else
            readable_size=$size
            unit="B"
        fi
        
        printf "${CYAN}│${NC} %-11s ${CYAN}│${NC} %-60s ${CYAN}│${NC}\n" "$readable_size $unit" "$file"
    done
    
    echo -e "${CYAN}└───────────────┴────────────────────────────────────────────────────────────┘${NC}"
    
    # Mostrar archivos con más líneas
    echo -e "\n${CYAN}${BOLD}Archivos con más líneas${NC}"
    echo -e "${CYAN}┌───────────────┬────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Líneas        ${NC}${CYAN}│ ${BOLD}Archivo                                                ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├───────────────┼────────────────────────────────────────────────────────────┤${NC}"
    
    git ls-files | xargs wc -l 2>/dev/null | sort -nr | head -n "$((limit + 1))" | tail -n "$limit" | while read -r lines file; do
        printf "${CYAN}│${NC} %-11s ${CYAN}│${NC} %-60s ${CYAN}│${NC}\n" "$lines" "$file"
    done
    
    echo -e "${CYAN}└───────────────┴────────────────────────────────────────────────────────────┘${NC}"
    
    # Mostrar archivos cambiados con más frecuencia
    echo -e "\n${CYAN}${BOLD}Archivos modificados con más frecuencia${NC}"
    echo -e "${CYAN}┌───────────────┬────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ${BOLD}Cambios       ${NC}${CYAN}│ ${BOLD}Archivo                                                ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├───────────────┼────────────────────────────────────────────────────────────┤${NC}"
    
    git log --name-only --pretty=format: | grep -v "^$" | sort | uniq -c | sort -nr | head -n "$limit" | while read -r changes file; do
        printf "${CYAN}│${NC} %-11s ${CYAN}│${NC} %-60s ${CYAN}│${NC}\n" "$changes" "$file"
    done
    
    echo -e "${CYAN}└───────────────┴────────────────────────────────────────────────────────────┘${NC}"
    
    return 0
}

# ===================================================================================
# Funciones principales y subcomandos
# ===================================================================================

# Mostrar la versión
show_version() {
    echo -e "${GREEN}GitMaster v$GITMASTER_VERSION${NC}"
    echo "La herramienta definitiva para dominar GitHub desde la terminal"
    echo "Creada por Claude 3.7 Sonnet - Un asistente de Anthropic con capacidades de razonamiento avanzadas"
}

# Mostrar ayuda
show_help() {
    show_header
    
    echo -e "${BOLD}USO:${NC}"
    echo "  gitmaster [comando] [opciones]"
    echo
    echo -e "${BOLD}COMANDOS DISPONIBLES:${NC}"
    echo "  ${CYAN}repo${NC}"
    echo "    ${CYAN}create${NC} <nombre> [descripción] [privado=false] - Crear un nuevo repositorio"
    echo "    ${CYAN}delete${NC} <nombre> - Eliminar un repositorio"
    echo "    ${CYAN}list${NC} [tipo=all] [orden=updated] [dirección=desc] - Listar repositorios"
    echo "    ${CYAN}clone${NC} <url|nombre> [directorio] - Clonar un repositorio"
    echo "    ${CYAN}init${NC} [nombre] [descripción] [privado=false] - Inicializar y subir repositorio"
    echo
    echo "  ${CYAN}user${NC}"
    echo "    ${CYAN}info${NC} - Mostrar información del usuario autenticado"
    echo "    ${CYAN}view${NC} <usuario> - Ver detalles de un usuario"
    echo "    ${CYAN}repos${NC} <usuario> [orden=updated] [dirección=desc] - Listar repositorios de usuario"
    echo
    echo "  ${CYAN}search${NC}"
    echo "    ${CYAN}repo${NC} <consulta> [orden=stars] [dirección=desc] - Buscar repositorios"
    echo "    ${CYAN}user${NC} <consulta> [orden=followers] [dirección=desc] - Buscar usuarios"
    echo "    ${CYAN}trending${NC} [lenguaje] [periodo=daily] - Ver repositorios en tendencia"
    echo
    echo "  ${CYAN}branch${NC}"
    echo "    ${CYAN}create${NC} <nombre> [rama_base] - Crear una nueva rama"
    echo "    ${CYAN}feature${NC} <start|complete> <nombre> [rama_base] - Gestionar features"
    echo "    ${CYAN}release${NC} <start|complete> <versión> [rama_base] - Gestionar releases"
    echo
    echo "  ${CYAN}issues${NC}"
    echo "    ${CYAN}list${NC} [repo] [estado=open] [orden=created] - Listar issues"
    echo "    ${CYAN}create${NC} [repo] [título] [cuerpo] [etiquetas] - Crear un issue"
    echo "    ${CYAN}close${NC} [repo] <número> - Cerrar un issue"
    echo
    echo "  ${CYAN}pr${NC} o ${CYAN}pull${NC}"
    echo "    ${CYAN}list${NC} [repo] [estado=open] [orden=created] - Listar pull requests"
    echo "    ${CYAN}create${NC} [repo] [rama_origen] [rama_destino] [título] - Crear pull request"
    echo
    echo "  ${CYAN}analyze${NC}"
    echo "    ${CYAN}contrib${NC} [directorio=.] [desde] [hasta] - Analizar contribuciones"
    echo "    ${CYAN}files${NC} [directorio=.] [límite=10] - Analizar tamaño de archivos"
    echo
    echo "  ${CYAN}config${NC}"
    echo "    ${CYAN}init${NC} - Inicializar configuración"
    echo "    ${CYAN}set${NC} <clave> <valor> - Establecer un valor de configuración"
    echo "    ${CYAN}get${NC} <clave> - Obtener un valor de configuración"
    echo "    ${CYAN}list${NC} - Listar toda la configuración"
    echo
    echo "  ${CYAN}help${NC} - Mostrar esta ayuda"
    echo "  ${CYAN}version${NC} - Mostrar la versión"
    echo
    echo -e "${BOLD}EJEMPLOS:${NC}"
    echo "  gitmaster repo create mi-proyecto \"Mi nuevo proyecto\" true"
    echo "  gitmaster search repo \"machine learning\" stars desc"
    echo "  gitmaster branch feature start nueva-funcionalidad"
    echo "  gitmaster analyze contrib"
}

# Comandos para configuración
config_cmd() {
    local subcmd="$1"
    shift
    
    case "$subcmd" in
        init)
            info "Inicializando configuración..."
            init_config_dirs
            success "Configuración inicializada en $GITMASTER_CONFIG_DIR"
            ;;
        set)
            local key="$1"
            local value="$2"
            
            if [ -z "$key" ] || [ -z "$value" ]; then
                error "Debe proporcionar una clave y un valor."
                return 1
            fi
            
            info "Estableciendo $key = $value"
            
            # Usar jq para actualizar el valor anidado
            local temp_file=$(mktemp)
            jq "$(echo "$key" | sed 's/\./\]\[/g' | sed 's/^/\[/;s/$/\]/')" = "\"$value\"" "$GITMASTER_CONFIG_FILE" > "$temp_file"
            mv "$temp_file" "$GITMASTER_CONFIG_FILE"
            
            success "Configuración actualizada."
            ;;
        get)
            local key="$1"
            
            if [ -z "$key" ]; then
                error "Debe proporcionar una clave."
                return 1
            fi
            
            local value=$(jq -r "$(echo "$key" | sed 's/\./\]\[/g' | sed 's/^/\[/;s/$/\]/')" "$GITMASTER_CONFIG_FILE")
            echo "$value"
            ;;
        list)
            echo -e "${CYAN}${BOLD}Configuración actual:${NC}"
            jq '.' "$GITMASTER_CONFIG_FILE"
            ;;
        *)
            error "Subcomando de configuración desconocido: $subcmd"
            echo "Subcomandos disponibles: init, set, get, list"
            return 1
            ;;
    esac
}

# Comando principal
main() {
    # Verificar si se proporciona un comando
    if [ $# -eq 0 ]; then
        show_header
        show_help
        return 0
    fi
    
    # Inicializar configuración
    init_config_dirs
    
    # Procesar comando
    local cmd="$1"
    shift
    
    case "$cmd" in
        repo)
            local subcmd="$1"
            shift
            
            case "$subcmd" in
                create)
                    create_repo "$@"
                    ;;
                delete)
                    delete_repo "$@"
                    ;;
                list)
                    list_repos "$@"
                    ;;
                clone)
                    clone_repo "$@"
                    ;;
                init)
                    init_and_push "$@"
                    ;;
                *)
                    error "Subcomando de repositorio desconocido: $subcmd"
                    echo "Subcomandos disponibles: create, delete, list, clone, init"
                    return 1
                    ;;
            esac
            ;;
        user)
            local subcmd="$1"
            shift
            
            case "$subcmd" in
                info)
                    get_user_info | jq '.'
                    ;;
                view)
                    get_user_details "$@"
                    ;;
                repos)
                    list_user_repos "$@"
                    ;;
                *)
                    error "Subcomando de usuario desconocido: $subcmd"
                    echo "Subcomandos disponibles: info, view, repos"
                    return 1
                    ;;
            esac
            ;;
        search)
            local subcmd="$1"
            shift
            
            case "$subcmd" in
                repo)
                    search_repos "$@"
                    ;;
                user)
                    search_users "$@"
                    ;;
                trending)
                    trending_repos "$@"
                    ;;
                *)
                    error "Subcomando de búsqueda desconocido: $subcmd"
                    echo "Subcomandos disponibles: repo, user, trending"
                    return 1
                    ;;
            esac
            ;;
        branch)
            local subcmd="$1"
            shift
            
            case "$subcmd" in
                create)
                    create_branch "$@"
                    ;;
                feature)
                    local feature_cmd="$1"
                    shift
                    
                    case "$feature_cmd" in
                        start)
                            start_feature "$@"
                            ;;
                        complete)
                            complete_feature "$@"
                            ;;
                        *)
                            error "Comando de feature desconocido: $feature_cmd"
                            echo "Comandos disponibles: start, complete"
                            return 1
                            ;;
                    esac
                    ;;
                release)
                    local release_cmd="$1"
                    shift
                    
                    case "$release_cmd" in
                        start)
                            start_release "$@"
                            ;;
                        complete)
                            complete_release "$@"
                            ;;
                        *)
                            error "Comando de release desconocido: $release_cmd"
                            echo "Comandos disponibles: start, complete"
                            return 1
                            ;;
                    esac
                    ;;
                *)
                    error "Subcomando de rama desconocido: $subcmd"
                    echo "Subcomandos disponibles: create, feature, release"
                    return 1
                    ;;
            esac
            ;;
        issues|issue)
            local subcmd="$1"
            shift
            
            case "$subcmd" in
                list)
                    list_issues "$@"
                    ;;
                create)
                    create_issue "$@"
                    ;;
                close)
                    close_issue "$@"
                    ;;
                *)
                    error "Subcomando de issue desconocido: $subcmd"
                    echo "Subcomandos disponibles: list, create, close"
                    return 1
                    ;;
            esac
            ;;
        pr|pull)
            local subcmd="$1"
            shift
            
            case "$subcmd" in
                list)
                    list_pulls "$@"
                    ;;
                create)
                    create_pull_request "$@"
                    ;;
                *)
                    error "Subcomando de pull request desconocido: $subcmd"
                    echo "Subcomandos disponibles: list, create"
                    return 1
                    ;;
            esac
            ;;
        analyze)
            local subcmd="$1"
            shift
            
            case "$subcmd" in
                contrib)
                    analyze_contributions "$@"
                    ;;
                files)
                    analyze_file_sizes "$@"
                    ;;
                *)
                    error "Subcomando de análisis desconocido: $subcmd"
                    echo "Subcomandos disponibles: contrib, files"
                    return 1
                    ;;
            esac
            ;;
        config)
            config_cmd "$@"
            ;;
        help)
            show_header
            show_help
            ;;
        version)
            show_version
            ;;
        *)
            error "Comando desconocido: $cmd"
            echo "Ejecute 'gitmaster help' para ver los comandos disponibles."
            return 1
            ;;
    esac
    
    return 0
}

# Evitar ejecución si el script es sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Verificar dependencias
    check_dependencies
    
    # Cargar configuración
    load_config
    
    # Ejecutar comando principal
    main "$@"
fi