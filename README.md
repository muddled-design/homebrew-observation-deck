# Homebrew Tap for Observation Deck

Floating macOS dashboard that monitors all active Claude Code sessions in real time.

## Install

```bash
brew tap muddled-design/observation-deck https://github.com/muddled-design/homebrew-observation-deck
brew install observation-deck
```

This will:
1. Build ClaudeMonitor from source
2. Install the `.app` bundle
3. Automatically configure Claude Code hooks for real-time status

## Launch

```bash
open $(brew --prefix)/opt/observation-deck/ClaudeMonitor.app
```

## Uninstall

```bash
# Remove hooks from Claude Code settings
$(brew --prefix)/share/observation-deck/install-hooks.sh --uninstall

# Uninstall the app
brew uninstall observation-deck
brew untap muddled-design/observation-deck
```
