# Houston final award format

The `bis_1ris_2ris_bbos` format adds **Best of the Best Opposite** (`BBOS`) to the existing Best in Show / 1st RIS / 2nd RIS format.

- Availability uses `secretary_feature_access` with feature key `best_of_best_opposite`. The initial account is `3e8dddf9-3a17-4ebb-aeab-9b51d31e7871`.
- An eligible show has an allowlisted creator, owner, or explicitly assigned show secretary. Normal show permissions still apply. Global administration alone does not enable the format for unrelated shows.
- Select the format in Edit Show Settings or Award Rules. Staff entering results use the show's saved format, including QR results entry.
- BBOS requires a shown, first-place, non-fur rabbit or cavy with Best Opposite Sex of Breed (`BOSB`, also recognized as `BOS`). Variety/group opposites alone do not qualify.
- There is one BBOS winner per species per section. This award selects from breed BOS winners; it does not require the winner to be the opposite sex of the BIS animal.
- Missing BBOS produces a closeout warning, never a missing-required-award blocker. BIS, 1st RIS, and 2nd RIS retain their existing requirements. Recorded BBOS must remain eligible and unique.
- Removing BOS in the entry sheet clears BBOS. Remove existing BBOS selections before switching away from this format.

Applied `20260914005617_add_best_of_best_opposite_final_award.sql` to the live Supabase project on September 14, 2026 (UTC). The matching Flutter build is available in the local preview. The feature option stays hidden if the access RPC is unavailable. The migration adds the allowlist row; it does not change any show's selected format.

When another secretary's account exists, add the following row through a privileged database connection, replacing the example UUID:

```sql
insert into public.secretary_feature_access (feature_key, user_id)
values ('best_of_best_opposite', 'NEW_ACCOUNT_UUID'::uuid)
on conflict (feature_key, user_id) do nothing;
```

Validation covers rabbit/cavy eligibility, existing final award formats, standard/QR UI visibility, optional closeout warnings, show-scoped access, duplicate winners, authenticated saves, and transactional BOS/BBOS removal. The SQL fixture runs in a transaction and rolls back; it is intended for the disposable local Supabase database.
