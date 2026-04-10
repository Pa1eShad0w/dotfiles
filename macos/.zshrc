# macOS Zsh startup profile for oh-my-posh + Git quality-of-life.

# ── Homebrew shellenv (Apple Silicon / Intel) ─────────────────────────────
if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# ── Prompt theme ───────────────────────────────────────────────
OMP_THEME="${HOME}/.config/oh-my-posh/agnosterplus.omp.json"
if command -v oh-my-posh >/dev/null 2>&1 && [[ -f "$OMP_THEME" ]]; then
    eval "$(oh-my-posh init zsh --config "$OMP_THEME")"
fi

# ── Useful defaults ───────────────────────────────────────────
export EDITOR="vim"
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced
alias ll='ls -lah'
alias la='ls -A'
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit'
alias gp='git push'

# ── History ─────────────────────────────────────────────────────────
HISTSIZE=5000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt EXTENDED_HISTORY      # record timestamps; fzf Ctrl+R shows time
setopt INC_APPEND_HISTORY    # write immediately; multi-terminal safe
setopt SHARE_HISTORY         # share across sessions
setopt AUTO_PUSHD            # cd pushes onto dir stack (pairs with fzf ALT-C)
setopt PUSHD_IGNORE_DUPS

# ── fzf / zoxide options (export BEFORE both inits) ─────────────────────
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
# _ZO_FZF_OPTS is read by zoxide built-in zi picker.
export _ZO_FZF_OPTS='--no-sort --height 40% --layout=reverse --border --preview "ls -la {}"'
# Use fd as the fzf path/dir walker when available.
if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
    _fzf_compgen_path() { fd --hidden --follow --exclude .git . "$1"; }
    _fzf_compgen_dir()  { fd --type d --hidden --follow --exclude .git . "$1"; }
fi
# Show directory tree in ALT-C preview; use bat for file preview in Ctrl+T.
export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always {} 2>/dev/null || cat {}'"
export FZF_ALT_C_OPTS="--preview 'tree -C {} | head -30 2>/dev/null || ls -la {}'"

# ── zoxide (init AFTER _ZO_FZF_OPTS is exported) ─────────────────────────
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi

# ── fzf keybindings and completion ─────────────────────────────────────
if command -v fzf >/dev/null 2>&1; then
    eval "$(fzf --zsh 2>/dev/null)" || {
        # Fallback for fzf < 0.48.0
        [[ -f "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh" ]] \
            && source "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh"
        [[ -f "$(brew --prefix)/opt/fzf/shell/completion.zsh" ]] \
            && source "$(brew --prefix)/opt/fzf/shell/completion.zsh"
    }
fi

# ── _fzf_comprun: custom preview per command (zsh only) ───────────────────
_fzf_comprun() {
    local command=$1; shift
    case "$command" in
        cd)           fzf --preview 'tree -C {} | head -30' "$@" ;;
        export|unset) fzf --preview "eval 'echo \${}'" "$@" ;;
        ssh)          fzf --preview 'dig {}' "$@" ;;
        *)            fzf --preview 'bat -n --color=always {} 2>/dev/null || cat {}' "$@" ;;
    esac
}

# ── zi: interactive zoxide+fzf directory jump ──────────────────────────
# zoxide 0.9+ registers zi automatically via "zoxide init"; define it here as
# a safe fallback and to guarantee the preview window is always present.
if command -v zoxide >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
    zi() {
        local dir
        dir=$(zoxide query -l | fzf \
            --no-sort \
            --height 40% \
            --layout=reverse \
            --border \
            --preview 'ls -la {}' \
            --preview-window 'right:40%') \
        && z "$dir"
    }
fi