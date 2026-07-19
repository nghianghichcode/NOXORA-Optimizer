# NOXORA OPTIMIZER

A professional Windows performance analysis and optimization toolkit for technicians.

## Overview

NOXORA OPTIMIZER is a terminal-based Windows system optimization tool built entirely
in PowerShell. It provides deep system analysis, hardware detection, process management,
service optimization, security scanning, and game performance boosting — all with a
full backup-and-restore safety model.

## Requirements

- Windows 10 (Build 18362+) or Windows 11
- PowerShell 5.1 (built-in) or PowerShell 7+ (recommended)
- Administrator privileges
- No external dependencies, no internet connection required

## Quick Start

1. Right-click `Start-Noxora.bat` and select **Run as administrator**
   (or double-click — the launcher requests UAC automatically)

2. On first run, create your OWNER account (username + password)

3. Log in and use the menu to analyze and optimize your system

## Architecture

```
NOXORA-Optimizer/
├── Start-Noxora.bat      — Launcher (UAC-aware)
├── Noxora.ps1            — Main entry point
├── Setup-Noxora.ps1      — Pre-flight environment check
│
├── config/               — JSON configuration files
├── modules/              — PowerShell modules (one per feature area)
├── data/                 — Runtime data (logs, sessions, backups)
└── tests/                — Pester unit tests
```

## Module Map

| Module | Purpose |
|--------|---------|
| Noxora.Core | Environment validation, config loading, path management |
| Noxora.UI | Terminal UI, banner, menus, color output |
| Noxora.Auth | OWNER authentication, PBKDF2 hashing, session management |
| Noxora.Logging | Structured logging, audit trail, log rotation |
| Noxora.Session | Optimization session tracking, action history |
| Noxora.System | Hardware detection, system dashboard (Phase 2) |
| Noxora.CPU | CPU analysis and optimization (Phase 3) |
| Noxora.GPU | GPU analysis and optimization (Phase 3) |
| Noxora.Memory | RAM analysis and optimization (Phase 3) |
| Noxora.Process | Process analyzer and optimizer (Phase 3) |
| Noxora.Services | Services optimizer with dependency graph (Phase 3) |
| Noxora.Startup | Startup entry analysis and management (Phase 3) |
| Noxora.Debloat | AppX / UWP debloater (Phase 4) |
| Noxora.Network | Network analyzer and optimizer (Phase 4) |
| Noxora.Backup | Backup creation and management (Phase 4) |
| Noxora.Restore | Rollback engine (Phase 4) |
| Noxora.GameBoost | Smart game boost with auto-restore (Phase 5) |
| Noxora.Thermal | Temperature and throttling analysis (Phase 5) |
| Noxora.Benchmark | Before/after benchmarking (Phase 5) |
| Noxora.Security | Security scanner — persistence, connections, files (Phase 6) |
| Noxora.Defender | Microsoft Defender integration (Phase 6) |
| Noxora.Persistence | Persistence mechanism scanner (Phase 6) |
| Noxora.Quarantine | File quarantine manager (Phase 6) |
| Noxora.Reporting | Report generation (Phase 2) |

## Security Model

- **Single OWNER account** — no guest mode, no multi-user
- **PBKDF2-SHA256** password hashing (100,000 iterations, 32-byte salt)
- **No plain-text passwords** stored anywhere
- **ACL-protected** credential files (Administrators + SYSTEM only)
- **5 attempt lockout** with exponential backoff
- **60-minute session timeout** with re-authentication
- **Audit log** for all login events

## Safety Principles

Every action follows this workflow:
```
Analyze → Explain → Preview → Backup → Confirm → Apply → Verify → Restore
```

NOXORA never:
- Applies tweaks blindly
- Reports success when a command fails
- Disables Windows Defender or Firewall
- Disables Windows Update permanently
- Kills Windows core processes
- Modifies System32, WinSxS, or DriverStore
- Uses Invoke-Expression or downloads code

## Running Tests

```powershell
# Run all tests
Invoke-Pester .\tests\ -Output Detailed

# Run specific test file
Invoke-Pester .\tests\Safety.Tests.ps1 -Output Detailed
Invoke-Pester .\tests\Auth.Tests.ps1   -Output Detailed
```

## Development Phases

- **Phase 1** (Current) — Foundation, Auth, UI, Logging, Core
- **Phase 2** — Hardware detection, Dashboard, Baseline
- **Phase 3** — CPU, GPU, RAM, Process, Services, Startup
- **Phase 4** — Debloater, Network, Backup, Restore
- **Phase 5** — Game Boost, Thermal, Benchmark
- **Phase 6** — Security Center, Defender, Persistence, Quarantine
- **Phase 7** — Tests, Compatibility, Documentation

## License

Proprietary. All rights reserved.
