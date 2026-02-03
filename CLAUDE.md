# DMSA Project Memory Document

> This document serves as persistent cross-session context for Claude Code.
> Detailed session records: `doc/CLAUDE_SESSIONS.md`
> Version: 5.5 | Updated: 2026-02-02

---

## Quick Context

Reference when the user mentions:

| User says | Refers to |
|-----------|-----------|
| "app" / "DMSA" | macOS menu bar app `DMSA.app` |
| "sync" | Native incremental sync, one-way LOCAL → EXTERNAL |
| "disk" | External drive (configurable, e.g. BACKUP, PORTABLE) |
| "VFS" | Virtual file system layer, FUSE mount |
| "LOCAL_DIR" | Local hot data directory `~/Downloads_Local`, not directly accessed by user |
| "EXTERNAL_DIR" | External drive backend `/Volumes/{DiskName}/Downloads/`, full data source |
| "TARGET_DIR" | VFS-mounted `~/Downloads`, user's sole access point |
| "Downloads_Local" | Alias for LOCAL_DIR |
| "virtual Downloads" | Alias for TARGET_DIR |
| "EXTERNAL" | Short for EXTERNAL_DIR |
| "config" | JSON config file `~/Library/Application Support/DMSA/config.json` |
| "database" | ObjectBox database `~/Library/Application Support/DMSA/Database/` |
| "eviction" | LRU eviction mechanism, cleans local cache based on access time |
| "version file" | `.FUSE/db.json`, stores file tree version and metadata |
| "tree version" | Version number of file tree state, used for change detection |
| "log" | `~/Library/Logs/DMSA/app.log` |
| "status bar" | macOS top menu bar icon |
| "build" | Xcode build or `swift build` |
| "dirty data" | Files written to LOCAL_DIR but not yet synced to EXTERNAL_DIR |
| "smart merge" | TARGET_DIR shows union of LOCAL_DIR + EXTERNAL_DIR |
| "Service" | `DMSAService` unified background service (root privileges) |
| "XPC" | Communication mechanism between App and Service |
| "ServiceClient" | App-side XPC client `ServiceClient.swift` |
| "pbxproj_tool" | Xcode project management tool `pbxproj_tool.rb` (Ruby), supports list/add/remove/check/fix/smart-fix |
| "smart-fix" | pbxproj_tool smart repair command, auto-detects and adds missing files |

**Addition criteria:**
- User repeatedly uses a term to refer to a specific file/component
- New important module/feature added
- Confusing concepts discovered

---

## Project Info

| Property | Value |
|----------|-------|
| **Project Name** | Delt macOS Sync App (DMSA) |
| **Project Path** | `/Users/ttttt/Documents/xcodeProjects/DMSA` |
| **Bundle ID** | `com.ttttt.dmsa` |
| **Min OS Version** | macOS 11.0 |
| **Current Version** | 4.9 |
| **Last Updated** | 2026-02-02 |

---

## Tech Stack

```
Language: Swift 5.5+
Framework: Cocoa, Foundation, SwiftUI
VFS: macFUSE 5.1.3+ (C libfuse wrapper)
Storage: ObjectBox (high-performance embedded database)
Sync: Native Swift sync engine
Build: Xcode / Swift Package Manager
Platform: macOS (arm64 / x86_64)
Type: Menu bar app (LSUIElement)
Architecture: Dual-process (App + Service)
```

---

## Core Architecture (v4.8 - Pure UI + Distributed Notifications)

### System Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User Space                                   │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    DMSA.app (Menu Bar App)                      │  │
│  │                      Normal User Privileges                     │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────┐   │  │
│  │  │   GUI   │  │Settings │  │ Status  │  │  ServiceClient  │   │  │
│  │  │ Manager │  │  View   │  │ Display │  │  (Unified XPC)  │   │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                    │                                 │
│                        XPC Channel │                                 │
│                                    ▼                                 │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                       System Space                                   │
│                        LaunchDaemon (root)                          │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │               com.ttttt.dmsa.service (Unified Service)         │  │
│  │                                                                │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐    │  │
│  │  │ VFSManager  │  │ SyncManager │  │ PrivilegedOperations│    │  │
│  │  │  (Actor)    │  │   (Actor)   │  │     (Static)        │    │  │
│  │  │             │  │             │  │                     │    │  │
│  │  │• FUSE mount │  │• File sync  │  │• Dir protection     │    │  │
│  │  │• Smart merge│  │• Scheduling │  │• ACL management     │    │  │
│  │  │• R/W routing│  │• Conflict   │  │• Permissions        │    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Dual-Process Components

| Component | Process ID | Privileges | Responsibility |
|-----------|-----------|------------|----------------|
| **DMSA.app** | Main app | User | Pure UI, status display, user interaction |
| **DMSAService** | `com.ttttt.dmsa.service` | root | VFS + Sync + Privileged + Data management |

### Architecture Benefits

1. **GUI exit doesn't affect core service**: Unified service keeps running, files always accessible
2. **Simplified XPC**: Single XPC connection, reduced complexity
3. **Root privileges**: Single LaunchDaemon solves all permission issues
4. **Auto-recovery**: launchd auto-restarts crashed service
5. **Clear separation**: App = UI, Service = Business logic

---

## Directory Structure

```
DMSA/
├── DMSAApp/
│   ├── DMSAApp.xcodeproj/         # Xcode project
│   ├── DMSAApp/                    # Main app (pure UI)
│   │   ├── App/AppDelegate.swift   # Lifecycle management
│   │   ├── Models/                 # Data models
│   │   ├── Services/               # 10 service files
│   │   │   ├── ServiceClient.swift # XPC client (core)
│   │   │   ├── ConfigManager.swift
│   │   │   ├── DiskManager.swift
│   │   │   └── VFS/FUSEManager.swift
│   │   ├── UI/                     # SwiftUI views
│   │   └── Utils/                  # Utilities
│   │
│   ├── DMSAService/                # Unified service (business logic)
│   │   ├── main.swift
│   │   ├── ServiceImplementation.swift
│   │   ├── VFS/                    # VFS module
│   │   ├── Sync/                   # Sync module
│   │   ├── Data/                   # Data management
│   │   ├── Monitor/                # File/disk monitoring
│   │   └── Privileged/             # Privileged operations
│   │
│   └── DMSAShared/                 # Shared code
│       ├── Protocols/              # XPC protocols
│       ├── Models/                 # Shared models
│       └── Utils/                  # Shared utilities
│
├── doc/                            # Documentation
├── CLAUDE.md                       # This document (project memory)
└── README.md                       # Project introduction
```

---

## Key Files

### Main App (DMSAApp) - 10 Service Files

| File | Purpose |
|------|---------|
| `ServiceClient.swift` | **XPC client** (core, all business calls go through this) |
| `ConfigManager.swift` | Configuration management |
| `DatabaseManager.swift` | In-memory cache (data fetched from Service) |
| `DiskManager.swift` | Disk events + UI callbacks |
| `AlertManager.swift` | UI alerts |
| `VFS/FUSEManager.swift` | macFUSE detection/install guide |

### Unified Service (DMSAService)

| File | Purpose |
|------|---------|
| `ServiceImplementation.swift` | XPC protocol implementation |
| `VFS/VFSManager.swift` | VFS Actor, FUSE mount management |
| `VFS/EvictionManager.swift` | LRU eviction management |
| `Sync/SyncManager.swift` | Sync scheduling |
| `Sync/NativeSyncEngine.swift` | Sync engine core |
| `Data/ServiceDatabaseManager.swift` | Database management |

### Shared Code (DMSAShared)

| File | Purpose |
|------|---------|
| `DMSAServiceProtocol.swift` | Unified XPC protocol |
| `Constants.swift` | Global constants |

---

## Core Flows

**Smart Merge (readdir):**
```
TARGET_DIR = LOCAL_DIR ∪ EXTERNAL_DIR (union of both sides)
```

**Read Flow (zero-copy):**
```
Read request → LOCAL_DIR exists? → Yes → Read from LOCAL_DIR
                    ↓ No
            EXTERNAL_DIR exists? → Yes → Redirect read
                    ↓ No
            Return error
```

**Write Flow (Write-Back):**
```
Write request → Write to LOCAL_DIR → Mark isDirty → Return success
                                        ↓ (async)
                               EXTERNAL connected? → Sync → Clear isDirty
```

**Eviction Flow (LRU):**
```
localSize > threshold → Get candidates (BOTH + non-dirty + sorted by access time)
                            ↓
                Verify EXTERNAL exists → Delete LOCAL file → Update to externalOnly
```

---

## Build Commands

```bash
# Xcode build
cd /Users/ttttt/Documents/xcodeProjects/DMSA/DMSAApp
xcodebuild -scheme DMSAApp -configuration Release

# View logs
tail -f ~/Library/Logs/DMSA/app.log
```

---

## Config Paths

| Purpose | Path |
|---------|------|
| Config file | `~/Library/Application Support/DMSA/config.json` |
| Database | `~/Library/Application Support/DMSA/Database/` |
| Log | `~/Library/Logs/DMSA/app.log` |
| LaunchDaemon | `/Library/LaunchDaemons/com.ttttt.dmsa.service.plist` |

---

## Memory Collection Process

> **Trigger**: User says "collect memory" or similar

### Steps

1. **Summarize current session**
   - Review all conversation content
   - Extract completed tasks, modified files, key code

2. **Extract knowledge**
   - Design decisions and rationale
   - Problems encountered and solutions
   - New terminology mappings

3. **Read session attributes**
   - Run `ls -lt ~/.claude/projects/-Users-ttttt-Documents-xcodeProjects-DMSA/*.jsonl | head -1`
   - Extract Session ID (first 8 chars) from filename
   - Record date

4. **Check merge conditions**
   - Review existing session records
   - Determine if same-feature historical sessions can be merged
   - See "Session Merge Strategy" below

5. **Update memory files**
   - Update session index table
   - Update detailed session records (write to `doc/CLAUDE_SESSIONS.md`)
   - Update quick context table (if new terms)

6. **Notify user on completion**
   - Modify files directly, inform user when done

**Error handling:** If collection fails, inform user of specific error, don't make partial changes

---

## Session Merge Strategy

**Principle**: Merge by "feature" — multiple sessions for the same feature merge into one record

**Rules:**
1. **Same-feature criteria**: Sessions modifying the same module/implementing the same feature
2. **Time span**: Can merge across days if same feature
3. **After merge**: Don't keep original sessions separately, merge into one

**Content merge rules:**
- Task list: Merge and deduplicate
- Problems & solutions: Keep all
- Modified files: Merge and deduplicate
- Key code: Keep final version

---

## Collection Checklist

- [ ] Session index table updated
- [ ] Detailed record includes design rationale
- [ ] Detailed record includes problems & solutions
- [ ] Checked for mergeable same-feature sessions
- [ ] Quick context table updated (if new terms)

---

## Session Records

> Detailed records: `doc/CLAUDE_SESSIONS.md`

### Session Index

| Session ID | Date | Title | Summary |
|------------|------|-------|---------|
| 505f841a | 2026-01-24 | v4.5 Build Fix | Fixed type errors, restored ConfigManager, added shared models |
| eae6e63e | 2026-01-26 | Code Signing Fix | Fixed Service Team ID, macFUSE Library Validation |
| 2a099f6b | 2026-01-26 | C FUSE Wrapper | libfuse C implementation, fixed permissions and protection |
| e4bd3c09 | 2026-01-27 | MD Doc Cleanup | Deleted 13 outdated docs, kept 4 core docs |
| 50877371 | 2026-01-27 | SERVICE_FLOW Docs | Created 19 flow documents, complete architecture design |
| 50877371 | 2026-01-27 | v4.9 Code Changes (P0-P3) | State mgmt/VFS blocking/notifications/error codes/startup checks/conflict detection/log format |
| 50877371 | 2026-01-27 | UI Design Spec | 21_ui_design_spec.md + HTML prototype |
| 4f263311 | 2026-01-27 | App Modification Plan + P0-P2 Fix | Code review + App-side P0-P2 fixes |
| 4f263311 | 2026-01-27 | UI File Cleanup + pbxproj Tool | Deleted 14 old UI files + created Xcode project mgmt tool |
| 4f263311 | 2026-01-28 | Ruby xcodeproj Migration | Python pbxproj had bugs, switched to Ruby xcodeproj |
| 7ec270c8 | 2026-01-28 | DMSAApp Build Fix | Fixed P0 type errors, SyncStatus enum, Color extension |
| 7ec270c8 | 2026-01-28 | pbxproj_tool Improvements | Ruby encoding fix + smart-fix command |
| 7ec270c8 | 2026-01-28 | UI + App Feature Audit | Generated verification reports |
| 7ec270c8 | 2026-01-28 | i18n Fix + Cleanup | Added 150+ missing localization keys, deleted 78 unused keys |
| 7ec270c8 | 2026-01-28 | Disk State Sync Fix | DashboardView & DisksPage state out-of-sync issue |
| 7ec270c8 | 2026-01-28 | File-level Sync/Eviction Records | ServiceSyncFileRecord entity + XPC + UI display |
| c2bc39ee | 2026-02-02 | Build/i18n/Decode Fix | pbxproj path fix, PBXVariantGroup fix, SyncHistory CodingKeys fix |
| b6fc182a | 2026-02-02 | Persistence+Index+Eviction+Log+FUSE | ActivityRecord persistence, incremental index, batch writes, eviction logic fix, log rotation, FUSE recovery |
| 0d89290c | 2026-02-02 | Ownership+Installer+EnvVar+Release | VFS ownership fix, ServiceInstaller plist refactor, remove DMSA_USER_HOME env vars, setUserHome XPC gate, release.sh, v2.0 GitHub release |
| 4c07df08 | 2026-02-02 | FUSE Exit Diagnostics | Signal handlers + post-exit diagnostics in fuse_wrapper.c, Swift-side pre-recovery diagnostics, v2.0 release rebuild |
| 0833e23d | 2026-02-03 | FUSE Blocking+Symlink+Delete Fix | cp -rf blocking fix (throttled batch atime), symlink deadlock fix (fuse_loop_mt), delete flow optimization (pending_delete) |
| (current) | 2026-02-03 | Sync Lock + UI Fix | Sync/eviction file locking (EBUSY), onFileCreated trigger sync fix, diskConnected resumeSync fix, Logger history load, sidebar fixed width |

---

## Known Issues & Fixes

### UI Freeze (2026-01-21 Fixed)

**Symptom**: UI freezes after clicking sync

**Root cause**: Progress callbacks too frequent

**Fix**:
- Progress callback throttle 100ms
- Batch log refresh
- Async data loading

---

## Notes

1. **First-time setup**:
   - Detect if ~/Downloads exists
   - If yes, rename to ~/Downloads_Local
   - Create FUSE mount point at ~/Downloads

2. **Permission requirements**:
   - macFUSE 5.1.3+ (download from https://macfuse.github.io/)
   - Full Disk Access (TCC)

3. **Design principles**:
   - App is UI-only, contains no business logic
   - Service is the brain — all sync, VFS, data management lives there
   - XPC is the bridge — App communicates via ServiceClient

---

**Expected behaviors:**
- DMSAShared files appearing in two targets is **normal** (shared code)
- Build artifacts (.app, .service) not existing is **normal** (generated after build)

---

*Document maintenance: Update session index after each session, write detailed records to doc/CLAUDE_SESSIONS.md*
