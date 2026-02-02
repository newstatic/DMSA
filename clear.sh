#!/bin/bash

# Stop and remove DMSA service

# Kill dmsa processes
ps aux | grep dmsa | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null

# Remove LaunchDaemon configuration
rm -f /Library/LaunchDaemons/com.ttttt.dmsa.service.plist

# Unload service
launchctl bootout system/com.ttttt.dmsa.service 2>/dev/null

# Clean up logs
rm -rf /Users/ttttt/Library/Logs/DMSA/*.log

# Clean up database
rm -rf "/Users/ttttt/Library/Application Support/DMSA/ServiceData/objectbox/data.mdb"
rm -rf "/Users/ttttt/Library/Application Support/DMSA/ServiceData/objectbox/lock.mdb"

# Remove protection from /Volumes/BACKUP/Downloads and delete it
BACKUP_DOWNLOADS="/Volumes/BACKUP/Downloads"
if [ -d "$BACKUP_DOWNLOADS" ]; then
    echo "Removing protection from $BACKUP_DOWNLOADS..."
    # Remove ACL
    chmod -N "$BACKUP_DOWNLOADS" 2>/dev/null
    # Remove hidden flag
    chflags nohidden "$BACKUP_DOWNLOADS" 2>/dev/null
    # Restore permissions
    chmod 755 "$BACKUP_DOWNLOADS" 2>/dev/null
    # Delete directory
    echo "Deleting $BACKUP_DOWNLOADS..."
    rm -rf "$BACKUP_DOWNLOADS"
    echo "$BACKUP_DOWNLOADS has been deleted"
else
    echo "$BACKUP_DOWNLOADS does not exist, skipping"
fi

echo "DMSA service cleanup complete"
