# DMSA - Downloads Management & Sync App

<p align="center">
  <img src="doc/assets/icon.png" alt="DMSA Icon" width="128" height="128">
</p>

<p align="center">
  <strong>Intelligent External Drive Sync with Virtual File System</strong><br>
  macOS Menu Bar App | Dual-Process Architecture | macFUSE VFS
</p>

<p align="center">
  <a href="https://github.com/newstatic/DMSA/releases/latest">
    <img src="https://img.shields.io/github/v/release/newstatic/DMSA?style=flat-square" alt="Latest Release">
  </a>
  <img src="https://img.shields.io/badge/macOS-11.0+-blue?style=flat-square" alt="macOS 11.0+">
  <img src="https://img.shields.io/badge/Swift-5.5+-orange?style=flat-square" alt="Swift 5.5+">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">
</p>

<p align="center">
  English | <a href="README_CN.md">简体中文</a>
</p>

---

## What is DMSA?

DMSA (Downloads Management & Sync App) creates a **virtual file system** that seamlessly merges your local storage with external drives. Access all your files through a single `~/Downloads` folder — whether they're stored locally or on an external drive.

### The Problem

- External drives have large capacity but are slow and not always connected
- Local SSDs are fast but have limited space
- Manually managing files between local and external storage is tedious
- Traditional sync tools copy everything, wasting space

### The Solution

DMSA creates a **smart virtual layer** that:
- Shows **all files** from both local and external in one place
- **Reads directly** from external drive (no copying)
- **Writes locally first**, then syncs to external in background
- **Automatically evicts** old local files when space runs low
- **Works offline** — local files are always accessible

---

## Features

### 🗂️ VFS Smart Merge

Your `~/Downloads` folder becomes a **unified view** of local + external files:

```
~/Downloads (VFS Mount - What you see)
    ├── project.zip      ← Local only (new file)
    ├── movie.mp4        ← External only (large file)
    ├── document.pdf     ← Both (synced)
    └── photos/          ← Mixed contents
```

The actual storage:
```
~/Downloads_Local/           /Volumes/BACKUP/Downloads/
    ├── project.zip              ├── movie.mp4
    ├── document.pdf             ├── document.pdf
    └── photos/                  └── photos/
        └── recent.jpg               ├── recent.jpg
                                     └── archive.jpg
```

### ⚡ Zero-Copy Read

When you open a file that only exists on external drive:
- **No copying** — file is read directly from external
- **No waiting** — instant access to metadata
- **No wasted space** — large files stay on external

### ✍️ Write-Back Sync

When you create or modify a file:
1. **Write to local** — instant, no waiting for external drive
2. **Mark as dirty** — track files needing sync
3. **Background sync** — copy to external when connected
4. **Clear dirty flag** — file is now safely backed up

### 🧹 LRU Eviction

When local space runs low:
1. Find files that exist on **both** local and external
2. Sort by **last access time** (least recently used first)
3. **Delete local copy** — file still accessible via VFS from external
4. **Preserve index** — no re-scanning needed

### 📊 Incremental Index

- **First run**: Full scan of external drive, builds complete index
- **Subsequent runs**: Only scan changed files (fast startup)
- **Batch writes**: 10,000 entries per database transaction
- **50万+ files**: Handles large archives efficiently

### 🔄 FUSE Recovery

- **Sleep/Wake**: Automatic remount after system sleep
- **Crash Recovery**: Service auto-restarts and remounts
- **Signal Handling**: Graceful shutdown on SIGTERM/SIGHUP

### 🔔 Real-time Status

- Menu bar icon shows sync status
- Progress notifications for large operations
- Detailed activity log in app

---

## Architecture

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
│                       System Space (root)                            │
│                        LaunchDaemon Service                          │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │               com.ttttt.dmsa.service                           │  │
│  │                                                                │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐    │  │
│  │  │ VFSManager  │  │ SyncManager │  │     C libfuse       │    │  │
│  │  │  (Actor)    │  │   (Actor)   │  │     Wrapper         │    │  │
│  │  │             │  │             │  │                     │    │  │
│  │  │• FUSE mount │  │• File sync  │  │• fuse_loop_mt()     │    │  │
│  │  │• Smart merge│  │• Scheduling │  │• Multi-threaded     │    │  │
│  │  │• R/W routing│  │• Conflict   │  │• Async callbacks    │    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘    │  │
│  │                                                                │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐    │  │
│  │  │EvictionMgr │  │  ObjectBox  │  │ PrivilegedOps       │    │  │
│  │  │             │  │  Database   │  │                     │    │  │
│  │  │• LRU evict  │  │             │  │• Dir protection     │    │  │
│  │  │• Space mgmt │  │• 50万+ files│  │• ACL management     │    │  │
│  │  │• Batch ops  │  │• Batch write│  │• Permissions        │    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Dual-Process Design

| Component | Process | Privileges | Responsibility |
|-----------|---------|------------|----------------|
| **DMSA.app** | Main app | User | Pure UI, status display, user interaction |
| **DMSAService** | LaunchDaemon | root | VFS + Sync + Database + Privileged operations |

**Benefits:**
- GUI can quit without affecting file access
- Service runs independently with root privileges
- Auto-restart on crash via launchd
- Clear separation of concerns

---

## Directory Structure

| Path | Name | Description |
|------|------|-------------|
| `~/Downloads` | TARGET_DIR | VFS mount point — user's access entry |
| `~/Downloads_Local` | LOCAL_DIR | Local hot data cache (hidden) |
| `/Volumes/BACKUP/Downloads` | EXTERNAL_DIR | External drive full data |

**Flow Examples:**

```
Read movie.mp4 (external only):
  App → ~/Downloads/movie.mp4 → VFS → /Volumes/BACKUP/Downloads/movie.mp4

Write new.txt:
  App → ~/Downloads/new.txt → VFS → ~/Downloads_Local/new.txt
                                  → Background sync → /Volumes/BACKUP/Downloads/new.txt

Delete old.zip:
  App → rm ~/Downloads/old.zip → VFS → Delete from LOCAL_DIR
                                     → Delete from EXTERNAL_DIR
                                     → Remove from index
```

---

## Installation

### Requirements

1. **macOS 11.0+** (Big Sur or later)
2. **macFUSE 5.1.3+** — Download from https://macfuse.github.io/

### Install macFUSE

1. Download macFUSE from https://macfuse.github.io/
2. Open the DMG and run the installer
3. Restart your Mac when prompted
4. Go to **System Settings > Privacy & Security** and allow the kernel extension

### Install DMSA

1. Download `DMSA-x.x.dmg` from [Releases](https://github.com/newstatic/DMSA/releases)
2. Open the DMG and drag DMSA to Applications
3. Launch DMSA from Applications
4. Grant **Full Disk Access** when prompted:
   - System Settings > Privacy & Security > Full Disk Access
   - Add DMSA.app

### First Run

1. DMSA will detect your external drive
2. Configure the sync pair (local ↔ external directories)
3. Initial indexing may take a few minutes for large drives
4. Your `~/Downloads` is now a smart VFS!

---

## Configuration

### Config File

`~/Library/Application Support/DMSA/config.json`

```json
{
  "syncPairs": [
    {
      "id": "...",
      "localDir": "/Users/you/Downloads_Local",
      "externalDir": "/Volumes/BACKUP/Downloads",
      "mountPoint": "/Users/you/Downloads"
    }
  ],
  "eviction": {
    "triggerThreshold": 5368709120,
    "targetFreeSpace": 10737418240,
    "maxFilesPerRun": 100
  }
}
```

### Eviction Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `triggerThreshold` | 5 GB | Start eviction when local cache exceeds this |
| `targetFreeSpace` | 10 GB | Target free space after eviction |
| `maxFilesPerRun` | 100 | Max files to evict per cycle |
| `minFileAge` | 1 hour | Don't evict recently accessed files |

---

## Logs

| Log File | Description |
|----------|-------------|
| `~/Library/Logs/DMSA/app-YYYY-MM-DD.log` | App UI logs |
| `~/Library/Logs/DMSA/service-YYYY-MM-DD.log` | Service logs |
| `~/Library/Logs/DMSA/fuse-YYYY-MM-DD.log` | FUSE C layer logs |

Logs rotate daily and are kept for 7 days.

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Language | Swift 5.5+ |
| UI Framework | SwiftUI + Cocoa |
| VFS | macFUSE + C libfuse wrapper |
| Database | ObjectBox Swift |
| IPC | XPC + DistributedNotificationCenter |
| Build | Xcode 14+ / Swift Package Manager |

---

## Building from Source

```bash
# Clone repository
git clone https://github.com/newstatic/DMSA.git
cd DMSA

# Build Release
cd DMSAApp
xcodebuild -scheme DMSAApp -configuration Release
xcodebuild -scheme com.ttttt.dmsa.service -configuration Release

# Or use the release script
cd ..
./release.sh 2.0
```

---

## Troubleshooting

### VFS not mounting

1. Check macFUSE is installed: `kextstat | grep fuse`
2. Check Full Disk Access is granted
3. Check logs: `tail -f ~/Library/Logs/DMSA/service-*.log`

### Files not syncing

1. Check external drive is connected
2. Check disk permissions
3. View sync status in DMSA menu bar

### Performance issues

1. Initial index can be slow for large drives (50万+ files)
2. Subsequent startups use incremental index (fast)
3. Check if eviction is running: `~/Library/Logs/DMSA/service-*.log`

---

## Documentation

Detailed documentation is in the `doc/` directory:

- `doc/00_README.md` — Documentation index
- `doc/CLAUDE_SESSIONS.md` — Development history
- `SERVICE_FLOW/` — Architecture and flow diagrams

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- [macFUSE](https://macfuse.github.io/) — FUSE for macOS
- [ObjectBox](https://objectbox.io/) — High-performance embedded database
- [Claude](https://claude.ai/) — AI pair programming assistant

---

<p align="center">
  <strong>DMSA v2.0</strong> | 2026-02-03<br>
  Made with ❤️ for seamless external drive management
</p>
