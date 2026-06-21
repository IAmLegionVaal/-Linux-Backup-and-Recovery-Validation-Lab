# Linux Backup and Recovery Validation Lab

A Bash toolkit for validating backup artefacts and performing controlled, verified restores into an empty destination.

## Validate a backup

```bash
chmod +x src/validate_backup.sh
./src/validate_backup.sh --backup /path/to/backup.tar.gz
```

Perform an isolated test restore:

```bash
./src/validate_backup.sh --backup /path/to/backup.tar.gz --test-restore
```

Compare against a known checksum:

```bash
./src/validate_backup.sh \
  --backup /path/to/backup.tar.gz \
  --expected-sha256 HASH
```

## Perform an actual verified restore

Preview the restore plan:

```bash
chmod +x src/restore_backup.sh
./src/restore_backup.sh \
  --backup /path/to/backup.tar.gz \
  --destination /srv/restore-test \
  --dry-run
```

Restore into a new or empty destination:

```bash
./src/restore_backup.sh \
  --backup /path/to/backup.tar.gz \
  --destination /srv/restore-test
```

Include checksum verification:

```bash
./src/restore_backup.sh \
  --backup /path/to/backup.tar.gz \
  --destination /srv/restore-test \
  --expected-sha256 HASH
```

## What the restore workflow does

- Validates TAR, TAR.GZ, TAR.XZ and ZIP archive integrity before extraction.
- Optionally verifies an expected SHA-256 checksum.
- Extracts into an isolated staging directory first.
- Refuses dangerous system destinations.
- Requires the destination to be absent or empty.
- Never overwrites existing files.
- Records checksum, restored file count, restored size and destination verification.
- Supports dry-run, confirmation prompts, logs and clear exit codes.

## Safety

Existing production data is never deleted or overwritten. The destination must be new or empty. The restore workflow is suitable for controlled recovery tests and technician-managed restores where the destination is explicitly selected.

## Author

Dewald Pretorius — L2 IT Support Engineer
