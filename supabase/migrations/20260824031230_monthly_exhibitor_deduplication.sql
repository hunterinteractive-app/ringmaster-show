-- This is a soft merge: historical records keep their original exhibitor IDs,
-- while inactive duplicate directory records point at the retained record.
-- That matches the existing exhibitor_merge_log behavior and preserves audit
-- history for entries, payments, and check-in records.
create or replace function public.run_monthly_exhibitor_deduplication(
  p_apply boolean default false
)
returns table (
  kept_exhibitor_id uuid,
  merged_exhibitor_id uuid,
  merge_reason text
)
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  candidate_group record;
  candidate_merged_id uuid;
  candidate_snapshot jsonb;
  reason constant text :=
    'Automated monthly deduplication: exact normalized name, email, and phone; no conflicting account or ARBA number.';
begin
  if p_apply then
    perform pg_advisory_xact_lock(hashtext('public.run_monthly_exhibitor_deduplication'));
  end if;

  for candidate_group in
    with normalized_exhibitors as (
      select
        e.id,
        lower(regexp_replace(coalesce(e.display_name, ''), '[^a-z0-9]+', '', 'g')) as name_key,
        lower(regexp_replace(coalesce(e.email, ''), '\\s+', '', 'g')) as email_key,
        regexp_replace(coalesce(e.phone, ''), '\\D', '', 'g') as phone_key,
        upper(regexp_replace(coalesce(e.arba_number, ''), '\\s+', '', 'g')) as arba_key,
        e.owner_user_id,
        e.is_local_only,
        e.created_at
      from public.exhibitors e
      where e.is_active
        and not e.is_merged
        and not e.is_test
    ),
    eligible_groups as (
      select
        name_key,
        email_key,
        phone_key
      from normalized_exhibitors
      where name_key <> ''
        and email_key <> ''
        and length(phone_key) >= 7
      group by name_key, email_key, phone_key
      having count(*) > 1
        and count(distinct owner_user_id) filter (where owner_user_id is not null) <= 1
        and count(distinct nullif(arba_key, '')) <= 1
    )
    select array_agg(
      e.id
      order by
        (e.owner_user_id is not null) desc,
        (not e.is_local_only) desc,
        (e.arba_key <> '') desc,
        e.created_at asc,
        e.id
    ) as exhibitor_ids
    from normalized_exhibitors e
    join eligible_groups g
      using (name_key, email_key, phone_key)
    group by e.name_key, e.email_key, e.phone_key
  loop
    kept_exhibitor_id := candidate_group.exhibitor_ids[1];

    foreach candidate_merged_id in array candidate_group.exhibitor_ids[2:]
    loop
      if p_apply then
        select to_jsonb(e)
          into candidate_snapshot
        from public.exhibitors e
        where e.id = candidate_merged_id
          and e.is_active
          and not e.is_merged
        for update;

        if candidate_snapshot is null then
          continue;
        end if;

        update public.exhibitors e
        set
          is_merged = true,
          is_active = false,
          merged_into_exhibitor_id = kept_exhibitor_id,
          merged_at = now(),
          updated_at = now()
        where e.id = candidate_merged_id
          and e.is_active
          and not e.is_merged
          and exists (
            select 1
            from public.exhibitors kept
            where kept.id = kept_exhibitor_id
              and kept.is_active
              and not kept.is_merged
          );

        if not found then
          continue;
        end if;

        insert into public.exhibitor_merge_log (
          kept_exhibitor_id,
          merged_exhibitor_id,
          reason,
          merged_snapshot
        ) values (
          kept_exhibitor_id,
          candidate_merged_id,
          reason,
          candidate_snapshot
        );
      end if;

      merged_exhibitor_id := candidate_merged_id;
      merge_reason := reason;
      return next;
    end loop;
  end loop;
end;
$$;

revoke execute on function public.run_monthly_exhibitor_deduplication(boolean)
  from public, anon, authenticated;

create index if not exists exhibitors_monthly_deduplication_identity_idx
  on public.exhibitors (
    lower(regexp_replace(coalesce(display_name, ''), '[^a-z0-9]+', '', 'g')),
    lower(regexp_replace(coalesce(email, ''), '\\s+', '', 'g')),
    regexp_replace(coalesce(phone, ''), '\\D', '', 'g')
  )
  where is_active and not is_merged and not is_test;

do $$
declare
  existing_job_id bigint;
begin
  select jobid
    into existing_job_id
  from cron.job
  where jobname = 'monthly-exhibitor-deduplication';

  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;

  perform cron.schedule(
    'monthly-exhibitor-deduplication',
    '15 5 1 * *',
    'select public.run_monthly_exhibitor_deduplication(true);'
  );
end;
$$;
