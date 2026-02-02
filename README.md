# DMSA - Downloads Management & Sync App

> Version: 4.9 | macOS Menu Bar App | Dual-Process Architecture

Intelligently syncs local directories with external drives, providing a unified access point through a VFS (Virtual File System).

## Features

- **VFS Smart Merge** — `~/Downloads` displays the union of local + external files
- **Zero-Copy Read** — External files are read directly without copying to local
- **Write-Back** — Writes go to local first, then async-synced to external
- **LRU Eviction** — Automatic local cache management based on access time and index stats
- **Real-time Notifications** — DistributedNotificationCenter pushes sync progress
- **Incremental Index** — Batched index writes (10K per batch), incremental updates on restart
- **FUSE Recovery** — Auto-remount on sleep/wake and crash recovery

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        User Space                                 │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │           DMSA.app (Menu Bar App - User Privileges)         │  │
│  │     GUI + Status Display + ServiceClient (XPC Client)       │  │
│  └────────────────────────────────────────────────────────────┘  │
│                              │ XPC                                │
└──────────────────────────────┼────────────────────────────────────┘
┌──────────────────────────────┼────────────────────────────────────┐
│                        System Space (root)                        │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │          com.ttttt.dmsa.service (LaunchDaemon)              │  │
│  │     VFSManager + SyncManager + PrivilegedOperations         │  │
│  │     ObjectBox Database + C libfuse Wrapper                  │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## Terminology

| Term | Path | Description |
|------|------|-------------|
| TARGET_DIR | `~/Downloads` | VFS mount point, user access entry |
| LOCAL_DIR | `~/Downloads_Local` | Local hot data cache |
| EXTERNAL_DIR | `/Volumes/BACKUP/Downloads` | External drive full data |

## Tech Stack

| Component | Technology |
|-----------|-----------|
| VFS | macFUSE + C libfuse wrapper |
| Database | ObjectBox Swift |
| Sync | Native Swift incremental sync |
| IPC | XPC + DistributedNotificationCenter |
| UI | SwiftUI |

## Building

```bash
cd DMSAApp
xcodebuild -scheme DMSAApp -configuration Release
xcodebuild -scheme com.ttttt.dmsa.service -configuration Release
```

## Requirements

1. **macFUSE 5.1.3+** — https://macfuse.github.io/
2. **Full Disk Access** — System Settings > Privacy & Security

## Configuration

`~/Library/Application Support/DMSA/config.json`

## Logs

`~/Library/Logs/DMSA/app.log`

## Documentation

All project documentation is in the `doc/` directory. See `doc/00_README.md` for an overview of the service flow documents.

---

*DMSA v4.9 | 2026-02-02*
