#!/usr/bin/env bash
set -euo pipefail

# ── Locate repo root (this script lives in <repo>/macos/) ────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

THEME_SOURCE="${REPO_ROOT}/shared/agnosterplus.omp.json"
THEME_TARGET="${HOME}/.config/oh-my-posh/agnosterplus.omp.json"
BACKUP_DIR="${HOME}/profile-backups/$(date +%Y%m%d-%H%M%S)"

SHELL_NAME="$(basename "${SHELL:-}")"
if [[ -z "${SHELL_NAME}" ]]; then
    SHELL_NAME="zsh"
fi

if [[ "${SHELL_NAME}" == "bash" ]]; then
    PROFILE_SOURCE="${REPO_ROOT}/macos/.bash_profile"
    PROFILE_TARGET="${HOME}/.bash_profile"
    SOURCE_HINT="source ~/.bash_profile"
elif [[ "${SHELL_NAME}" == "zsh" ]]; then
    PROFILE_SOURCE="${REPO_ROOT}/macos/.zshrc"
    PROFILE_TARGET="${HOME}/.zshrc"
    SOURCE_HINT="source ~/.zshrc"
else
    printf "WARN: Unsupported shell '%s'. Defaulting to zsh setup.\n" "${SHELL_NAME}" >&2
    PROFILE_SOURCE="${REPO_ROOT}/macos/.zshrc"
    PROFILE_TARGET="${HOME}/.zshrc"
    SOURCE_HINT="source ~/.zshrc"
fi

log()    { printf "\n==> %s\n" "$*"; }
warn()   { printf "WARN: %s\n" "$*" >&2; }

backup_if_exists() {
    local f="$1"
    # Don't back up symlinks — they point to the repo
    if [[ -f "$f" && ! -L "$f" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp "$f" "${BACKUP_DIR}/$(basename "$f")"
    fi
}

restore_file() {
    local target="$1"
    local bak="${BACKUP_DIR}/$(basename "$target")"
    if [[ -f "$bak" ]]; then
        cp "$bak" "$target"
    fi
}

rollback() {
    warn "Setup failed. Rolling back changed files..."
    restore_file "$PROFILE_TARGET"
    restore_file "$THEME_TARGET"
    warn "Rollback complete."
}
trap rollback ERR

create_symlink() {
    local src="$1"
    local dst="$2"
    mkdir -p "$(dirname "$dst")"
    # Remove existing file/symlink at target
    rm -f "$dst"
    ln -s "$src" "$dst"
    printf "  %s -> %s\n" "$dst" "$src"
}

ensure_homebrew() {
    if command -v brew >/dev/null 2>&1; then return; fi
    log "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

ensure_package() {
    local pkg="$1"
    if brew list --formula "$pkg" >/dev/null 2>&1 || brew list --cask "$pkg" >/dev/null 2>&1; then
        printf "Already installed: %s\n" "$pkg"
    else
        printf "Installing: %s\n" "$pkg"
        brew install "$pkg"
    fi
}

log "Preparing backups"
backup_if_exists "$PROFILE_TARGET"
backup_if_exists "$THEME_TARGET"

ensure_homebrew

log "Installing required tools"
ensure_package oh-my-posh
ensure_package git
ensure_package zoxide
ensure_package fzf
ensure_package fd
ensure_package tree
ensure_package bat
if [[ "${SHELL_NAME}" == "bash" ]]; then
    ensure_package bash-completion@2
fi

log "Creating symlinks"
create_symlink "$THEME_SOURCE"   "$THEME_TARGET"
create_symlink "$PROFILE_SOURCE" "$PROFILE_TARGET"

log "Validating oh-my-posh command"
if ! command -v oh-my-posh >/dev/null 2>&1; then
    warn "oh-my-posh not found in PATH yet; open a new terminal."
fi

trap - ERR
log "Done"
printf "Repo:    %s\n" "$REPO_ROOT"
printf "Shell:   %s\n" "$SHELL_NAME"
printf "Profile: %s -> %s\n" "$PROFILE_TARGET" "$PROFILE_SOURCE"
printf "Theme:   %s -> %s\n" "$THEME_TARGET" "$THEME_SOURCE"
printf "Backup:  %s\n" "${BACKUP_DIR}"
printf "Open a new terminal, or run: %s\n" "${SOURCE_HINT}"
