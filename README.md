# Linux Backup and Recovery Validation Lab

A safe Bash-based lab for validating backup artefacts, checksums, archive readability, retention, and controlled test restores.

## Purpose

This project demonstrates that a backup is not considered successful until it can be verified and restored. It focuses on evidence, repeatability, and non-destructive testing.

## Features

- File existence, size, age, and ownership validation
- SHA-256 checksum generation or comparison
- TAR, TAR.GZ, TAR.XZ, and ZIP integrity testing
- Optional isolated extraction into a newly created temporary directory
- File-count and restored-size comparison
- Retention-age evaluation
- Text and JSON validation reports
- Clear pass, warning, and failure results

## Usage

Validate an archive without extracting it:

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
./src/validate_backup.sh --backup /path/to/backup.tar.gz --expected-sha256 HASH
```

## Safety

Test restores are written only to a newly created directory beneath the selected output folder. Existing production data is never overwritten. The script does not delete backups or alter source data.

## Validation scenarios

- Healthy archive with matching checksum
- Corrupt archive
- Backup older than the retention threshold
- Archive containing nested paths
- Insufficient free space for extraction

## Author

Dewald Pretorius — L2 IT Support Engineer
