# Off-site database backups

The `weekly-database-backup` workflow creates logical role, schema, and data
dumps every Sunday, verifies their checksums, encrypts them with AES-256, and
uploads only the encrypted archive and its checksum to Backblaze B2.

## One-time setup

1. Create a private Backblaze B2 bucket dedicated to these backups.
2. Add a lifecycle rule in that bucket to delete files after 400 days.
3. Create a B2 application key restricted to that bucket with read/write access.
4. In GitHub, open **Settings > Secrets and variables > Actions**, and add:
   - `SUPABASE_DB_URL` — the Session pooler connection URI from the Supabase
     Dashboard's **Connect** panel, with the database password filled in.
   - `BACKUP_PASSPHRASE` — a unique, high-entropy passphrase kept in a password manager.
   - `B2_KEY_ID` and `B2_APPLICATION_KEY` — the restricted B2 application key.
   - `B2_REGION` — the B2 bucket region, such as `us-west-004`.
   - `B2_BUCKET` — the dedicated private bucket name.
   - `B2_ENDPOINT` — the matching B2 S3 endpoint, such as `https://s3.us-west-004.backblazeb2.com`.
5. Run **Back up Supabase database to Backblaze B2** manually once in GitHub Actions and confirm both encrypted files appear in `ringmaster-show/database/`.

## Scope and recovery

This is a database backup. It does not copy the file contents in Supabase
Storage; Storage objects need a separate backup process if they are included in
the recovery objective. Keep the passphrase and the B2 key separate from the
GitHub repository. Test a restore to a non-production project periodically.
