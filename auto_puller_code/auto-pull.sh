#!/bin/bash

# ==========================================
# DYNAMIC SETUP & LOGGING
# ==========================================
# Get the exact directory where this script is located, regardless of where cron runs it from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

# Ensure the config file exists before proceeding
if [ ! -f "$CONFIG_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Error - Configuration file not found at $CONFIG_FILE"
    exit 1
fi

# Load variables from config.env
source "$CONFIG_FILE"
LOG_PATH="$SCRIPT_DIR/$LOG_FILE"

# Apply SSH Key if configured
if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
    export GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH -o IdentitiesOnly=yes"
fi

# Helper function to write logs with timestamps
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_PATH"
}

# Helper function to write debug logs
debug_log() {
    local DEBUG_PATH="$SCRIPT_DIR/${DEBUG_LOG_FILE:-debug.logs}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG]: $1" >> "$DEBUG_PATH"
}

# ==========================================
# GIT AUTO-PULL LOGIC
# ==========================================
# Navigate to your project directory
cd "$PROJECT_DIR" || { log "Error: Directory $PROJECT_DIR not found"; exit 1; }

# Capture and log debug information to verify connections
REMOTE_URL=$(git config --get remote.origin.url)
debug_log "--- Cron Execution Started ---"
debug_log "Project Path: $PROJECT_DIR"
debug_log "GitHub Link: $REMOTE_URL"

# Fetch the latest metadata from GitHub
git fetch origin > /dev/null 2>&1

# Get the commit hashes
LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse origin/"$BRANCH")

# Compare the hashes
if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
    log "New changes found on GitHub (Branch: $BRANCH). Pulling code..."

    # Pull the code and append the output to our log file
    if git pull --rebase origin "$BRANCH" >> "$LOG_PATH" 2>&1; then
        log "Code successfully pulled."

        # --- Docker Deployment ---
        if [ "$ENABLE_DOCKER" = "true" ]; then
            log "Rebuilding and restarting Docker containers..."
            if eval "$DOCKER_COMMAND" >> "$LOG_PATH" 2>&1; then
                log "Docker deployment successful."
            else
                log "Error: Docker deployment failed. Check logs above."
            fi
        fi

        log "Update process complete."
    else
        log "Error: Git pull failed. Please resolve conflicts manually."
    fi
else
    # Uncomment the line below if you want a log entry every time it checks (can spam your logs)
    # log "Already up to date."
    : 
fi
