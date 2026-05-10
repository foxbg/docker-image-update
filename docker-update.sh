#!/bin/bash

# docker-update.sh
# A portable script to check and update running Docker containers.

set -e

# --- Defaults & Variables ---
VERSION="1.1.0"
MODE="check"
DRY_RUN=false

# --- Helper Functions ---

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

usage() {
    echo "Docker Image Update Utility v$VERSION"
    echo "Usage: $0 [check | apply] [options]"
    echo ""
    echo "Modes:"
    echo "  check           Check all running containers and list updates (Default)"
    echo "  apply           Pull new images and restart containers/services"
    echo ""
    echo "Options:"
    echo "  --dry-run       Show what would happen without making changes (for 'apply')"
    echo "  -v, --version   Show version information"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Exit Codes:"
    echo "  0               Success (No updates found in 'check' mode)"
    echo "  1               Error occurred"
    echo "  2               Updates available (only in 'check' mode)"
    exit 0
}

check_dependencies() {
    if ! command -v docker &> /dev/null; then
        echo "Error: docker command not found. Please install Docker."
        exit 1
    fi
}

get_remote_config_digest() {
    local image=$1
    local arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="arm" ;;
    esac

    # Capture manifest and any error messages
    local manifest_verbose
    manifest_verbose=$(docker manifest inspect --verbose "$image" 2>&1) || {
        if echo "$manifest_verbose" | grep -qi "toomanyrequests"; then
            echo "RATE_LIMIT_REACHED"
            return
        fi
        return
    }

    # Find the config digest for the current architecture
    local config_digest=$(echo "$manifest_verbose" | \
        grep -A 30 "\"architecture\": \"$arch\"" | \
        grep -A 10 "\"config\":" | \
        grep "\"digest\":" | head -n 1 | sed -E 's/.*"(sha256:[a-f0-9]+)".*/\1/')

    # Fallback for single-arch images
    if [ -z "$config_digest" ]; then
        config_digest=$(echo "$manifest_verbose" | \
            grep -A 15 "\"config\":" | \
            grep "\"digest\":" | head -n 1 | sed -E 's/.*"(sha256:[a-f0-9]+)".*/\1/')
    fi

    echo "$config_digest"
}

update_container() {
    local container_id=$1
    local image=$2
    local is_compose=$3

    if [ "$is_compose" = "true" ]; then
        local project_dir=$(docker inspect "$container_id" --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}')
        
        if [ -n "$project_dir" ] && [ -d "$project_dir" ]; then
            if [ "$DRY_RUN" = "true" ]; then
                log "[DRY-RUN] Would run: cd $project_dir && docker compose pull && docker compose up -d"
            else
                log "Updating Compose service in $project_dir..."
                (cd "$project_dir" && docker compose pull && docker compose up -d)
            fi
        else
            log "Warning: Could not find Compose directory for $container_id. Skipping update."
        fi
    else
        if [ "$DRY_RUN" = "true" ]; then
            log "[DRY-RUN] Would run: docker pull $image (Standalone container $container_id)"
        else
            log "Updating standalone container $container_id ($image)..."
            docker pull "$image"
            log "Image $image pulled. Standalone containers must be restarted manually to apply updates."
        fi
    fi
}

cleanup_images() {
    if [ "$DRY_RUN" = "true" ]; then
        log "[DRY-RUN] Would run: docker image prune -f"
    else
        log "Cleaning up dangling images..."
        docker image prune -f
    fi
}

# --- Argument Parsing ---

while [[ $# -gt 0 ]]; do
    case $1 in
        check|check-updates|list-updates)
            MODE="check"
            shift
            ;;
        apply|apply-updates)
            MODE="apply"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--version)
            echo "Docker Image Update Utility v$VERSION"
            exit 0
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# --- Main Logic ---

check_dependencies

log "Running in mode: $MODE (Dry-run: $DRY_RUN)"
log "Scanning running containers..."

# List all running containers and their images
# Use process substitution to avoid subshell so we can update variables directly
UPDATES_FOUND=0
while IFS=$'\t' read -r container_id image; do
    # Get the local Image ID (which is the local config digest)
    local_config_id=$(docker inspect "$image" --format '{{.Id}}' 2>/dev/null || true)
    
    # Get the remote config digest
    remote_config_id=$(get_remote_config_digest "$image")
    
    if [ "$remote_config_id" = "RATE_LIMIT_REACHED" ]; then
        log "Warning: Docker Hub rate limit reached for $image. Cannot check for updates at this time."
        continue
    fi
    
    if [ -z "$remote_config_id" ] || [ -z "$local_config_id" ]; then
        log "Skipping $image: Could not retrieve remote manifest. Ensure the image name is correct."
        continue
    fi

    if [ "$local_config_id" != "$remote_config_id" ]; then
        log "UPDATE AVAILABLE: $image (Local: ${local_config_id:7:12}, Remote: ${remote_config_id:7:12})"
        UPDATES_FOUND=$((UPDATES_FOUND + 1))
        
        if [ "$MODE" = "apply" ]; then
            is_compose=$(docker inspect "$container_id" --format '{{ if index .Config.Labels "com.docker.compose.project" }}true{{else}}false{{end}}')
            update_container "$container_id" "$image" "$is_compose"
        fi
    else
        if [ "$MODE" = "check" ]; then
            log "Up to date: $image"
        fi
    fi
done < <(docker ps --format "{{.ID}}\t{{.Image}}")

if [ "$MODE" = "apply" ]; then
    cleanup_images
fi

log "Scan complete."

# Handle exit codes
if [ "$MODE" = "check" ] && [ "$UPDATES_FOUND" -gt 0 ]; then
    exit 2
fi

exit 0
