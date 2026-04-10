# Dotfiles

Cross-platform shell configuration with oh-my-posh, zoxide, fzf, and more.

## Structure

```
dotfiles/
├── shared/          # Cross-platform configs
│   └── agnosterplus.omp.json
├── windows/         # Windows (PowerShell)
│   ├── Microsoft.PowerShell_profile.ps1
│   ├── Add-ZoxideIndex.ps1
│   └── setup.ps1
└── macos/           # macOS (Bash / Zsh)
    ├── .zshrc
    ├── .bash_profile
    └── setup.sh
```

## Setup

Clone this repo, then run the platform setup script. It installs dependencies and creates symlinks from the repo files to their expected locations.

### Windows (PowerShell)

```powershell
git clone git@github.com:Pa1eShad0w/dotfiles.git ~/Repos/dotfiles
~/Repos/dotfiles/windows/setup.ps1
```

> Requires **Developer Mode** enabled (Settings → For Developers) for symlink support.

### macOS (Bash/Zsh)

```bash
git clone git@github.com:Pa1eShad0w/dotfiles.git ~/Repos/dotfiles
~/Repos/dotfiles/macos/setup.sh
```

## Symlink Targets

| Source (repo) | Target (system) |
|---|---|
| `shared/agnosterplus.omp.json` | `~/.config/oh-my-posh/agnosterplus.omp.json` |
| `windows/Microsoft.PowerShell_profile.ps1` | `~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1` |
| `macos/.zshrc` | `~/.zshrc` |
| `macos/.bash_profile` | `~/.bash_profile` |

Edit files in the repo, changes take effect immediately. Use `git pull` to sync across machines.
