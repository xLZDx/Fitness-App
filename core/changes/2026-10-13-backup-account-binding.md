# Change record: backup iteration ceiling, account binding and undo (NEW-BACKUP-ITER, NEW-RESTORE-BIND)

**Problems.**
1. `decryptBackup` accepted any PBKDF2 iteration count from the file, so a crafted backup could pin a CPU for hours.
2. Restoring a backup wrote the health blob under whatever account was signed in, with no check that the backup belonged to that account and no way back.

**Changes.**
- `backup_envelope.dart`: `kMaxIterations` (2,100,000, ten times the default); a file above it is rejected as `BackupFormatException("backup key settings are out of range")`.
- `backup_transfer.dart`: the payload carries an optional `owner` tag, `ownerTagFor(uid)` (first 16 hex chars of a SHA-256 of a fixed prefix and the uid, never the uid itself). `readTransferOwner` returns it, or null for older backups, which restore exactly as before. New `BackupAccountMismatch`.
- `backup_providers.dart`: backups are created with the tag. Restore refuses a backup whose tag differs from the signed-in account unless the caller passes `acceptOtherAccount: true`. Before overwriting, the previous device blob is held in memory only (not written to disk, so no new copy of health data exists) and `undoLastRestore()` puts it back or clears the key if there was none. An unreadable previous blob is not undoable because the store already quarantined it.
- `backup_page.dart` and both `.arb` files: a "Restore anyway" button after a mismatch, an "Undo restore" button after a restore, and four new strings (`backupRestoreOtherAccount`, `backupRestoreAnyway`, `backupRestoreUndo`, `backupRestoreUndone`) in English and Russian.

**Contracts touched.** Backup payload format (additive optional field, version unchanged), restore flow and its error types.

**Known limits.** Undo is lost if the app process dies. A backup made before this change has no tag and cannot be bound to an account. The tag is not a secret; it only detects an honest mix-up.

**Verification state.** Not run. The test agents write and run the focused tests at sprint end. Nothing pushed.
