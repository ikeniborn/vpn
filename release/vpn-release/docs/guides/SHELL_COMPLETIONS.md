# Shell Completion Scripts

The VPN CLI supports shell completion scripts for all major shells. These scripts provide command and argument completion when you press Tab.

## Available Shells

- **Bash** - Linux/macOS default shell
- **Zsh** - macOS default shell (modern versions)
- **Fish** - User-friendly shell
- **PowerShell** - Windows and cross-platform PowerShell
- **Elvish** - Modern shell with advanced features

## Installation

### Generate Completion Scripts

Use the `vpn completions` command to generate completion scripts:

```bash
# Generate for your shell (saves to file)
vpn completions bash -o ~/.local/share/bash-completion/completions/vpn
vpn completions zsh -o ~/.local/share/zsh/site-functions/_vpn
vpn completions fish -o ~/.config/fish/completions/vpn.fish
vpn completions power-shell -o ~/.config/powershell/completions/vpn.ps1

# Or output to stdout for manual handling
vpn completions bash > vpn-completion.bash
```

### Shell-Specific Installation

#### Bash

```bash
# Method 1: System-wide (requires sudo)
sudo vpn completions bash -o /usr/share/bash-completion/completions/vpn

# Method 2: User-local
mkdir -p ~/.local/share/bash-completion/completions
vpn completions bash -o ~/.local/share/bash-completion/completions/vpn

# Method 3: Manual sourcing (add to ~/.bashrc)
vpn completions bash > ~/.vpn-completion.bash
echo 'source ~/.vpn-completion.bash' >> ~/.bashrc
```

#### Zsh

```bash
# Method 1: System-wide (requires sudo)
sudo vpn completions zsh -o /usr/local/share/zsh/site-functions/_vpn

# Method 2: User-local (make sure ~/.local/share/zsh/site-functions is in $fpath)
mkdir -p ~/.local/share/zsh/site-functions
vpn completions zsh -o ~/.local/share/zsh/site-functions/_vpn

# Method 3: Manual sourcing (add to ~/.zshrc)
vpn completions zsh > ~/.vpn-completion.zsh
echo 'source ~/.vpn-completion.zsh' >> ~/.zshrc
```

#### Fish

```bash
# Fish auto-loads from this directory
mkdir -p ~/.config/fish/completions
vpn completions fish -o ~/.config/fish/completions/vpn.fish
```

#### PowerShell

```powershell
# Create profile directory if it doesn't exist
New-Item -Type Directory -Path (Split-Path $PROFILE) -Force

# Generate and save completion script
vpn completions power-shell -o "$HOME/vpn-completion.ps1"

# Add to PowerShell profile
Add-Content $PROFILE ". `"$HOME/vpn-completion.ps1`""
```

## Usage

After installation, restart your shell or source your shell's configuration file. Then use Tab completion:

```bash
vpn <Tab>                    # Shows all available commands
vpn users <Tab>              # Shows user subcommands  
vpn users create <Tab>       # Shows options for create command
vpn install --protocol <Tab> # Shows available protocols
```

## Advanced Features

The completion scripts provide intelligent completion for:

- **Commands and subcommands** - All CLI commands and their subcommands
- **Options and flags** - Short (-h) and long (--help) options
- **Values** - Enum values like protocols, formats, shells
- **Files and paths** - File path completion where appropriate

## Examples

```bash
# Command completion
vpn us<Tab> → vpn users
vpn users cr<Tab> → vpn users create

# Option completion  
vpn install --pr<Tab> → vpn install --protocol
vpn users list --st<Tab> → vpn users list --status

# Value completion
vpn install --protocol <Tab> → vless shadowsocks trojan vmess
vpn completions <Tab> → bash zsh fish power-shell elvish
```

## Troubleshooting

### Completions Not Working

1. **Check installation path** - Make sure the completion file is in the correct location for your shell
2. **Restart shell** - Source your configuration file or restart your terminal
3. **Check permissions** - Ensure the completion file is readable
4. **Verify shell support** - Some shells require specific configuration

### Bash Completion Issues

```bash
# Check if bash-completion is installed
which bash-completion

# Check if completion files are being loaded
complete -p | grep vpn

# Manual debug - source the file directly
source ~/.vpn-completion.bash
```

### Zsh Completion Issues

```bash
# Check fpath contains the completion directory
echo $fpath

# Reload zsh completions
autoload -U compinit && compinit

# Check if completion is loaded
which _vpn
```

## Updating Completions

When you update the VPN CLI, regenerate completion scripts to ensure they include new commands and options:

```bash
# Regenerate for your shell
vpn completions bash -o ~/.local/share/bash-completion/completions/vpn
# Or wherever you installed them originally
```