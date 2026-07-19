# NOXORA OPTIMIZER — Changelog

All notable changes are documented here.
Format: [Version] — Date — Description

---

## [1.0.0] — 2026-07-19 — Phase 1: Foundation

### Added
- `Start-Noxora.bat` — UAC-aware batch launcher
  - Detects pwsh.exe / powershell.exe
  - Requests UAC elevation if not Administrator
  - No credentials stored, no internet access

- `Noxora.ps1` — Main entry point
  - Environment validation (OS build, PS version, admin check)
  - Module loading with ordered dependency resolution
  - First-run OWNER account creation workflow
  - Authentication loop with lockout handling
  - Main menu dispatch (placeholder stubs for Phase 2+)
  - Session timeout management
  - Graceful exit with logout

- `Setup-Noxora.ps1` — Environment pre-flight check

- `modules/Noxora.Core.psm1` — Core engine
  - Environment validation (CIM, admin, OS build, architecture)
  - Configuration loading from settings.json
  - Directory initialization with ACL restriction on auth/
  - Action ID and Session ID generators
  - Config file loader for all JSON config files

- `modules/Noxora.Logging.psm1` — Structured logging
  - Log levels: Debug, Info, Pass, Skip, Warn, Fail, Error, Backup, Result, Restore, Audit, Action
  - Separate audit log for authentication events
  - Log rotation by file size
  - Explicit prohibition on logging sensitive data

- `modules/Noxora.Auth.psm1` — OWNER authentication
  - PBKDF2-SHA256 (100,000 iterations, 32-byte random salt)
  - Constant-time hash comparison (timing attack prevention)
  - ACL-restricted credential file (Administrators + SYSTEM only)
  - 5-attempt lockout with exponential backoff (base 30s, 2x multiplier)
  - 60-minute session timeout
  - Audit log for login success, login failed, logout, lockout
  - No plain-text password in any file or log

- `modules/Noxora.UI.psm1` — Terminal UI engine
  - ASCII art NOXORA banner
  - Box-drawing menu system with Unicode chars via [char] codepoints
  - Adaptive layout (auto-detects terminal width)
  - Cyan/Green/Yellow/Red color scheme
  - OWNER authentication screen
  - Main menu with session header
  - Action progress table
  - Confirmation dialog
  - Key-value display helpers

- `modules/Noxora.Session.psm1` — Optimization session tracking
  - Session creation per optimization category
  - Action recording with status, before/after values, restore commands
  - Session summary (applied/skipped/warnings/failed counts)
  - JSON persistence for rollback reference

- `config/settings.json` — Global settings
- `config/protected-processes.json` — 30+ protected process entries
- `config/protected-services.json` — 29 protected service entries
- `config/optional-services.json` — 15 optional service recommendations
- `config/process-rules.json` — Process classification regex rules
- `config/package-rules.json` — AppX/UWP classification and presets
- `config/startup-rules.json` — Startup entry classification
- `config/security-rules.json` — Security scan patterns and indicators

- `tests/Auth.Tests.ps1` — Authentication Pester tests
  - PBKDF2 hash determinism
  - Salt randomness
  - Constant-time comparison
  - Password strength validation
  - Owner account creation
  - Credential file security (no plain text)
  - Login success/failure flows
  - Session lifecycle

- `tests/Safety.Tests.ps1` — Safety guard Pester tests
  - Protected process completeness
  - Protected service completeness
  - Process rule kill permissions
  - Safety settings defaults
  - Prohibited command patterns
  - No hardcoded credentials
  - Module structure requirements
  - Config file JSON validity

### Security
- Credential files restricted to Administrators + SYSTEM via Windows ACL
- PBKDF2-SHA256 with 100,000 iterations for password hashing
- Constant-time comparison prevents timing-based attacks
- All dangerous commands (Invoke-Expression, iex, EncodedCommand, etc.) prohibited by design and verified by Safety tests

### Architecture Decisions
- Box-drawing characters stored via [char] Unicode codepoints (PS5.1 safe)
- All module functions return structured PSCustomObject (not Write-Host only)
- UI layer is the only layer that calls Write-Host
- Data collection, decision, execution, UI, logging all separated

---

## [Upcoming] — Phase 2

- Hardware auto-detection (CPU vendor, GPU vendor, integrated vs. dedicated)
- System Dashboard with real hardware data
- Baseline measurement for before/after comparison
- Report generation
- Noxora.System.psm1
- Noxora.Benchmark.psm1 (baseline)
- Noxora.Reporting.psm1

---

## [Upcoming] — Phase 3

- CPU Performance Optimization (Safe, Gaming, Low Latency profiles)
- GPU Performance Optimization (per-game preference, overlay detection)
- RAM and Memory Optimizer (analysis, safe cleanup, leak detection)
- Process Optimizer (classification, priority management)
- Services Optimizer (dependency graph, safe presets)
- Startup Optimizer (startup cost scoring, safe disable)
