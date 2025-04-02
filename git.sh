#!/bin/bash

# Colores para mejorar la presentación
RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"

# Archivo de configuración para el token de GitHub
CONFIG_FILE="$HOME/.githelper_config"
GITHUB_API="https://api.github.com"

# Función para cargar la configuración
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# Función para guardar la configuración
save_config() {
    echo "GITHUB_TOKEN=\"$GITHUB_TOKEN\"" > "$CONFIG_FILE"
    echo "GITHUB_USERNAME=\"$GITHUB_USERNAME\"" >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"  # Asegurar que solo el usuario pueda leer el archivo
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

# Función para configurar credenciales de GitHub
configure_github() {
    echo -e "${BLUE}Configuración de GitHub${RESET}"
    read -p "Ingrese su nombre de usuario de GitHub: " GITHUB_USERNAME
    read -sp "Ingrese su token de acceso personal de GitHub: " GITHUB_TOKEN
    echo
    
    save_config
    echo -e "${GREEN}Configuración guardada correctamente.${RESET}"
}

# Función para mostrar el menú
show_menu() {
    clear
    echo -e "${BOLD}${BLUE}═════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${BLUE}  Menú de Comandos Avanzados de Git y GitHub${RESET}"
    echo -e "${BOLD}${BLUE}═════════════════════════════════════════${RESET}"
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
    echo -e "8. Pop stash: recuperar cambios guardados"
    echo -e "9. Rebase interactivo"
    echo -e "10. Cherry-pick commits"
    echo -e "11. Resolver conflictos"
    echo
    echo -e "${BOLD}${GREEN}-- Operaciones con GitHub --${RESET}"
    echo -e "12. Listar mis repositorios"
    echo -e "13. Crear un nuevo repositorio en GitHub"
    echo -e "14. Crear un Pull Request"
    echo -e "15. Ver Pull Requests abiertos"
    echo -e "16. Configurar token de GitHub"
    echo
    echo -e "${BOLD}${GREEN}-- Sistema --${RESET}"
    echo -e "17. Salir"
    echo -e "${BOLD}${BLUE}═════════════════════════════════════════${RESET}"
}

# Función para clonar un repositorio
clone_repo() {
    echo -e "${BLUE}Clonar Repositorio${RESET}"
    read -p "Ingrese la URL del repositorio: " repo_url
    read -p "Directorio destino (dejar en blanco para nombre por defecto): " target_dir
    
    if [ -z "$target_dir" ]; then
        git clone "$repo_url"
    else
        git clone "$repo_url" "$target_dir"
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Repositorio clonado exitosamente.${RESET}"
    else
        echo -e "${RED}Error al clonar el repositorio.${RESET}"
    fi
}

# Función para crear una nueva rama y cambiar a ella
create_and_checkout_branch() {
    echo -e "${BLUE}Crear y Cambiar a Nueva Rama${RESET}"
    read -p "Ingrese el nombre de la nueva rama: " branch_name
    
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${RED}No estás en un repositorio Git.${RESET}"
        return 1
    fi
    
    echo -e "Rama actual: ${YELLOW}$current_branch${RESET}"
    
    git checkout -b "$branch_name"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Rama '$branch_name' creada y activada.${RESET}"
    else
        echo -e "${RED}Error al crear la rama.${RESET}"
    fi
}

# Función para hacer pull de la rama actual
pull_current_branch() {
    echo -e "${BLUE}Pull de la Rama Actual${RESET}"
    
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${RED}No estás en un repositorio Git.${RESET}"
        return 1
    fi
    
    remote=$(git config --get branch.$current_branch.remote)
    if [ -z "$remote" ]; then
        read -p "No hay un remote configurado. Ingrese el nombre del remote (ej. origin): " remote
        if [ -z "$remote" ]; then
            echo -e "${RED}Se requiere un remote.${RESET}"
            return 1
        fi
    fi
    
    echo -e "Haciendo pull de ${YELLOW}$current_branch${RESET} desde ${YELLOW}$remote${RESET}..."
    git pull $remote $current_branch
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Pull completado exitosamente.${RESET}"
    else
        echo -e "${RED}Error al hacer pull.${RESET}"
    fi
}

# Función para hacer merge de una rama en la rama actual
merge_branch() {
    echo -e "${BLUE}Merge de Rama${RESET}"
    
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${RED}No estás en un repositorio Git.${RESET}"
        return 1
    fi
    
    echo -e "Rama actual: ${YELLOW}$current_branch${RESET}"
    
    # Listar todas las ramas disponibles
    echo -e "\nRamas disponibles:"
    branches=$(git branch | sed 's/^..//')
    i=1
    for branch in $branches; do
        echo "$i. $branch"
        i=$((i+1))
    done
    
    read -p "Ingrese el nombre de la rama a mergear: " branch_name
    
    git merge "$branch_name"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Merge completado exitosamente.${RESET}"
    else
        echo -e "${YELLOW}Se detectaron conflictos. Por favor, resuélvelos y luego ejecuta 'git merge --continue'.${RESET}"
    fi
}

# Función para ver el log de los commits
view_commit_log() {
    echo -e "${BLUE}Historial de Commits${RESET}"
    read -p "Número de commits a mostrar (Enter para todos): " num_commits
    
    if [ -z "$num_commits" ]; then
        git log --graph --pretty=format:'%C(red)%h%C(reset) - %C(yellow)%d%C(reset) %C(green)(%cr)%C(reset) %s %C(bold blue)<%an>%C(reset)' --abbrev-commit --all
    else
        git log --graph --pretty=format:'%C(red)%h%C(reset) - %C(yellow)%d%C(reset) %C(green)(%cr)%C(reset) %s %C(bold blue)<%an>%C(reset)' --abbrev-commit --all -n $num_commits
    fi
}

# Función para ver el estado del repositorio
view_repo_status() {
    echo -e "${BLUE}Estado del Repositorio${RESET}"
    git status -s
    
    # Mostrar información adicional
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo -e "\nRama actual: ${YELLOW}$current_branch${RESET}"
        
        ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null)
        behind=$(git rev-list --count HEAD..@{u} 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            if [ $ahead -gt 0 ]; then
                echo -e "Tu rama está ${GREEN}$ahead commit(s) adelante${RESET} del remoto."
            fi
            
            if [ $behind -gt 0 ]; then
                echo -e "Tu rama está ${RED}$behind commit(s) atrás${RESET} del remoto."
            fi
        fi
    fi
}

# Función para guardar cambios temporalmente (stash)
stash_changes() {
    echo -e "${BLUE}Guardar Cambios Temporalmente (Stash)${RESET}"
    read -p "Mensaje descriptivo para el stash (opcional): " stash_message
    
    if [ -z "$stash_message" ]; then
        git stash
    else
        git stash save "$stash_message"
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Cambios guardados en stash exitosamente.${RESET}"
    else
        echo -e "${RED}Error al guardar cambios en stash.${RESET}"
    fi
}

# Función para recuperar cambios del stash
pop_stash() {
    echo -e "${BLUE}Recuperar Cambios del Stash${RESET}"
    
    # Mostrar lista de stashes
    git stash list
    
    read -p "Índice del stash a recuperar (Enter para el último): " stash_index
    
    if [ -z "$stash_index" ]; then
        git stash pop
    else
        git stash pop stash@{$stash_index}
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Cambios recuperados exitosamente.${RESET}"
    else
        echo -e "${RED}Error al recuperar cambios del stash.${RESET}"
    fi
}

# Función para hacer rebase interactivo
interactive_rebase() {
    echo -e "${BLUE}Rebase Interactivo${RESET}"
    echo -e "${YELLOW}¡Advertencia! El rebase modifica la historia de git.${RESET}"
    read -p "¿Cuántos commits atrás desea hacer rebase? " num_commits
    
    if [ -z "$num_commits" ]; then
        echo -e "${RED}Debe especificar un número de commits.${RESET}"
        return 1
    fi
    
    git rebase -i HEAD~$num_commits
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Rebase interactivo completado.${RESET}"
    else
        echo -e "${YELLOW}Rebase interrumpido. Puede continuar con 'git rebase --continue' o abortarlo con 'git rebase --abort'.${RESET}"
    fi
}

# Función para cherry-pick commits
cherry_pick_commits() {
    echo -e "${BLUE}Cherry-pick Commits${RESET}"
    
    # Mostrar commits recientes
    echo -e "Commits recientes:"
    git log --oneline -n 10
    
    read -p "Ingrese el hash del commit que desea aplicar: " commit_hash
    
    if [ -z "$commit_hash" ]; then
        echo -e "${RED}Debe especificar un hash de commit.${RESET}"
        return 1
    fi
    
    git cherry-pick $commit_hash
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Cherry-pick completado exitosamente.${RESET}"
    else
        echo -e "${YELLOW}Se detectaron conflictos. Resuélvalos y luego ejecute 'git cherry-pick --continue'.${RESET}"
    fi
}

# Función para resolver conflictos
resolve_conflicts() {
    echo -e "${BLUE}Herramienta de Resolución de Conflictos${RESET}"
    
    # Verificar si hay conflictos
    if ! git ls-files -u | grep -q .; then
        echo -e "${YELLOW}No se detectaron archivos con conflictos.${RESET}"
        return 0
    fi
    
    # Listar archivos con conflictos
    echo -e "Archivos con conflictos:"
    git diff --name-only --diff-filter=U
    
    # Opciones para resolver
    echo -e "\n1. Usar herramienta visual (mergetool)"
    echo -e "2. Ver archivos con conflictos para edición manual"
    echo -e "3. Aceptar cambios locales para todos los archivos"
    echo -e "4. Aceptar cambios remotos para todos los archivos"
    echo -e "5. Cancelar"
    
    read -p "Seleccione una opción: " conflict_option
    
    case $conflict_option in
        1)
            git mergetool
            ;;
        2)
            for file in $(git diff --name-only --diff-filter=U); do
                echo -e "\n${YELLOW}Mostrando conflictos en: $file${RESET}"
                grep -n -A 3 -B 3 "<<<<<<" "$file"
                read -p "Presione Enter para continuar o 'e' para editar este archivo: " edit_option
                if [ "$edit_option" = "e" ]; then
                    ${EDITOR:-nano} "$file"
                fi
            done
            ;;
        3)
            for file in $(git diff --name-only --diff-filter=U); do
                git checkout --ours "$file"
                git add "$file"
                echo -e "Aceptados cambios locales para: $file"
            done
            echo -e "${GREEN}Cambios locales aplicados. Use 'git commit' para finalizar.${RESET}"
            ;;
        4)
            for file in $(git diff --name-only --diff-filter=U); do
                git checkout --theirs "$file"
                git add "$file"
                echo -e "Aceptados cambios remotos para: $file"
            done
            echo -e "${GREEN}Cambios remotos aplicados. Use 'git commit' para finalizar.${RESET}"
            ;;
        5)
            echo -e "${YELLOW}Resolución de conflictos cancelada.${RESET}"
            ;;
        *)
            echo -e "${RED}Opción no válida.${RESET}"
            ;;
    esac
}

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

# Función para crear un repositorio en GitHub
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
    
    # Verificar respuesta
    if echo "$response" | grep -q "\"name\":\"$repo_name\"" || echo "$response" | grep -q "\"name\":.*\"$repo_name\""; then
        # Extracción más robusta de la URL
        if ! repo_url=$(echo "$response" | grep -o '"html_url":"[^"]*"' | head -1 | sed 's/"html_url":"//;s/"//'); then
            repo_url="$GITHUB_API/repos/$GITHUB_USERNAME/$repo_name"
        fi
        
        echo -e "${GREEN}Repositorio creado exitosamente: $repo_url${RESET}"
        
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
            git branch -M main
            git remote add origin "$repo_url"
            
            echo -e "${YELLOW}Subiendo cambios iniciales al repositorio remoto...${RESET}"
            if ! git push -u origin main; then
                echo -e "${RED}Error al subir cambios al repositorio remoto.${RESET}"
                echo -e "${YELLOW}Puede intentar manualmente con: git push -u origin main${RESET}"
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

# Función para crear un Pull Request
create_pull_request() {
    echo -e "${BLUE}Crear Pull Request${RESET}"
    
    validate_token || return 1
    
    # Verificar si estamos en un repositorio
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}No estás en un repositorio Git.${RESET}"
        return 1
    fi
    
    # Obtener información del repositorio
    current_branch=$(git symbolic-ref --short HEAD)
    origin_url=$(git remote get-url origin 2>/dev/null)
    
    if [ -z "$origin_url" ]; then
        echo -e "${RED}No se encontró un remote 'origin'.${RESET}"
        return 1
    fi
    
    # Extraer owner/repo de la URL de origen
    if echo "$origin_url" | grep -q "github.com"; then
        repo_info=$(echo "$origin_url" | sed -E 's|.*github.com[/:]([^/]+)/([^/.]+)(\.git)?|\1/\2|')
    else
        read -p "No se pudo determinar el repositorio de GitHub. Ingrese en formato 'propietario/repo': " repo_info
    fi
    
    # Solicitar información del PR
    read -p "Rama base (generalmente 'main' o 'master'): " base_branch
    read -p "Título del Pull Request: " pr_title
    read -p "Descripción (opcional): " pr_body
    
    # Crear el PR
    json_data="{\"title\":\"$pr_title\",\"body\":\"$pr_body\",\"head\":\"$current_branch\",\"base\":\"$base_branch\"}"
    
    response=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" -d "$json_data" "$GITHUB_API/repos/$repo_info/pulls")
    
    # Verificar respuesta
    if echo "$response" | grep -q "\"url\":"; then
        pr_url=$(echo "$response" | grep -o "\"html_url\":\"[^\"]*\"" | head -1 | cut -d'"' -f4)
        echo -e "${GREEN}Pull Request creado exitosamente: $pr_url${RESET}"
    else
        error_msg=$(echo "$response" | grep -o "\"message\":\"[^\"]*\"" | cut -d'"' -f4)
        echo -e "${RED}Error al crear el Pull Request: $error_msg${RESET}"
    fi
}

# Función para ver Pull Requests abiertos
view_pull_requests() {
    echo -e "${BLUE}Pull Requests Abiertos${RESET}"
    
    validate_token || return 1
    
    # Obtener información del repositorio
    origin_url=$(git remote get-url origin 2>/dev/null)
    
    if [ -z "$origin_url" ]; then
        read -p "Ingrese el repositorio en formato 'propietario/repo': " repo_info
    else
        if echo "$origin_url" | grep -q "github.com"; then
            repo_info=$(echo "$origin_url" | sed -E 's|.*github.com[/:]([^/]+)/([^/.]+)(\.git)?|\1/\2|')
        else
            read -p "Ingrese el repositorio en formato 'propietario/repo': " repo_info
        fi
    fi
    
    echo -e "Consultando Pull Requests para ${YELLOW}$repo_info${RESET}..."
    
    # Obtener PRs
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API/repos/$repo_info/pulls?state=open")
    
    # Verificar si hay PRs
    if [ "$response" = "[]" ]; then
        echo -e "${YELLOW}No hay Pull Requests abiertos en este repositorio.${RESET}"
        return 0
    fi
    
    # Imprimir PRs
    echo -e "\n${BOLD}Pull Requests abiertos:${RESET}"
    echo "$response" | grep -E '"number"|"title"|"html_url"|"user"|"login"' | \
        sed -E 's/"number": ([0-9]+),/#\1/g' | \
        sed -E 's/"title": "([^"]+)",/  Título: \1/g' | \
        sed -E 's/"html_url": "([^"]+)",/  URL: \1/g' | \
        sed -E 's/"login": "([^"]+)"/  Autor: \1/g' | \
        grep -v "\"user\":" | \
        grep -v "^  *$"
}

# Main loop del menú
load_config

while true; do
    show_menu
    read -p "Seleccione una opción: " choice
    
    case $choice in
        1) clone_repo ;;
        2) create_and_checkout_branch ;;
        3) pull_current_branch ;;
        4) merge_branch ;;
        5) view_commit_log ;;
        6) view_repo_status ;;
        7) stash_changes ;;
        8) pop_stash ;;
        9) interactive_rebase ;;
        10) cherry_pick_commits ;;
        11) resolve_conflicts ;;
        12) list_github_repos ;;
        13) create_github_repo ;;
        14) create_pull_request ;;
        15) view_pull_requests ;;
        16) configure_github ;;
        17) echo -e "${GREEN}Saliendo...${RESET}"; exit 0 ;;
        *) echo -e "${RED}Opción no válida${RESET}" ;;
    esac
    
    echo
    read -p "Presione Enter para continuar..."
done