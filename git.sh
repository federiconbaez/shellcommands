#!/bin/bash

#==============================================================================
#
#   GitHelper - Herramienta mejorada para Git y GitHub
#   Versión: 1.0.0
#
#   Una interfaz de línea de comandos que simplifica las operaciones
#   comunes y avanzadas de Git y GitHub.
#
#==============================================================================

# ============== CONFIGURACIÓN Y VARIABLES ==============

# Definición de colores
RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
MAGENTA="\033[35m"

# Configuración de archivos y directorios
CONFIG_DIR="$HOME/.git-helper"
CONFIG_FILE="$CONFIG_DIR/config.json"
CACHE_DIR="$CONFIG_DIR/cache"
GITHUB_API="https://api.github.com"
GIT_VERSION=$(git --version | awk '{print $3}')

# ============== FUNCIONES AUXILIARES ==============

# Mostrar mensaje de error y salir
die() {
    echo -e "${RED}Error: $1${RESET}" >&2
    exit 1
}

# Mostrar mensaje informativo
info() {
    echo -e "${BLUE}[INFO]${RESET} $1"
}

# Mostrar mensaje de éxito
success() {
    echo -e "${GREEN}[✓]${RESET} $1"
}

# Mostrar mensaje de advertencia
warning() {
    echo -e "${YELLOW}[!]${RESET} $1"
}

# Mostrar mensaje de error
error() {
    echo -e "${RED}[✗]${RESET} $1"
}

# Asegurar que el directorio de configuración existe
ensure_config_dirs() {
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        mkdir -p "$CACHE_DIR"
        chmod 700 "$CONFIG_DIR"
    fi
}

# Verificar las dependencias necesarias
check_dependencies() {
    local missing_deps=0
    
    for cmd in git curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Falta dependencia: $cmd"
            missing_deps=$((missing_deps + 1))
        fi
    done
    
    if [ $missing_deps -gt 0 ]; then
        die "Por favor, instale las dependencias faltantes e intente nuevamente."
    fi
    
    info "Git versión: $GIT_VERSION"
}

# ============== FUNCIONES DE CONFIGURACIÓN ==============

# Cargar la configuración
load_config() {
    ensure_config_dirs
    
    if [ -f "$CONFIG_FILE" ]; then
        GITHUB_TOKEN=$(jq -r '.github_token // ""' "$CONFIG_FILE" 2>/dev/null)
        GITHUB_USERNAME=$(jq -r '.github_username // ""' "$CONFIG_FILE" 2>/dev/null)
        DEFAULT_REMOTE=$(jq -r '.default_remote // "origin"' "$CONFIG_FILE" 2>/dev/null)
        PR_TEMPLATE=$(jq -r '.pr_template // ""' "$CONFIG_FILE" 2>/dev/null)
    else
        # Valores predeterminados si no existe el archivo
        GITHUB_TOKEN=""
        GITHUB_USERNAME=""
        DEFAULT_REMOTE="origin"
        PR_TEMPLATE=""
        
        # Crear archivo de configuración con valores predeterminados
        save_config
    fi
}

# Guardar la configuración
save_config() {
    ensure_config_dirs
    
    # Crear JSON con la configuración actual
    cat > "$CONFIG_FILE" << EOF
{
    "github_token": "$GITHUB_TOKEN",
    "github_username": "$GITHUB_USERNAME",
    "default_remote": "$DEFAULT_REMOTE",
    "pr_template": "$PR_TEMPLATE"
}
EOF
    
    chmod 600 "$CONFIG_FILE"  # Restringir permisos por seguridad
}

# Configurar credenciales de GitHub
configure_github() {
    echo -e "${BLUE}${BOLD}Configuración de GitHub${RESET}"
    echo "Esta información se utilizará para interactuar con GitHub."
    echo "El token debe tener permisos para: repo, workflow, read:org"
    echo "Puede crear un token en: https://github.com/settings/tokens"
    echo
    
    read -p "Ingrese su nombre de usuario de GitHub: " GITHUB_USERNAME
    read -sp "Ingrese su token de acceso personal de GitHub: " GITHUB_TOKEN
    echo
    
    save_config
    
    # Verificar el token
    if validate_github_token; then
        success "Configuración guardada y verificada correctamente."
    else
        error "El token no pudo ser verificado. Verifique sus credenciales."
        # Mantener los valores para que el usuario pueda corregirlos
    fi
}

# Validar token de GitHub
validate_github_token() {
    if [ -z "$GITHUB_TOKEN" ]; then
        return 1
    fi
    
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API/user")
    
    if [ "$response_code" -eq 200 ]; then
        return 0  # Token válido
    else
        return 1  # Token inválido
    fi
}

# Asegurar que hay un token válido de GitHub
ensure_github_token() {
    if ! validate_github_token; then
        error "No se ha configurado un token de GitHub válido."
        echo "Por favor, configure sus credenciales de GitHub:"
        configure_github
        
        # Verificar nuevamente después de la configuración
        if ! validate_github_token; then
            die "No se pudo configurar un token de GitHub válido."
        fi
    fi
}

# ============== FUNCIONES BÁSICAS DE GIT ==============

# Verificar si estamos en un repositorio git
ensure_git_repo() {
    if ! git rev-parse --git-dir &> /dev/null; then
        die "No estás en un repositorio Git. Ejecuta 'git init' o cambia al directorio correcto."
    fi
}

# Clonar un repositorio
clone_repo() {
    echo -e "${BLUE}${BOLD}Clonar Repositorio${RESET}"
    echo "Proporcione la URL del repositorio que desea clonar."
    echo "También puede ingresar 'username/repo' para repositorios de GitHub."
    echo
    
    read -p "URL/Nombre del repositorio: " repo_url
    
    # Verificar si es un formato shorthand de GitHub (usuario/repo)
    if [[ "$repo_url" =~ ^[^/]+/[^/]+$ && ! "$repo_url" =~ ^https?:// && ! "$repo_url" =~ ^git@ ]]; then
        read -p "¿Usar SSH para clonar? (s/N): " use_ssh
        
        if [[ "$use_ssh" =~ ^[Ss]$ ]]; then
            repo_url="git@github.com:$repo_url.git"
        else
            repo_url="https://github.com/$repo_url.git"
        fi
    fi
    
    read -p "Directorio destino (opcional): " target_dir
    
    echo -e "${BOLD}Clonando repositorio...${RESET}"
    if [ -z "$target_dir" ]; then
        git clone --progress "$repo_url"
    else
        git clone --progress "$repo_url" "$target_dir"
    fi
    
    if [ $? -eq 0 ]; then
        # Determinar el directorio del repositorio clonado
        if [ -z "$target_dir" ]; then
            target_dir=$(basename "$repo_url" .git)
        fi
        
        success "Repositorio clonado exitosamente en: $target_dir"
        
        # Preguntar si desea acceder al directorio clonado
        read -p "¿Desea cambiar al directorio del repositorio? (s/N): " change_dir
        if [[ "$change_dir" =~ ^[Ss]$ ]]; then
            cd "$target_dir" || return 1
            echo -e "Directorio actual: ${GREEN}$(pwd)${RESET}"
            
            # Mostrar información del repositorio
            echo -e "\n${BOLD}Información del repositorio:${RESET}"
            echo -e "Remote origen: ${GREEN}$(git remote get-url origin)${RESET}"
            echo -e "Rama actual: ${GREEN}$(git branch --show-current)${RESET}"
            remote_branches=$(git branch -r | wc -l)
            echo -e "Ramas remotas: ${GREEN}$remote_branches${RESET}"
        fi
    else
        error "Error al clonar el repositorio."
        echo "Verifique la URL e intente de nuevo."
    fi
}

# Crear una rama y cambiar a ella
create_branch() {
    ensure_git_repo
    
    echo -e "${BLUE}${BOLD}Crear y Cambiar a Nueva Rama${RESET}"
    
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    echo -e "Rama actual: ${CYAN}$current_branch${RESET}"
    
    read -p "Ingrese el nombre de la nueva rama: " branch_name
    
    if [ -z "$branch_name" ]; then
        error "El nombre de la rama no puede estar vacío."
        return 1
    fi
    
    read -p "¿Actualizar la rama actual antes de ramificar? (S/n): " update_branch
    if [[ ! "$update_branch" =~ ^[Nn]$ ]]; then
        echo "Actualizando rama $current_branch..."
        git pull
    fi
    
    echo "Creando rama: $branch_name..."
    if git checkout -b "$branch_name"; then
        success "Rama '$branch_name' creada y activada."
        
        # Preguntar si desea configurar el upstream
        read -p "¿Desea publicar esta rama en el remoto? (s/N): " push_branch
        if [[ "$push_branch" =~ ^[Ss]$ ]]; then

            # Preguntar si desea configurar el remote origin
            read -p "¿Desea configurar el remote origin para esta rama? (s/N): " set_remote
            git remote add origin "$GITHUB_API/$branch_name.git"
            if [[ "$set_remote" =~ ^[Ss]$ ]]; then
                echo "Configurando remote origin para la rama $branch_name..."
                git remote set-url origin "$GITHUB_API/$branch_name.git"
            fi

            # Configurar el remote origin
            echo "Configurando remote origin para la rama $branch_name..."
            git remote set-url origin "$GITHUB_API/$branch_name.git"

            # Verificar si el remote origin se configuró correctamente
            if [ $? -eq 0 ]; then
                success "Remote origin configurado para la rama '$branch_name'."
            else
                error "Error al configurar el remote origin."
            fi

            # Configurar el upstream
            echo "Configurando upstream para la rama $branch_name..."
            git push --set-upstream origin "$branch_name"
            if [ $? -eq 0 ]; then
                success "Upstream configurado para la rama '$branch_name'."
            else
                error "Error al configurar el upstream."
            fi

            # Preguntar si desea hacer push de la rama
            git push -u origin "$branch_name"
            if [ $? -eq 0 ]; then
                success "Rama publicada en el remoto."
            else
                error "Error al publicar la rama."
            fi
        fi
    else
        error "Error al crear la rama."
    fi
}

# Hacer pull de la rama actual
pull_current_branch() {
    ensure_git_repo
    
    echo -e "${BLUE}${BOLD}Pull de la Rama Actual${RESET}"
    
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    echo -e "Rama actual: ${CYAN}$current_branch${RESET}"
    
    # Listar remotes disponibles
    echo -e "\nRemotes disponibles:"
    git remote -v | grep "(fetch)" | awk '{print "  " $1 " -> " $2}'
    
    # Autodetectar remote configurado para la rama actual
    remote=$(git config --get branch.$current_branch.remote || echo "origin")
    
    read -p "Remote (predeterminado: $remote): " input_remote
    if [ -n "$input_remote" ]; then
        remote="$input_remote"
    fi
    
    echo "Verificando cambios remotos..."
    git fetch "$remote"
    
    echo -e "Opciones de integración:"
    echo "  1. Merge (predeterminado)"
    echo "  2. Rebase"
    echo "  3. Fast-forward únicamente"
    read -p "Seleccione una opción [1-3]: " merge_option
    
    case "$merge_option" in
        2)
            echo "Ejecutando: git pull --rebase $remote $current_branch"
            git pull --rebase "$remote" "$current_branch"
            ;;
        3)
            echo "Ejecutando: git pull --ff-only $remote $current_branch"
            git pull --ff-only "$remote" "$current_branch"
            ;;
        *)
            echo "Ejecutando: git pull $remote $current_branch"
            git pull "$remote" "$current_branch"
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        success "Pull completado exitosamente."
    else
        error "Error al hacer pull."
        echo -e "\n${YELLOW}Consulte los mensajes anteriores para obtener detalles sobre el error.${RESET}"
    fi
}

# Hacer merge de una rama en la rama actual
merge_branch() {
    ensure_git_repo
    
    echo -e "${BLUE}${BOLD}Merge de Rama${RESET}"
    
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    echo -e "Rama actual: ${CYAN}$current_branch${RESET}"
    
    # Listar todas las ramas locales y remotas
    echo -e "\n${BOLD}Ramas locales:${RESET}"
    git branch | sed 's/^../  /'
    
    echo -e "\n${BOLD}Ramas remotas:${RESET}"
    git branch -r | grep -v 'HEAD' | sed 's/^../  /'
    
    read -p "Ingrese el nombre de la rama a mergear: " branch_name
    
    if [ -z "$branch_name" ]; then
        error "Debe especificar una rama."
        return 1
    fi
    
    # Verificar si la rama existe
    if ! git show-ref --verify --quiet "refs/heads/$branch_name" && 
       ! git show-ref --verify --quiet "refs/remotes/$branch_name"; then
        # Intentar encontrar la rama si es que se ingresó de forma parcial
        possible_matches=$(git branch --all | grep -i "$branch_name" | sed 's/^..//' | sed 's/remotes\///')
        
        if [ -n "$possible_matches" ]; then
            echo -e "${YELLOW}Rama '$branch_name' no encontrada, pero se encontraron estas posibles coincidencias:${RESET}"
            echo "$possible_matches"
            read -p "Ingrese el nombre completo de la rama: " branch_name
        else
            error "La rama '$branch_name' no existe."
            return 1
        fi
    fi
    
    echo -e "\nOpciones de merge:"
    echo "  1. Merge normal (crea un commit de merge)"
    echo "  2. Squash (combina todos los commits en uno)"
    echo "  3. Fast-forward únicamente (rechaza si se necesita merge)"
    read -p "Seleccione una opción [1-3]: " merge_option
    
    # Verificar si hay cambios sin commitear
    if [ -n "$(git status --porcelain)" ]; then
        warning "Hay cambios sin commitear en su espacio de trabajo."
        read -p "¿Desea hacer stash de estos cambios antes del merge? (s/N): " do_stash
        
        if [[ "$do_stash" =~ ^[Ss]$ ]]; then
            git stash
            echo "Cambios guardados en stash."
        else
            warning "Continuando con el merge con cambios sin commitear."
        fi
    fi
    
    # Realizar el merge según la opción elegida
    case "$merge_option" in
        2)
            echo "Ejecutando: git merge --squash $branch_name"
            git merge --squash "$branch_name"
            
            if [ $? -eq 0 ]; then
                echo "Cambios preparados para commit. Cree un commit para completar el squash:"
                read -p "Mensaje de commit: " commit_msg
                
                if [ -z "$commit_msg" ]; then
                    commit_msg="Merge squash de '$branch_name' en '$current_branch'"
                fi
                
                git commit -m "$commit_msg"
            fi
            ;;
        3)
            echo "Ejecutando: git merge --ff-only $branch_name"
            git merge --ff-only "$branch_name"
            ;;
        *)
            echo "Ejecutando: git merge $branch_name"
            git merge "$branch_name"
            ;;
    esac
    
    merge_status=$?
    
    # Recuperar cambios de stash si se hizo
    if [[ "$do_stash" =~ ^[Ss]$ ]]; then
        echo "Recuperando cambios del stash..."
        git stash pop
    fi
    
    # Verificar resultado del merge
    if [ $merge_status -eq 0 ]; then
        success "Merge completado exitosamente."
    else
        error "Se encontraron conflictos durante el merge."
        echo -e "\n${BOLD}Opciones para resolver conflictos:${RESET}"
        echo "  1. Utilizar herramienta de merge (git mergetool)"
        echo "  2. Abortar el merge"
        echo "  3. Resolver manualmente (estado actual)"
        read -p "Seleccione una opción [1-3]: " conflict_option
        
        case "$conflict_option" in
            1)
                git mergetool
                read -p "¿Desea completar el merge con commit? (S/n): " complete_merge
                if [[ ! "$complete_merge" =~ ^[Nn]$ ]]; then
                    git commit
                fi
                ;;
            2)
                git merge --abort
                echo "Merge abortado."
                ;;
            *)
                echo -e "\n${YELLOW}Resuelva los conflictos manualmente y luego ejecute:${RESET}"
                echo "  git add <archivos>"
                echo "  git commit"
                ;;
        esac
    fi
}

# Ver el historial de commits
view_commit_log() {
    ensure_git_repo
    
    echo -e "${BLUE}${BOLD}Historial de Commits${RESET}"
    
    echo -e "\nOpciones de visualización:"
    echo "  1. Log simple"
    echo "  2. Log con gráfico"
    echo "  3. Log con estadísticas"
    echo "  4. Log personalizado (gráfico, oneline)"
    echo "  5. Commits de un autor específico"
    echo "  6. Buscar commits por mensaje"
    read -p "Seleccione una opción [1-6]: " log_option
    
    case "$log_option" in
        2)
            read -p "Número de commits a mostrar (Enter para todos): " num_commits
            
            if [ -z "$num_commits" ]; then
                git log --graph --pretty=format:'%C(yellow)%h%Creset%C(auto)%d%Creset %s %C(blue)<%an>%Creset %C(green)(%cr)%Creset' --all
            else
                git log --graph --pretty=format:'%C(yellow)%h%Creset%C(auto)%d%Creset %s %C(blue)<%an>%Creset %C(green)(%cr)%Creset' --all -n "$num_commits"
            fi
            ;;
        3)
            read -p "Número de commits a mostrar (Enter para todos): " num_commits
            
            if [ -z "$num_commits" ]; then
                git log --stat
            else
                git log --stat -n "$num_commits"
            fi
            ;;
        4)
            read -p "Número de commits a mostrar (Enter para todos): " num_commits
            
            if [ -z "$num_commits" ]; then
                git log --graph --pretty=oneline --abbrev-commit --all
            else
                git log --graph --pretty=oneline --abbrev-commit --all -n "$num_commits"
            fi
            ;;
        5)
            read -p "Ingrese el nombre del autor: " author_name
            
            if [ -z "$author_name" ]; then
                error "Debe especificar un nombre de autor."
                return 1
            fi
            
            git log --author="$author_name" --pretty=format:'%C(yellow)%h%Creset - %s %C(blue)<%an>%Creset %C(green)(%cr)%Creset'
            ;;
        6)
            read -p "Ingrese el texto a buscar: " search_text
            
            if [ -z "$search_text" ]; then
                error "Debe especificar un texto para buscar."
                return 1
            fi
            
            git log --grep="$search_text" --pretty=format:'%C(yellow)%h%Creset - %s %C(blue)<%an>%Creset %C(green)(%cr)%Creset'
            ;;
        *)
            read -p "Número de commits a mostrar (Enter para todos): " num_commits
            
            if [ -z "$num_commits" ]; then
                git log
            else
                git log -n "$num_commits"
            fi
            ;;
    esac
}

# Ver el estado del repositorio
view_repo_status() {
    ensure_git_repo
    
    echo -e "${BLUE}${BOLD}Estado del Repositorio${RESET}\n"
    
    # Información básica
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    echo -e "Rama actual: ${CYAN}$current_branch${RESET}"
    
    # Verificar si la rama tiene un upstream
    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
    
    if [ -n "$upstream" ]; then
        echo -e "Upstream: ${CYAN}$upstream${RESET}"
        
        # Obtener estado de commits adelante/atrás
        git fetch --quiet
        ahead=$(git rev-list --count @{upstream}..HEAD 2>/dev/null)
        behind=$(git rev-list --count HEAD..@{upstream} 2>/dev/null)
        
        if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
            echo -e "Estado: ${YELLOW}$ahead commit(s) adelante y $behind commit(s) atrás del remoto${RESET}"
        elif [ "$ahead" -gt 0 ]; then
            echo -e "Estado: ${GREEN}$ahead commit(s) adelante del remoto${RESET}"
        elif [ "$behind" -gt 0 ]; then
            echo -e "Estado: ${RED}$behind commit(s) atrás del remoto${RESET}"
        else
            echo -e "Estado: ${GREEN}Sincronizado con el remoto${RESET}"
        fi
    else
        echo -e "Estado: ${YELLOW}Rama local sin seguimiento remoto${RESET}"
    fi
    
    # Última actividad
    last_commit=$(git log -1 --pretty=format:'%h - %s (%cr) <%an>' 2>/dev/null)
    if [ -n "$last_commit" ]; then
        echo -e "Último commit: ${CYAN}$last_commit${RESET}"
    else
        echo -e "Último commit: ${YELLOW}No hay commits todavía${RESET}"
    fi
    
    # Estado detallado
    echo -e "\n${BOLD}Cambios en el espacio de trabajo:${RESET}"
    changes=$(git status --porcelain)
    
    if [ -z "$changes" ]; then
        echo -e "${GREEN}El espacio de trabajo está limpio, no hay cambios.${RESET}"
    else
        # Contar número de archivos cambiados
        staged_new=$(echo "$changes" | grep -c "^A")
        staged_modified=$(echo "$changes" | grep -c "^M")
        staged_deleted=$(echo "$changes" | grep -c "^D")
        unstaged_modified=$(echo "$changes" | grep -c "^.M")
        unstaged_deleted=$(echo "$changes" | grep -c "^.D")
        untracked=$(echo "$changes" | grep -c "^??")
        
        # Mostrar resumen
        echo -e "${BOLD}Resumen:${RESET}"
        [ "$staged_new" -gt 0 ] && echo -e "  ${GREEN}$staged_new${RESET} archivos nuevos preparados para commit"
        [ "$staged_modified" -gt 0 ] && echo -e "  ${GREEN}$staged_modified${RESET} archivos modificados preparados para commit"
        [ "$staged_deleted" -gt 0 ] && echo -e "  ${GREEN}$staged_deleted${RESET} archivos eliminados preparados para commit"
        [ "$unstaged_modified" -gt 0 ] && echo -e "  ${YELLOW}$unstaged_modified${RESET} archivos modificados sin preparar"
        [ "$unstaged_deleted" -gt 0 ] && echo -e "  ${YELLOW}$unstaged_deleted${RESET} archivos eliminados sin preparar"
        [ "$untracked" -gt 0 ] && echo -e "  ${RED}$untracked${RESET} archivos sin seguimiento"
        
        # Mostrar listado detallado
        echo -e "\n${BOLD}Cambios detallados:${RESET}"
        git status -s
    fi
    
    # Mostrar ramas locales y remotas
    echo -e "\n${BOLD}Ramas locales:${RESET}"
    git branch --sort=-committerdate --format="  %(if:equals=*)%(HEAD)%(then)${GREEN}%(else)${RESET}%(end)%(align:25,left)%(refname:short)%(end) - %(contents:subject) (%(committerdate:relative))"
    
    # Información de stash
    stash_count=$(git stash list | wc -l)
    if [ "$stash_count" -gt 0 ]; then
        echo -e "\n${BOLD}Stash:${RESET} ${CYAN}$stash_count${RESET} entrada(s)"
        git stash list | head -3 | sed 's/^/  /'
        if [ "$stash_count" -gt 3 ]; then
            echo "  ..."
        fi
    fi
}

# ============== FUNCIONES AVANZADAS DE GIT ==============

# Guardar cambios temporalmente (stash)
stash_changes() {
    ensure_git_repo
    
    echo -e "${BLUE}${BOLD}Guardar Cambios Temporalmente (Stash)${RESET}"
    
    # Verificar si hay cambios para stash
    if [ -z "$(git status --porcelain)" ]; then
        error "No hay cambios para guardar en stash."
        return 1
    fi
    
    # Mostrar cambios actuales
    echo -e "${BOLD}Cambios actuales:${RESET}"
    git status -s
    
    echo -e "\nOpciones de stash:"
    echo "  1. Stash de todos los cambios (incluyendo no seguidos)"
    echo "  2. Stash de solo cambios en archivos seguidos"
    echo "  3. Stash interactivo (seleccionar cambios)"
    read -p "Seleccione una opción [1-3]: " stash_option
    
    read -p "Mensaje descriptivo para el stash (opcional): " stash_message
    
    case "$stash_option" in
        2)
            if [ -z "$stash_message" ]; then
                git stash
            else
                git stash save "$stash_message"
            fi
            ;;
        3)
            git stash -p
            ;;
        *)
            if [ -z "$stash_message" ]; then
                git stash --include-untracked
            else
                git stash save --include-untracked "$stash_message"
            fi
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        success "Cambios guardados en stash exitosamente."
        echo -e "Use '${CYAN}git stash list${RESET}' para ver todos los stashes."
        echo -e "Use '${CYAN}git stash apply${RESET}' o '${CYAN}git stash pop${RESET}' para recuperar."
    else
        error "Error al guardar cambios en stash."
    fi
}

# Aplicar cambios guardados en stash
apply_stash() {
    ensure_git_repo
    
    echo -e "${BLUE}${BOLD}Aplicar Cambios desde Stash${RESET}"
    
    # Listar stashes disponibles
    stash_list=$(git stash list)
    if [ -z "$stash_list" ]; then
        error "No hay stashes guardados."
        return 1
    fi
    
    echo -e "${BOLD}Stashes disponibles:${RESET}"
    echo "$stash_list" | nl -w2 -s') '
    
    read -p "Seleccione el número de stash a aplicar (Enter para el último): " stash_index
    
    # Opciones para aplicar stash
    echo -e "\nOpciones de aplicación:"
    echo "  1. Aplicar y mantener stash (apply)"
    echo "  2. Aplicar y eliminar stash (pop)"
    echo "  3. Ver contenido sin aplicar"
    read -p "Seleccione una opción [1-3]: " apply_option
    
    # Construir referencia al stash
    stash_ref="stash@{0}"  # Por defecto, el más reciente
    if [ -n "$stash_index" ]; then
        # Ajustar el índice (la numeración del usuario comienza en 1)
        stash_index=$((stash_index - 1))
        stash_ref="stash@{$stash_index}"
    fi
    
    case "$apply_option" in
        2)
            git stash pop "$stash_ref"
            if [ $? -eq 0 ]; then
                success "Stash aplicado y eliminado exitosamente."
            else
                error "Error al aplicar el stash. Posibles conflictos."
                echo -e "\n${YELLOW}Sugerencias para resolver:${RESET}"
                echo "  1. Resuelva los conflictos manualmente"
                echo "  2. Use 'git stash drop $stash_ref' si ya no necesita estos cambios"
            fi
            ;;
        3)
            echo -e "${BOLD}Contenido del stash:${RESET}"
            git stash show -p "$stash_ref"
            
            read -p "¿Desea aplicar este stash ahora? (s/N): " apply_now
            if [[ "$apply_now" =~ ^[Ss]$ ]]; then
                read -p "¿Eliminar el stash después de aplicar? (s/N): " delete_after
                if [[ "$delete_after" =~ ^[Ss]$ ]]; then
                    git stash pop "$stash_ref"
                else
                    git stash apply "$stash_ref"
                fi
            fi
            ;;
        *)
            git stash apply "$stash_ref"
            if [ $? -eq 0 ]; then
                success "Stash aplicado exitosamente. El stash permanece guardado."
                echo -e "Use '${CYAN}git stash drop $stash_ref${RESET}' si desea eliminarlo."
            else
                error "Error al aplicar el stash. Posibles conflictos."
            fi
            ;;
    esac
}

# Realizar rebase interactivo
interactive_rebase() {
    ensure_git_repo
    
    echo -e "${BLUE}${BOLD}Rebase Interactivo${RESET}"
    echo -e "${YELLOW}¡Advertencia! El rebase modifica el historial de Git.${RESET}"
    echo -e "Esto puede causar problemas si los cambios ya fueron enviados a un repositorio remoto."
    echo
    
    # Mostrar historial de commits recientes
    echo -e "${BOLD}Commits recientes:${RESET}"
    git log --oneline -n 10
    echo
    
    read -p "¿Cuántos commits atrás desea hacer rebase? " num_commits
    
    if [ -z "$num_commits" ] || ! [[ "$num_commits" =~ ^[0-9]+$ ]]; then
        error "Por favor, especifique un número válido de commits."
        return 1
    fi
    
    echo -e "\n${BOLD}En el editor que se abrirá, podrá modificar los commits:${RESET}"
    echo "  - pick: mantener el commit como está"
    echo "  - reword: cambiar el mensaje del commit"
    echo "  - edit: pausar para modificar el commit"
    echo "  - squash: combinar con el commit anterior"
    echo "  - fixup: combinar y descartar el mensaje"
    echo "  - drop: eliminar el commit"
    echo
    
    read -p "Presione Enter para continuar..."
    
    git rebase -i HEAD~"$num_commits"
    
    rebase_status=$?
    if [ $rebase_status -eq 0 ]; then
        success "Rebase interactivo completado exitosamente."
        
        # Preguntar si desea forzar el push
        current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
        upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
        
        if [ -n "$upstream" ]; then
            echo -e "\n${YELLOW}Advertencia: Ha modificado el historial de una rama que ya está publicada.${RESET}"
            read -p "¿Desea forzar el push de estos cambios al repositorio remoto? (s/N): " force_push
            
            if [[ "$force_push" =~ ^[Ss]$ ]]; then
                echo -e "${RED}¡Atención! El push forzado sobrescribirá el repositorio remoto.${RESET}"
                read -p "¿Está seguro? Escriba 'confirmar' para proceder: " confirmation
                
                if [ "$confirmation" = "confirmar" ]; then
                    remote=$(echo "$upstream" | cut -d '/' -f 1)
                    branch=$(echo "$upstream" | cut -d '/' -f 2-)
                    
                    echo "Ejecutando: git push --force-with-lease $remote $current_branch:$branch"
                    git push --force-with-lease "$remote" "$current_branch":"$branch"
                fi
            fi
        fi
    elif [ $rebase_status -eq 1 ]; then
        warning "Rebase en progreso."
        echo -e "\nSi hay conflictos, resuélvalos y luego ejecute:"
        echo -e "  ${CYAN}git rebase --continue${RESET}"
        echo -e "\nPara abortar el rebase:"
        echo -e "  ${CYAN}git rebase --abort${RESET}"
    else
        error "Error durante el rebase."
    fi
}

# Git add y commit en un solo paso
git_add_commit() {
    # Verificar que estamos en un repositorio git
    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        error "No estás dentro de un repositorio Git."
        return 1
    fi
    
    echo -e "${BLUE}${BOLD}Git Add y Commit${RESET}"
    
    # Obtener la rama actual
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [ -z "$current_branch" ]; then
        error "No se pudo determinar la rama actual."
        return 1
    fi
    
    # Verificar si hay cambios para agregar
    if [ -z "$(git status --porcelain)" ]; then
        warning "No hay cambios para agregar."
        
        # Verificar si hay commits para pushear
        local ahead=0
        local remote_exists=1
        
        # Verificar si hay un upstream configurado para la rama
        if git rev-parse @{u} &>/dev/null; then
            ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
            remote_exists=0
        fi
        
        if [ $remote_exists -eq 0 ] && [ "$ahead" -gt 0 ]; then
            echo -e "${YELLOW}Tienes $ahead commit(s) local(es) que no están en el remoto.${RESET}"
            
            # Pushear cambios al remoto
            read -p "¿Desea hacer push de los cambios al remoto? (s/N): " push_changes
            if [[ "$push_changes" =~ ^[Ss]$ ]]; then
                # Obtener el remoto configurado para la rama actual
                local remote=$(git config --get branch.$current_branch.remote)
                if [ -z "$remote" ]; then
                    # Si no hay remoto configurado, preguntar
                    echo -e "${YELLOW}No hay un remoto configurado para la rama actual.${RESET}"
                    git remote -v
                    read -p "Ingrese el nombre del remoto (ej. origin): " remote
                    
                    if [ -z "$remote" ]; then
                        error "Se requiere un remoto para hacer push."
                        return 1
                    fi
                fi
                
                echo -e "Haciendo push a ${CYAN}$remote/$current_branch${RESET}..."
                git push "$remote" "$current_branch"
                
                if [ $? -eq 0 ]; then
                    success "Cambios enviados al remoto exitosamente."
                else
                    error "Error al enviar cambios al remoto."
                    echo -e "${YELLOW}¿Necesita configurar el upstream para esta rama?${RESET}"
                    read -p "¿Desea configurar el upstream y reintentar? (s/N): " set_upstream
                    
                    if [[ "$set_upstream" =~ ^[Ss]$ ]]; then
                        git push --set-upstream "$remote" "$current_branch"
                        
                        if [ $? -eq 0 ]; then
                            success "Upstream configurado y push realizado correctamente."
                        else
                            error "No se pudo configurar el upstream. Verifique la configuración del remoto:"
                            git remote -v
                            read -p "¿Desea modificar la URL del remoto? (s/N): " modify_remote
                            
                            if [[ "$modify_remote" =~ ^[Ss]$ ]]; then
                                read -p "Ingrese la nueva URL para $remote: " remote_url
                                if [ -n "$remote_url" ]; then
                                    git remote set-url "$remote" "$remote_url"
                                    success "URL del remoto actualizada. Intente hacer push manualmente."
                                fi
                            fi
                        fi
                    fi
                fi
            else
                echo -e "${YELLOW}No se enviaron cambios al remoto.${RESET}"
            fi
        elif [ $remote_exists -ne 0 ]; then
            warning "Esta rama no tiene un remoto configurado."
            git remote -v
            
            if [ -z "$(git remote)" ]; then
                echo -e "${YELLOW}No hay remotos configurados en este repositorio.${RESET}"
                read -p "¿Desea agregar un remoto? (s/N): " add_remote
                
                if [[ "$add_remote" =~ ^[Ss]$ ]]; then
                    read -p "Nombre del remoto (ej. origin): " remote_name
                    read -p "URL del remoto: " remote_url
                    
                    if [ -n "$remote_name" ] && [ -n "$remote_url" ]; then
                        git remote add "$remote_name" "$remote_url"
                        success "Remoto '$remote_name' agregado correctamente."
                        
                        read -p "¿Desea hacer push a este remoto? (s/N): " do_push
                        if [[ "$do_push" =~ ^[Ss]$ ]]; then
                            git push --set-upstream "$remote_name" "$current_branch"
                            
                            if [ $? -eq 0 ]; then
                                success "Push realizado correctamente."
                            else
                                error "Error al hacer push."
                            fi
                        fi
                    else
                        error "Se requieren nombre y URL para agregar un remoto."
                    fi
                fi
            else
                read -p "¿Desea configurar un upstream para esta rama? (s/N): " set_upstream
                
                if [[ "$set_upstream" =~ ^[Ss]$ ]]; then
                    echo "Remotos disponibles:"
                    git remote -v
                    read -p "Ingrese el nombre del remoto: " remote_name
                    
                    if [ -n "$remote_name" ]; then
                        git push --set-upstream "$remote_name" "$current_branch"
                        
                        if [ $? -eq 0 ]; then
                            success "Upstream configurado y push realizado correctamente."
                        else
                            error "Error al configurar el upstream."
                        fi
                    fi
                fi
            fi
        else
            echo -e "${GREEN}La rama está actualizada con el remoto.${RESET}"
        fi

        # Verificar si hay cambios en el stash
        stash_count=$(git stash list | wc -l)

        if [ "$stash_count" -gt 0 ]; then
            echo -e "\n${BOLD}Cambios en el stash:${RESET} ${CYAN}$stash_count${RESET} entrada(s)"
            git stash list | head -3 | sed 's/^/  /'
            if [ "$stash_count" -gt 3 ]; then
                echo "  ..."
            fi
            
            read -p "¿Desea aplicar algún stash? (s/N): " apply_stash
            if [[ "$apply_stash" =~ ^[Ss]$ ]]; then
                read -p "Índice del stash a aplicar (Enter para el último): " stash_index
                
                if [ -z "$stash_index" ]; then
                    git stash pop
                else
                    git stash pop "stash@{$stash_index}"
                fi
                
                if [ $? -eq 0 ]; then
                    success "Stash aplicado correctamente."
                else
                    error "Error al aplicar el stash."
                fi
            fi
        else
            echo -e "${GREEN}No hay cambios en el stash.${RESET}"
        fi
        
        return 0
    fi
    
    # Mostrar cambios actuales
    echo -e "${BOLD}Cambios actuales:${RESET}"
    git status -s
    
    # Opciones para agregar archivos
    echo -e "\n${BOLD}Opciones para agregar archivos:${RESET}"
    echo "  1. Agregar todos los archivos"
    echo "  2. Agregar archivos específicos"
    echo "  3. Agregar archivos interactivamente"
    echo "  4. Ver diferencias antes de agregar"
    read -p "Seleccione una opción [1-4]: " add_option
    
    case "$add_option" in
        2)
            read -p "Archivos a agregar (separados por espacio): " files_to_add
            if [ -n "$files_to_add" ]; then
                git add $files_to_add
                echo -e "${GREEN}Archivos agregados.${RESET}"
            else
                error "No se especificaron archivos."
                return 1
            fi
            ;;
        3)
            git add -i
            ;;
        4)
            # Mostrar diferencias y luego preguntar qué agregar
            git diff
            read -p "¿Desea agregar todos los archivos? (s/N): " add_all
            if [[ "$add_all" =~ ^[Ss]$ ]]; then
                git add .
                echo -e "${GREEN}Todos los archivos agregados.${RESET}"
            else
                read -p "Archivos a agregar (separados por espacio): " files_to_add
                if [ -n "$files_to_add" ]; then
                    git add $files_to_add
                    echo -e "${GREEN}Archivos seleccionados agregados.${RESET}"
                else
                    error "No se especificaron archivos."
                    return 1
                fi
            fi
            ;;
        *)
            git add .
            echo -e "${GREEN}Agregando todos los archivos...${RESET}"
            ;;
    esac
    
    # Confirmar qué se va a enviar
    echo -e "\n${BOLD}Archivos preparados para commit:${RESET}"
    git status -s
    
    # Solicitar mensaje de commit
    read -p "Mensaje de commit: " commit_msg
    
    if [ -z "$commit_msg" ]; then
        error "El mensaje de commit no puede estar vacío."
        return 1
    fi
    
    # Preguntar por mensaje extendido
    read -p "¿Desea agregar un mensaje de commit extendido? (s/N): " extended_msg
    
    if [[ "$extended_msg" =~ ^[Ss]$ ]]; then
        echo "Ingrese el mensaje extendido (termine con Ctrl+D en una nueva línea):"
        extended_content=$(cat)
        
        # Realizar el commit con mensaje extendido
        git commit -m "$commit_msg" -m "$extended_content"
    else
        # Realizar el commit
        git commit -m "$commit_msg"
    fi
    
    if [ $? -eq 0 ]; then
        success "Commit realizado exitosamente."
        
        # Mostrar el último commit
        echo -e "\n${BOLD}Último commit:${RESET}"
        git show --stat HEAD
        
        # Preguntar si desea hacer push
        read -p "¿Desea hacer push de los cambios? (s/N): " do_push
        
        if [[ "$do_push" =~ ^[Ss]$ ]]; then
            # Obtener el remoto configurado para la rama actual
            local remote=$(git config --get branch.$current_branch.remote)
            
            if [ -z "$remote" ]; then
                # Si no hay remoto configurado, preguntar
                echo -e "${YELLOW}No hay un remoto configurado para la rama actual.${RESET}"
                git remote -v
                
                if [ -z "$(git remote)" ]; then
                    echo -e "${YELLOW}No hay remotos configurados en este repositorio.${RESET}"
                    read -p "¿Desea agregar un remoto? (s/N): " add_remote
                    
                    if [[ "$add_remote" =~ ^[Ss]$ ]]; then
                        read -p "Nombre del remoto (ej. origin): " remote_name
                        read -p "URL del remoto: " remote_url
                        
                        if [ -n "$remote_name" ] && [ -n "$remote_url" ]; then
                            git remote add "$remote_name" "$remote_url"
                            success "Remoto '$remote_name' agregado correctamente."
                            remote="$remote_name"
                        else
                            error "Se requieren nombre y URL para agregar un remoto."
                            return 1
                        fi
                    else
                        return 0
                    fi
                else 
                    read -p "Ingrese el nombre del remoto para push (ej. origin): " remote
                    
                    if [ -z "$remote" ]; then
                        error "Se requiere un remoto para hacer push."
                        return 1
                    fi
                fi
            fi
            
            # Intentar push
            echo -e "Haciendo push a ${CYAN}$remote/$current_branch${RESET}..."
            git push "$remote" "$current_branch"
            
            if [ $? -eq 0 ]; then
                success "Push realizado correctamente a $remote/$current_branch."
            else
                error "Error al hacer push. Puede que necesite configurar el upstream."
                read -p "¿Desea configurar el upstream y reintentar? (s/N): " set_upstream
                
                if [[ "$set_upstream" =~ ^[Ss]$ ]]; then
                    git push --set-upstream "$remote" "$current_branch"
                    
                    if [ $? -eq 0 ]; then
                        success "Upstream configurado y push realizado correctamente."
                    else
                        error "No se pudo hacer push. Verifique la configuración del remoto."
                        git remote -v
                        read -p "¿Desea modificar la URL del remoto? (s/N): " modify_remote
                        
                        if [[ "$modify_remote" =~ ^[Ss]$ ]]; then
                            read -p "Ingrese la nueva URL para $remote: " remote_url
                            if [ -n "$remote_url" ]; then
                                git remote set-url "$remote" "$remote_url"
                                success "URL del remoto actualizada."
                                
                                # Intentar push nuevamente
                                read -p "¿Desea intentar push nuevamente? (s/N): " retry_push
                                if [[ "$retry_push" =~ ^[Ss]$ ]]; then
                                    git push --set-upstream "$remote" "$current_branch"
                                
                                    if [ $? -eq 0 ]; then
                                        success "Push realizado correctamente."
                                    else
                                        error "Error al hacer push nuevamente."
                                    fi
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        fi
    else
        error "Error al realizar el commit."
    fi
}

# Cherry-pick commits
cherry_pick_commits() {
    ensure_git_repo
    
    echo -e "${BLUE}${BOLD}Cherry-pick Commits${RESET}"
    echo "Esta función le permite aplicar commits específicos a la rama actual."
    echo
    
    # Mostrar ramas disponibles
    echo -e "${BOLD}Ramas disponibles:${RESET}"
    git branch --all | grep -v "^\*" | sed 's/^../  /'
    
    read -p "¿De qué rama o referencia desea ver los commits? (Enter para todas): " source_branch
    
    # Mostrar commits disponibles
    echo -e "\n${BOLD}Commits disponibles:${RESET}"
    
    if [ -z "$source_branch" ]; then
        git log --oneline --all --graph -n 20
    else
        git log --oneline --graph "$source_branch" -n 20
    fi
    
    echo -e "\n${BOLD}Opciones:${RESET}"
    echo "  1. Cherry-pick un solo commit"
    echo "  2. Cherry-pick un rango de commits"
    read -p "Seleccione una opción [1-2]: " pick_option
    
    case "$pick_option" in
        2)
            read -p "Ingrese el hash del commit inicial (más antiguo): " start_commit
            read -p "Ingrese el hash del commit final (más reciente): " end_commit
            
            if [ -z "$start_commit" ] || [ -z "$end_commit" ]; then
                error "Ambos hashes de commit son requeridos."
                return 1
            fi
            
            # Verificar si queremos incluir o excluir el commit inicial
            read -p "¿Incluir el commit inicial en el rango? (S/n): " include_start
            
            range_option=""
            if [[ "$include_start" =~ ^[Nn]$ ]]; then
                range_option="--right-only"
            fi
            
            # Crear lista de commits para cherry-pick
            commit_list=$(git rev-list --reverse $range_option "$start_commit".."$end_commit")
            
            echo -e "\n${BOLD}Commits que serán aplicados (del más antiguo al más reciente):${RESET}"
            for commit in $commit_list; do
                git show --oneline --no-patch "$commit"
            done
            
            read -p "¿Confirma el cherry-pick de estos commits? (s/N): " confirm_pick
            
            if [[ "$confirm_pick" =~ ^[Ss]$ ]]; then
                # Opciones para el cherry-pick
                read -p "¿Desea crear commits automáticamente? (S/n): " auto_commit
                
                cherry_opts=""
                if [[ "$auto_commit" =~ ^[Nn]$ ]]; then
                    cherry_opts="--no-commit"
                fi
                
                # Aplicar cada commit en orden
                for commit in $commit_list; do
                    echo -e "\nAplicando commit: $(git show --oneline --no-patch "$commit")"
                    if ! git cherry-pick $cherry_opts "$commit"; then
                        error "Error durante cherry-pick. Resuelva los conflictos y continúe manualmente."
                        echo -e "\nOpciones:"
                        echo -e "  - Resolver conflictos, añadir archivos con 'git add' y ejecutar:"
                        echo -e "    ${CYAN}git cherry-pick --continue${RESET}"
                        echo -e "  - Para abortar todo el proceso:"
                        echo -e "    ${CYAN}git cherry-pick --abort${RESET}"
                        return 1
                    fi
                done
                
                success "Cherry-pick completado exitosamente."
            else
                echo "Cherry-pick cancelado."
            fi
            ;;
            
        *)
            read -p "Ingrese el hash del commit que desea aplicar: " commit_hash
            
            if [ -z "$commit_hash" ]; then
                error "Debe especificar un hash de commit válido."
                return 1
            fi
            
            # Verificar opciones de cherry-pick
            read -p "¿Crear commit automáticamente? (S/n): " auto_commit
            
            cherry_opts=""
            if [[ "$auto_commit" =~ ^[Nn]$ ]]; then
                cherry_opts="--no-commit"
            fi
            
            # Ejecutar cherry-pick
            git cherry-pick $cherry_opts "$commit_hash"
            
            pick_status=$?
            if [ $pick_status -eq 0 ]; then
                success "Cherry-pick completado exitosamente."
            else
                error "Se detectaron conflictos durante el cherry-pick."
                echo -e "\nOpciones:"
                echo -e "  1. Resolver conflictos y continuar"
                echo -e "  2. Abortar cherry-pick"
                read -p "Seleccione una opción [1-2]: " conflict_option
                
                case "$conflict_option" in
                    2)
                        git cherry-pick --abort
                        echo "Cherry-pick abortado."
                        ;;
                    *)
                        echo -e "\nResolución de conflictos:"
                        echo -e "  1. Resuelva los conflictos en los archivos"
                        echo -e "  2. Añada los archivos resueltos con 'git add <archivos>'"
                        echo -e "  3. Complete el cherry-pick con: git cherry-pick --continue"
                        ;;
                esac
            fi
            ;;
    esac
}

# Resolver conflictos
resolve_conflicts() {
    ensure_git_repo
    
    echo -e "${BLUE}${BOLD}Herramienta de Resolución de Conflictos${RESET}"
    
    # Verificar si hay conflictos
    if ! git ls-files -u | grep -q .; then
        error "No se detectaron archivos con conflictos."
        
        # Verificar si hay un merge o rebase en progreso
        if [ -d "$(git rev-parse --git-dir)/rebase-merge" ] || [ -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
            echo -e "\n${YELLOW}Hay un rebase en progreso. Estado de la operación:${RESET}"
            
            # Mostrar opciones para rebase
            echo -e "  1. Continuar rebase (después de resolver conflictos)"
            echo -e "  2. Omitir commit actual"
            echo -e "  3. Abortar rebase"
            read -p "Seleccione una opción [1-3]: " rebase_option
            
            case "$rebase_option" in
                2)
                    git rebase --skip
                    ;;
                3)
                    git rebase --abort
                    echo "Rebase abortado."
                    ;;
                *)
                    git rebase --continue
                    ;;
            esac
        elif [ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]; then
            echo -e "\n${YELLOW}Hay un merge en progreso. Estado de la operación:${RESET}"
            
            # Mostrar opciones para merge
            echo -e "  1. Continuar merge (después de resolver conflictos)"
            echo -e "  2. Abortar merge"
            read -p "Seleccione una opción [1-2]: " merge_option
            
            case "$merge_option" in
                2)
                    git merge --abort
                    echo "Merge abortado."
                    ;;
                *)
                    git merge --continue
                    ;;
            esac
        elif [ -f "$(git rev-parse --git-dir)/CHERRY_PICK_HEAD" ]; then
            echo -e "\n${YELLOW}Hay un cherry-pick en progreso. Estado de la operación:${RESET}"
            
            # Mostrar opciones para cherry-pick
            echo -e "  1. Continuar cherry-pick (después de resolver conflictos)"
            echo -e "  2. Abortar cherry-pick"
            read -p "Seleccione una opción [1-2]: " cherry_option
            
            case "$cherry_option" in
                2)
                    git cherry-pick --abort
                    echo "Cherry-pick abortado."
                    ;;
                *)
                    git cherry-pick --continue
                    ;;
            esac
        fi
        
        return 0
    fi
    
    # Listar archivos con conflictos
    echo -e "${BOLD}Archivos con conflictos:${RESET}"
    conflicted_files=$(git diff --name-only --diff-filter=U)
    echo "$conflicted_files" | nl -w2 -s') '
    
    # Opciones para resolver conflictos
    echo -e "\n${BOLD}Opciones para resolver conflictos:${RESET}"
    echo "  1. Usar herramienta visual de merge (git mergetool)"
    echo "  2. Ver y editar archivos con conflictos individualmente"
    echo "  3. Usar 'ours' para todos los conflictos (mantener nuestros cambios)"
    echo "  4. Usar 'theirs' para todos los conflictos (usar los cambios de ellos)"
    echo "  5. Abortar la operación actual (merge/rebase/cherry-pick)"
    read -p "Seleccione una opción [1-5]: " conflict_option
    
    case "$conflict_option" in
        1)
            # Usar herramienta visual de merge
            if ! command -v git-mergetool &> /dev/null; then
                echo -e "\n${BOLD}Herramientas de merge disponibles:${RESET}"
                git mergetool --tool-help | grep -A 100 "The following merge tools are available:" | tail -n +2
                
                read -p "Especifique la herramienta a usar (Enter para la predeterminada): " merge_tool
                
                if [ -n "$merge_tool" ]; then
                    git mergetool --tool="$merge_tool"
                else
                    git mergetool
                fi
            else
                git mergetool
            fi
            
            # Verificar si quedan conflictos
            if ! git ls-files -u | grep -q .; then
                echo -e "\n${GREEN}Todos los conflictos han sido resueltos.${RESET}"
                echo -e "Para completar la operación, ejecute según corresponda:"
                echo -e "  - ${CYAN}git merge --continue${RESET}"
                echo -e "  - ${CYAN}git rebase --continue${RESET}"
                echo -e "  - ${CYAN}git cherry-pick --continue${RESET}"
            else
                echo -e "\n${YELLOW}Aún hay conflictos sin resolver.${RESET}"
            fi
            ;;
            
        2)
            # Resolver conflictos individualmente
            for file in $conflicted_files; do
                echo -e "\n${BOLD}Archivo: $file${RESET}"
                echo -e "${YELLOW}Mostrando conflictos:${RESET}"
                
                # Mostrar secciones con conflictos
                grep -n -C 2 "<<<<<<< HEAD" "$file" || echo "No se encontraron marcadores de conflicto estándar."
                
                # Opciones para este archivo
                echo -e "\n${BOLD}Opciones para '$file':${RESET}"
                echo "  1. Editar archivo para resolver conflictos"
                echo "  2. Usar nuestra versión (--ours)"
                echo "  3. Usar su versión (--theirs)"
                echo "  4. Saltar este archivo por ahora"
                read -p "Seleccione una opción [1-4]: " file_option
                
                case "$file_option" in
                    2)
                        git checkout --ours -- "$file"
                        git add "$file"
                        echo "Aplicados nuestros cambios para '$file'"
                        ;;
                    3)
                        git checkout --theirs -- "$file"
                        git add "$file"
                        echo "Aplicados sus cambios para '$file'"
                        ;;
                    4)
                        echo "Saltando '$file'..."
                        ;;
                    *)
                        ${EDITOR:-nano} "$file"
                        
                        # Verificar si todavía hay marcadores de conflicto
                        if grep -q "<<<<<<< HEAD" "$file" || grep -q "=======" "$file" || grep -q ">>>>>>>" "$file"; then
                            echo -e "\n${YELLOW}El archivo aún contiene marcadores de conflicto.${RESET}"
                            read -p "¿Marcar como resuelto de todos modos? (s/N): " force_resolved
                            
                            if [[ "$force_resolved" =~ ^[Ss]$ ]]; then
                                git add "$file"
                                echo "Archivo '$file' marcado como resuelto"
                            fi
                        else
                            git add "$file"
                            echo "Archivo '$file' resuelto y añadido"
                        fi
                        ;;
                esac
            done
            
            # Verificar si quedan conflictos
            if ! git ls-files -u | grep -q .; then
                echo -e "\n${GREEN}Todos los conflictos han sido resueltos.${RESET}"
                
                # Detectar qué operación está en progreso
                if [ -d "$(git rev-parse --git-dir)/rebase-merge" ] || [ -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
                    echo "Continuando rebase..."
                    git rebase --continue
                elif [ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]; then
                    echo "Continuando merge..."
                    git merge --continue
                elif [ -f "$(git rev-parse --git-dir)/CHERRY_PICK_HEAD" ]; then
                    echo "Continuando cherry-pick..."
                    git cherry-pick --continue
                else
                    echo -e "Use el comando apropiado para continuar la operación actual."
                fi
            else
                echo -e "\n${YELLOW}Aún hay conflictos sin resolver.${RESET}"
            fi
            ;;
            
        3)
            # Usar nuestra versión para todos los conflictos
            echo "Aplicando nuestra versión para todos los archivos con conflicto..."
            
            for file in $conflicted_files; do
                git checkout --ours -- "$file"
                git add "$file"
                echo "Resuelto: $file (usando nuestra versión)"
            done
            
            echo -e "\n${GREEN}Todos los conflictos han sido resueltos usando nuestra versión.${RESET}"
            echo -e "Para completar la operación, ejecute el comando apropiado."
            ;;
            
        4)
            # Usar su versión para todos los conflictos
            echo "Aplicando su versión para todos los archivos con conflicto..."
            
            for file in $conflicted_files; do
                git checkout --theirs -- "$file"
                git add "$file"
                echo "Resuelto: $file (usando su versión)"
            done
            
            echo -e "\n${GREEN}Todos los conflictos han sido resueltos usando su versión.${RESET}"
            echo -e "Para completar la operación, ejecute el comando apropiado."
            ;;
            
        5)
            # Abortar la operación actual
            if [ -d "$(git rev-parse --git-dir)/rebase-merge" ] || [ -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
                git rebase --abort
                echo "Rebase abortado."
            elif [ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]; then
                git merge --abort
                echo "Merge abortado."
            elif [ -f "$(git rev-parse --git-dir)/CHERRY_PICK_HEAD" ]; then
                git cherry-pick --abort
                echo "Cherry-pick abortado."
            else
                error "No se pudo determinar qué operación abortar."
            fi
            ;;
    esac
}

# ============== FUNCIONES DE GITHUB ==============


# Función para listar repositorios de GitHub
list_github_repos() {
    echo -e "${BLUE}Mis Repositorios en GitHub${RESET}"
    
    validate_token || return 1
    
    echo -e "Consultando repositorios para ${YELLOW}$GITHUB_USERNAME${RESET}..."
    
    # Obtener repositorios
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API/user/repos?per_page=100")
    
    if echo "$response" | grep -q "message.*API rate limit exceeded"; then
        echo -e "${RED}Se ha excedido el límite de la API de GitHub.${RESET}"
        return 1
    fi
    
    # Imprimir repositorios
    echo -e "\n${BOLD}Repositorios disponibles:${RESET}"
    echo "$response" | grep -E '"full_name"|"html_url"|"default_branch"|"private"' | \
        sed -E 's/"full_name": "([^"]+)",/\n\1/g' | \
        sed -E 's/"html_url": "([^"]+)",/  URL: \1/g' | \
        sed -E 's/"default_branch": "([^"]+)",/  Rama principal: \1/g' | \
        sed -E 's/"private": (true|false),/  Privado: \1/g' | \
        grep -v "^  *$"
}

# Función para crear un nuevo repositorio en GitHub
create_github_repo() {
    echo -e "${BLUE}Crear Nuevo Repositorio en GitHub${RESET}"
    
    validate_token || return 1
    
    # Validar entrada del usuario
    while true; do
        read -p "Nombre del repositorio: " repo_name
        if [ -z "$repo_name" ]; then
            echo -e "${RED}Error: El nombre del repositorio no puede estar vacío.${RESET}"
        else
            # Verificar si ya existe el repositorio
            check_response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API/repos/$GITHUB_USERNAME/$repo_name")
            if [ "$check_response" = "200" ]; then
                echo -e "${YELLOW}Advertencia: Ya existe un repositorio con ese nombre.${RESET}"
                read -p "¿Desea usar otro nombre? (s/n): " change_name
                [ "$change_name" = "s" ] || [ "$change_name" = "S" ] && continue
            fi
            break
        fi
    done
    
    read -p "Descripción (opcional): " repo_description
    read -p "¿Repositorio privado? (s/n): " is_private
    
    if [ "$is_private" = "s" ] || [ "$is_private" = "S" ]; then
        private="true"
    else
        private="false"
    fi
    
    # Sanitizar inputs para JSON
    repo_name=$(echo "$repo_name" | sed 's/"/\\"/g')
    repo_description=$(echo "$repo_description" | sed 's/"/\\"/g')
    
    # Crear JSON para la solicitud
    json_data="{\"name\":\"$repo_name\",\"description\":\"$repo_description\",\"private\":$private}"
    
    echo -e "${YELLOW}Creando repositorio...${RESET}"
    
    # Enviar solicitud a GitHub API
    response=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" -d "$json_data" "$GITHUB_API/user/repos")
    
    # Verificar si hay problemas de límite de API
    if echo "$response" | grep -q "API rate limit exceeded"; then
        echo -e "${RED}Error: Se ha excedido el límite de la API de GitHub. Inténtelo más tarde.${RESET}"
        return 1
    fi
    
    # Verificar si el repositorio se creó correctamente
    if echo "$response" | grep -q "\"name\":\"$repo_name\"" || echo "$response" | grep -q "\"name\":.*\"$repo_name\""; then
        # Extraer la URL del repositorio - método más robusto
        repo_url=""
        
        # Intento 1: Extraer directamente de la respuesta
        if repo_url=$(echo "$response" | grep -o '"html_url":"[^"]*"' | head -1 | sed 's/"html_url":"//;s/"//'); then
            echo -e "${GREEN}Repositorio creado exitosamente: $repo_url${RESET}"
        else
            # Intento 2: Construir la URL basada en el nombre de usuario y repositorio
            echo -e "${YELLOW}No se pudo extraer la URL directamente. Construyendo URL alternativa...${RESET}"
            repo_url="https://github.com/$GITHUB_USERNAME/$repo_name"
            echo -e "${GREEN}Repositorio creado exitosamente: $repo_url${RESET}"
        fi
        
        # Verificar que tenemos una URL válida antes de continuar
        if [ -z "$repo_url" ]; then
            echo -e "${RED}Error: No se pudo determinar la URL del repositorio.${RESET}"
            echo -e "${YELLOW}El repositorio probablemente se creó, pero deberá configurar el remoto manualmente.${RESET}"
            echo -e "${YELLOW}URL probable: https://github.com/$GITHUB_USERNAME/$repo_name${RESET}"
            return 1
        fi
        
        # Preguntar si desea inicializar el repositorio local
        read -p "¿Desea inicializar un repositorio local y vincularlo? (s/n): " init_local
        
        if [ "$init_local" = "s" ] || [ "$init_local" = "S" ]; then
            read -p "Directorio para el repositorio (Enter para directorio actual): " repo_dir
            
            if [ -n "$repo_dir" ]; then
                if ! mkdir -p "$repo_dir" 2>/dev/null; then
                    echo -e "${RED}Error: No se pudo crear el directorio '$repo_dir'.${RESET}"
                    return 1
                fi
                if ! cd "$repo_dir" 2>/dev/null; then
                    echo -e "${RED}Error: No se pudo acceder al directorio '$repo_dir'.${RESET}"
                    return 1
                fi
                echo -e "${GREEN}Usando directorio: $(pwd)${RESET}"
            fi
            
            echo -e "${YELLOW}Inicializando repositorio local...${RESET}"
            
            if ! git init; then
                echo -e "${RED}Error al inicializar el repositorio git.${RESET}"
                return 1
            fi
            
            echo "# $repo_name" > README.md
            echo -e "\n$repo_description" >> README.md
            
            git add README.md
            git commit -m "Inicialización del repositorio"
            
            # Asegurar que la rama principal se llama 'master'
            echo -e "${YELLOW}Configurando rama principal como 'master'...${RESET}"
            git branch -M master
            
            # Agregar remoto
            echo -e "${YELLOW}Configurando remoto 'origin' a $repo_url...${RESET}"
            if ! git remote add origin "$repo_url"; then
                echo -e "${RED}Error al configurar el remoto origin.${RESET}"
                return 1
            fi
            
            # Push inicial
            echo -e "${YELLOW}Subiendo cambios iniciales al repositorio remoto...${RESET}"
            if ! git push -u origin master; then
                echo -e "${RED}Error al subir cambios al repositorio remoto.${RESET}"
                echo -e "${YELLOW}Puede intentar manualmente con: git push -u origin master${RESET}"
                return 1
            fi
            
            echo -e "${GREEN}Repositorio local inicializado y vinculado exitosamente.${RESET}"
        fi
    else
        # Extraer mensaje de error más detallado
        if ! error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | head -1 | sed 's/"message":"//;s/"//'); then
            error_msg="Error desconocido. Compruebe su conexión e inténtelo de nuevo."
        fi
        echo -e "${RED}Error al crear el repositorio: $error_msg${RESET}"
        
        if echo "$error_msg" | grep -q "already exists"; then
            echo -e "${YELLOW}Sugerencia: Intente con otro nombre para el repositorio.${RESET}"
        elif echo "$error_msg" | grep -q "authenticated"; then
            echo -e "${YELLOW}Sugerencia: Verifique su token de GitHub ejecutando la opción 16 del menú.${RESET}"
        fi
    fi
}

# Función para validar token de GitHub
validate_token() {
    if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${YELLOW}No se ha configurado un token de GitHub.${RESET}"
        configure_github
        return 1
    fi
    
    # Verificar si el token es válido
    response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" $GITHUB_API/user)
    
    if [ "$response" != "200" ]; then
        echo -e "${RED}Token de GitHub inválido o expirado.${RESET}"
        configure_github
        return 1
    fi
    
    return 0
}

create_pull_request() {
    ensure_github_token
    ensure_git_repo
    
    echo -e "${BLUE}${BOLD}Crear Pull Request${RESET}"
    
    # Verificar si hay cambios sin commit
    if [ -n "$(git status --porcelain)" ]; then
        warning "Hay cambios sin commitear en su espacio de trabajo."
        read -p "¿Desea hacer commit de estos cambios antes de continuar? (s/N): " do_commit
        
        if [[ "$do_commit" =~ ^[Ss]$ ]]; then
            git add .
            read -p "Mensaje para el commit: " commit_msg
            git commit -m "${commit_msg:-"Cambios para pull request"}"
        else
            warning "Continuando con cambios sin commitear."
        fi
    fi
    
    # Obtener información del repositorio
    local remote_url=$(git config --get remote.origin.url)
    if [ -z "$remote_url" ]; then
        error "No se encontró un remote 'origin'."
        echo "Asegúrese de que el repositorio tenga un remote configurado."
        return 1
    fi
    
    # Obtener repo name en formato owner/repo
    local repo_info
    if [[ "$remote_url" =~ github.com[/:]([^/]+)/([^/.]+) ]]; then
        repo_info="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    else
        error "No se pudo determinar el repositorio de GitHub desde la URL: $remote_url"
        read -p "Ingrese el repositorio en formato 'propietario/repo': " repo_info
        
        if [ -z "$repo_info" ] || ! [[ "$repo_info" =~ ^[^/]+/[^/]+$ ]]; then
            error "Formato de repositorio inválido."
            return 1
        fi
    fi
    
    echo -e "Repositorio: ${CYAN}$repo_info${RESET}"
    
    # Obtener rama actual
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    echo -e "Rama actual: ${CYAN}$current_branch${RESET}"
    
    # Verificar ramas disponibles para PR
    echo -e "\n${BOLD}Ramas disponibles en el repositorio:${RESET}"
    
    local branches_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API/repos/$repo_info/branches")
    
    if echo "$branches_response" | grep -q "Not Found"; then
        error "Repositorio no encontrado: $repo_info"
        return 1
    fi
    
    echo "$branches_response" | jq -r '.[].name' | sort | sed 's/^/  /'
    
    # Solicitar información del PR
    read -p "Rama base (destino, generalmente 'master'): " base_branch
    
    if [ -z "$base_branch" ]; then
        error "La rama base es obligatoria."
        return 1
    fi
    
    # Verificar si la rama actual ya tiene un PR abierto
    local existing_prs=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                         "$GITHUB_API/repos/$repo_info/pulls?head=$GITHUB_USERNAME:$current_branch&state=open")
    
    if [ "$(echo "$existing_prs" | jq length)" -gt 0 ]; then
        warning "Ya existe un pull request abierto para esta rama:"
        local pr_url=$(echo "$existing_prs" | jq -r '.[0].html_url')
        local pr_title=$(echo "$existing_prs" | jq -r '.[0].title')
        echo -e "  Título: ${CYAN}$pr_title${RESET}"
        echo -e "  URL: ${CYAN}$pr_url${RESET}"
        
        read -p "¿Desea crear otro pull request de todos modos? (s/N): " create_another
        if [[ ! "$create_another" =~ ^[Ss]$ ]]; then
            return 0
        fi
    fi
    
    # Verificar si hay commits locales no enviados
    local remote_branch_exists=$(git ls-remote --heads origin "$current_branch" | wc -l)
    if [ "$remote_branch_exists" -eq 0 ]; then
        warning "La rama '$current_branch' no existe en el repositorio remoto."
        read -p "¿Desea enviar esta rama ahora? (S/n): " push_branch
        
        if [[ ! "$push_branch" =~ ^[Nn]$ ]]; then
            echo "Enviando rama '$current_branch' al remoto..."
            git push -u origin "$current_branch"
            
            if [ $? -ne 0 ]; then
                error "Error al enviar la rama al remoto."
                return 1
            fi
        else
            error "No se puede crear un PR sin enviar la rama al remoto."
            return 1
        fi
    else
        # Verificar si hay commits locales no enviados
        local ahead=$(git rev-list --count @{upstream}..HEAD 2>/dev/null)
        if [ "$ahead" -gt 0 ]; then
            warning "Tiene $ahead commit(s) local(es) que no han sido enviados al remoto."
            read -p "¿Desea enviar estos commits ahora? (S/n): " push_commits
            
            if [[ ! "$push_commits" =~ ^[Nn]$ ]]; then
                echo "Enviando commits pendientes..."
                git push origin "$current_branch"
                
                if [ $? -ne 0 ]; then
                    error "Error al enviar commits."
                    return 1
                fi
            else
                warning "El PR no incluirá los últimos commits locales."
            fi
        fi
    fi
    
    # Título y descripción del PR
    read -p "Título del Pull Request: " pr_title
    
    if [ -z "$pr_title" ]; then
        # Usar el título del último commit como título del PR
        pr_title=$(git log -1 --pretty=%B | head -n 1)
        echo -e "Usando título del último commit: ${CYAN}$pr_title${RESET}"
    fi
    
    echo -e "\nOpciones para la descripción:"
    echo "  1. Descripción simple"
    echo "  2. Incluir lista de commits"
    echo "  3. Usar plantilla"
    read -p "Seleccione una opción [1-3]: " desc_option
    
    case "$desc_option" in
        2)
            # Generar descripción con lista de commits
            local commit_list=$(git log --reverse --pretty=format:"* %s (%h)" "$base_branch".."$current_branch")
            
            echo -e "\nDescripción del PR (Editable):"
            echo -e "## Cambios incluidos\n"
            echo "$commit_list"
            echo -e "\n## Notas adicionales"
            echo "Por favor, revise estos cambios y proporcione feedback."
            
            read -p "¿Editar esta descripción? (s/N): " edit_desc
            
            if [[ "$edit_desc" =~ ^[Ss]$ ]]; then
                # Crear archivo temporal con descripción inicial
                local temp_desc_file=$(mktemp)
                echo -e "## Cambios incluidos\n" > "$temp_desc_file"
                echo "$commit_list" >> "$temp_desc_file"
                echo -e "\n## Notas adicionales" >> "$temp_desc_file"
                echo "Por favor, revise estos cambios y proporcione feedback." >> "$temp_desc_file"
                
                # Abrir editor
                ${EDITOR:-nano} "$temp_desc_file"
                pr_body=$(cat "$temp_desc_file")
                rm "$temp_desc_file"
            else
                pr_body="## Cambios incluidos\n\n$commit_list\n\n## Notas adicionales\nPor favor, revise estos cambios y proporcione feedback."
            fi
            ;;
        3)
            # Usar plantilla si existe
            if [ -n "$PR_TEMPLATE" ]; then
                local temp_pr_file=$(mktemp)
                echo "$PR_TEMPLATE" > "$temp_pr_file"
                
                ${EDITOR:-nano} "$temp_pr_file"
                pr_body=$(cat "$temp_pr_file")
                rm "$temp_pr_file"
            else
                # Plantilla básica
                local temp_pr_file=$(mktemp)
                cat > "$temp_pr_file" << EOF
## Descripción
<!-- Describe los cambios en detalle -->

## Motivación y Contexto
<!-- ¿Por qué es necesario este cambio? ¿Qué problema resuelve? -->

## Tipo de Cambio
<!-- Marque las opciones que apliquen -->
- [ ] Corrección de error (bug fix)
- [ ] Nueva funcionalidad
- [ ] Mejora de rendimiento
- [ ] Refactorización de código
- [ ] Actualización de documentación

## Cómo ha sido probado
<!-- Describa las pruebas que ha realizado -->

## Capturas de pantalla (si aplica)
<!-- Añada capturas de pantalla si es relevante -->

## Notas adicionales
<!-- Cualquier otra información relevante -->
EOF
                
                ${EDITOR:-nano} "$temp_pr_file"
                pr_body=$(cat "$temp_pr_file")
                rm "$temp_pr_file"
            fi
            ;;
        *)
            # Descripción simple
            echo -e "\nIngrese la descripción del PR (termine con ctrl+D en una nueva línea):"
            pr_body=$(cat)
            ;;
    esac
    
    # Opciones adicionales para el PR
    echo -e "\n${BOLD}Opciones adicionales:${RESET}"
    echo "  1. Pull Request regular"
    echo "  2. Solicitar revisores específicos"
    echo "  3. Asignar a usuarios"
    echo "  4. Aplicar etiquetas"
    read -p "Seleccione una opción [1-4]: " option_pr
    
    # Valores para opciones adicionales
    local reviewers=""
    local assignees=""
    local labels=""
    
    case "$option_pr" in
        2)
            echo -e "\nSolicitar revisores (separados por comas):"
            read -p "Nombres de usuario: " reviewers
            ;;
        3)
            echo -e "\nAsignar a usuarios (separados por comas):"
            read -p "Nombres de usuario: " assignees
            ;;
        4)
            echo -e "\nAplicar etiquetas (separadas por comas):"
            read -p "Etiquetas: " labels
            ;;
    esac
    
    # Crear JSON para la solicitud
    local json_data="{
        \"title\": \"$pr_title\",
        \"body\": \"$pr_body\",
        \"head\": \"$current_branch\",
        \"base\": \"$base_branch\"
    }"
    
    # Añadir revisores si se proporcionaron
    if [ -n "$reviewers" ]; then
        # Convertir lista separada por comas a array JSON
        local reviewers_array="[$(echo "$reviewers" | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')]"
        json_data=$(echo "$json_data" | jq --argjson reviewers "$reviewers_array" '. + {reviewers: $reviewers}')
    fi
    
    # Añadir asignados si se proporcionaron
    if [ -n "$assignees" ]; then
        # Convertir lista separada por comas a array JSON
        local assignees_array="[$(echo "$assignees" | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')]"
        json_data=$(echo "$json_data" | jq --argjson assignees "$assignees_array" '. + {assignees: $assignees}')
    fi
    
    # Añadir etiquetas si se proporcionaron
    if [ -n "$labels" ]; then
        # Convertir lista separada por comas a array JSON
        local labels_array="[$(echo "$labels" | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')]"
        json_data=$(echo "$json_data" | jq --argjson labels "$labels_array" '. + {labels: $labels}')
    fi
    
    echo -e "\nCreando Pull Request..."
    
    # Enviar solicitud a la API
    local response=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" -d "$json_data" "$GITHUB_API/repos/$repo_info/pulls")
    
    # Verificar respuesta
    if echo "$response" | grep -q "message"; then
        local error_msg=$(echo "$response" | jq -r '.message')
        
        if [ "$error_msg" = "No commits between $base_branch and $current_branch" ]; then
            error "No hay commits entre la rama base ($base_branch) y la rama actual ($current_branch)."
        elif [ "$error_msg" = "Validation Failed" ]; then
            local validation_errors=$(echo "$response" | jq -r '.errors[].message' 2>/dev/null || echo "Error de validación desconocido")
            error "Error de validación: $validation_errors"
        else
            error "Error al crear el Pull Request: $error_msg"
            echo "$response" | jq '.' 2>/dev/null || echo "$response"
        fi
        return 1
    fi
    
    # Obtener URL del PR creado
    local pr_url=$(echo "$response" | jq -r '.html_url')
    local pr_number=$(echo "$response" | jq -r '.number')
    
    if [ -z "$pr_url" ] || [ "$pr_url" = "null" ]; then
        error "Error al crear el Pull Request. Respuesta:"
        echo "$response" | jq '.' 2>/dev/null || echo "$response"
        return 1
    fi
    
    success "Pull Request #$pr_number creado exitosamente: $pr_url"
    
    # Manejar opciones adicionales (revisores, asignados, etiquetas) si la API inicial no las procesó
    if [ -n "$reviewers" ] || [ -n "$assignees" ] || [ -n "$labels" ]; then
        echo -e "Aplicando opciones adicionales..."
        
        # Añadir revisores (llamada separada requerida)
        if [ -n "$reviewers" ]; then
            local reviewers_json="{\"reviewers\": [$(echo "$reviewers" | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')]}"
            curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" \
                 -H "Accept: application/vnd.github.v3+json" \
                 -d "$reviewers_json" \
                 "$GITHUB_API/repos/$repo_info/pulls/$pr_number/requested_reviewers" > /dev/null
        fi
        
        # Añadir etiquetas si no se procesaron
        if [ -n "$labels" ] && ! echo "$response" | jq -e '.labels' > /dev/null; then
            local labels_json="{\"labels\": [$(echo "$labels" | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')]}"
            curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" \
                 -d "$labels_json" \
                 "$GITHUB_API/repos/$repo_info/issues/$pr_number/labels" > /dev/null
        fi
    fi
    
    # Abrir PR en el navegador
    read -p "¿Abrir el Pull Request en el navegador? (s/N): " open_browser
    if [[ "$open_browser" =~ ^[Ss]$ ]]; then
        if command -v xdg-open &> /dev/null; then
            xdg-open "$pr_url" &> /dev/null
        elif command -v open &> /dev/null; then
            open "$pr_url" &> /dev/null
        else
            echo "No se pudo abrir el navegador automáticamente."
            echo "URL del Pull Request: $pr_url"
        fi
    fi
    
    # Ofrecer opciones adicionales post-creación
    echo -e "\n${BOLD}¿Desea realizar alguna acción adicional?${RESET}"
    echo "  1. Volver a la rama anterior"
    echo "  2. Crear una nueva rama basada en $base_branch"
    echo "  3. Finalizar"
    read -p "Seleccione una opción [1-3]: " post_pr_action
    
    case "$post_pr_action" in
        1)
            # Obtener la rama anterior
            local prev_branch=$(git rev-parse --abbrev-ref @{-1} 2>/dev/null)
            if [ -n "$prev_branch" ] && [ "$prev_branch" != "HEAD" ]; then
                echo "Cambiando a la rama anterior: $prev_branch"
                git checkout "$prev_branch"
            else
                echo "No se pudo determinar la rama anterior."
                read -p "Ingrese el nombre de la rama a la que desea cambiar: " branch_name
                if [ -n "$branch_name" ]; then
                    git checkout "$branch_name"
                fi
            fi
            ;;
        2)
            read -p "Nombre para la nueva rama: " new_branch_name
            if [ -n "$new_branch_name" ]; then
                # Asegurar que estamos en la rama base primero
                git checkout "$base_branch"
                git pull origin "$base_branch"
                # Crear nueva rama
                git checkout -b "$new_branch_name"
                success "Rama '$new_branch_name' creada y activada."
            fi
            ;;
        *)
            echo "Pull Request creado exitosamente."
            ;;
    esac
}


# Función para mostrar el menú principal
show_menu() {
    clear
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${BLUE}  Git Helper - Herramienta avanzada para Git y GitHub${RESET}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════${RESET}"
    
    # Mostrar información básica
    if is_git_repo &>/dev/null; then
        local current_branch=$(git branch --show-current 2>/dev/null)
        local remote_url=$(git config --get remote.origin.url 2>/dev/null)
        local repo_name=$(basename -s .git "$(git rev-parse --show-toplevel 2>/dev/null)")
        
        echo -e "${BOLD}${GREEN}Repositorio actual:${RESET} $repo_name"
        echo -e "${BOLD}${GREEN}Rama actual:${RESET} $current_branch"
        if [ -n "$remote_url" ]; then
            echo -e "${BOLD}${GREEN}Remote:${RESET} $remote_url"
        fi
    fi
    
    echo
    echo -e "${BOLD}${GREEN}-- Operaciones Básicas de Git --${RESET}"
    echo -e "1. Clonar un repositorio"
    echo -e "2. Crear una rama y cambiar a ella"
    echo -e "3. Hacer pull de la rama actual"
    echo -e "4. Hacer un merge de una rama en la rama actual"
    echo -e "5. Ver el log de los commits"
    echo -e "6. Ver el estado del repositorio"
    echo
    echo -e "${BOLD}${GREEN}-- Operaciones Avanzadas de Git --${RESET}"
    echo -e "7. Stash: guardar cambios temporalmente"
    echo -e "8. Aplicar cambios desde stash"
    echo -e "9. Rebase interactivo"
    echo -e "10. Guardar y subir cambios"
    echo -e "11. Resolver conflictos"
    echo
    echo -e "${BOLD}${GREEN}-- Operaciones con GitHub --${RESET}"
    echo -e "12. Listar mis repositorios"
    echo -e "13. Crear un nuevo repositorio en GitHub"
    echo -e "14. Crear un Pull Request"
    echo -e "15. Administrar Pull Requests"
    echo -e "16. Configurar token de GitHub"
    echo
    echo -e "${BOLD}${GREEN}-- Sistema --${RESET}"
    echo -e "17. Configuración"
    echo -e "18. Ayuda"
    echo -e "19. Salir"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════${RESET}"
}

# Función para mostrar la ayuda
show_help() {
    clear
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${BLUE}  Git Helper - Ayuda y Documentación${RESET}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════${RESET}"
    echo
    echo -e "${BOLD}DESCRIPCIÓN:${RESET}"
    echo "  Git Helper es una herramienta interactiva que simplifica las operaciones"
    echo "  más comunes y avanzadas de Git y GitHub, todo desde una interfaz amigable."
    echo
    echo -e "${BOLD}CARACTERÍSTICAS PRINCIPALES:${RESET}"
    echo "  • Gestión intuitiva de ramas, stashes y commits"
    echo "  • Resolución asistida de conflictos de merge"
    echo "  • Integración completa con GitHub (repositorios, PRs)"
    echo "  • Operaciones avanzadas como rebase y cherry-pick simplificadas"
    echo
    echo -e "${BOLD}REQUISITOS:${RESET}"
    echo "  • Git instalado y configurado"
    echo "  • curl y jq para las funciones de GitHub"
    echo "  • Token de acceso personal de GitHub para funciones de API"
    echo
    echo -e "${BOLD}CONSEJOS RÁPIDOS:${RESET}"
    echo "  • Configure su token de GitHub con la opción 16 del menú"
    echo "  • Use la opción 6 para ver el estado detallado de su repositorio"
    echo "  • La opción 11 le ayuda a resolver conflictos paso a paso"
    echo
    echo -e "${BOLD}FLUJO DE TRABAJO RECOMENDADO:${RESET}"
    echo "  1. Clone o cree un repositorio (opciones 1 o 13)"
    echo "  2. Cree una rama para sus cambios (opción 2)"
    echo "  3. Después de hacer commits, cree un Pull Request (opción 14)"
    echo "  4. Gestione sus PRs con la opción 15"
    echo
    echo "Presione Enter para volver al menú principal..."
    read
}

# Función para configuración avanzada
advanced_config() {
    clear
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${BLUE}  Configuración Avanzada${RESET}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════${RESET}"
    echo
    echo -e "${BOLD}Opciones de configuración:${RESET}"
    echo "  1. Configurar editor predeterminado"
    echo "  2. Configurar plantilla para Pull Requests"
    echo "  3. Configurar remote predeterminado"
    echo "  4. Importar/Exportar configuración"
    echo "  5. Volver al menú principal"
    echo
    read -p "Seleccione una opción [1-5]: " config_option
    
    case $config_option in
        1)
            echo -e "\nEditores disponibles:"
            echo "  1. nano (recomendado para principiantes)"
            echo "  2. vim"
            echo "  3. emacs"
            echo "  4. code (VS Code)"
            echo "  5. Otro (especificar)"
            read -p "Seleccione un editor [1-5]: " editor_option
            
            case $editor_option in
                1) EDITOR="nano" ;;
                2) EDITOR="vim" ;;
                3) EDITOR="emacs" ;;
                4) EDITOR="code --wait" ;;
                5) 
                    read -p "Ingrese el comando del editor: " EDITOR
                    ;;
                *) 
                    echo "Opción no válida, se usará el editor predeterminado."
                    ;;
            esac
            
            # Guardar en la configuración global de Git
            git config --global core.editor "$EDITOR"
            echo -e "Editor configurado: ${GREEN}$EDITOR${RESET}"
            ;;
        2)
            echo -e "\nConfigurar plantilla para Pull Requests:"
            echo "Ingrese la plantilla (presione Ctrl+D en una nueva línea para finalizar):"
            PR_TEMPLATE=$(cat)
            
            # Guardar en configuración
            local temp_json=$(mktemp)
            jq --arg template "$PR_TEMPLATE" '.pr_template = $template' "$CONFIG_FILE" > "$temp_json"
            mv "$temp_json" "$CONFIG_FILE"
            
            echo -e "${GREEN}Plantilla guardada correctamente.${RESET}"
            ;;
        3)
            echo -e "\nConfigurando remote predeterminado:"
            read -p "Nombre del remote (por defecto: origin): " DEFAULT_REMOTE
            DEFAULT_REMOTE=${DEFAULT_REMOTE:-origin}
            
            # Guardar en configuración
            local temp_json=$(mktemp)
            jq --arg remote "$DEFAULT_REMOTE" '.default_remote = $remote' "$CONFIG_FILE" > "$temp_json"
            mv "$temp_json" "$CONFIG_FILE"
            
            echo -e "Remote predeterminado configurado: ${GREEN}$DEFAULT_REMOTE${RESET}"
            ;;
        4)
            echo -e "\nImportar/Exportar configuración:"
            echo "  1. Exportar configuración actual"
            echo "  2. Importar configuración"
            read -p "Seleccione una opción [1-2]: " io_option
            
            case $io_option in
                1)
                    read -p "Ruta del archivo para exportar: " export_path
                    export_path=${export_path:-"$HOME/git-helper-config-$(date +%Y%m%d).json"}
                    cp "$CONFIG_FILE" "$export_path"
                    echo -e "Configuración exportada a: ${GREEN}$export_path${RESET}"
                    ;;
                2)
                    read -p "Ruta del archivo a importar: " import_path
                    if [ -f "$import_path" ]; then
                        if jq '.' "$import_path" &>/dev/null; then
                            cp "$import_path" "$CONFIG_FILE"
                            echo -e "${GREEN}Configuración importada correctamente.${RESET}"
                            # Recargar configuración
                            load_config
                        else
                            echo -e "${RED}El archivo no es un JSON válido.${RESET}"
                        fi
                    else
                        echo -e "${RED}Archivo no encontrado.${RESET}"
                    fi
                    ;;
            esac
            ;;
        *)
            # Volver al menú principal
            ;;
    esac
    
    echo
    read -p "Presione Enter para continuar..."
}

# Función principal
main() {
    check_dependencies
    ensure_config_dirs
    load_config
    
    # Bucle principal del programa
    while true; do
        show_menu
        read -p "Seleccione una opción: " choice
        
        case $choice in
            1) clone_repo ;;
            2) create_branch ;;
            3) pull_current_branch ;;
            4) merge_branch ;;
            5) view_commit_log ;;
            6) view_repo_status ;;
            7) stash_changes ;;
            8) apply_stash ;;
            9) interactive_rebase ;;
            10) git_add_commit ;;
            11) resolve_conflicts ;;
            12) list_github_repos ;;
            13) create_github_repo ;;
            14) create_pull_request ;;
            15) manage_pull_requests ;;
            16) configure_github ;;
            17) advanced_config ;;
            18) show_help ;;
            19) 
                echo -e "${GREEN}¡Gracias por usar Git Helper!${RESET}"
                exit 0 
                ;;
            *)
                echo -e "${RED}Opción no válida. Por favor, seleccione una opción del menú.${RESET}"
                ;;
        esac
        
        # Pausa antes de volver al menú
        if [ "$choice" != "18" ]; then  # No pedir Enter después de mostrar ayuda (ya lo pide)
            echo
            read -p "Presione Enter para continuar..."
        fi
    done
}

# Verificar si se ejecuta directamente o se importa como módulo
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Si se ejecuta directamente
    main "$@"
fi