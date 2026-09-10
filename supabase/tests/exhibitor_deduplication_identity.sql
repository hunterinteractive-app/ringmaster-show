-- Read-only regression cases for distinct identities and valid duplicates.
    with fixtures(id, display_name, email, phone, arba_number, type, birth_date, owner_user_id, is_local_only, created_at, is_active, is_merged, is_test) as (
 values
 (1,'Tommy Cook','family@example.test','5551112222','','adult','1982-10-04'::date,null::uuid,false,now(),true,false,false),
 (2,'Tommy H Cook','family@example.test','5551112222','','youth','2013-06-28'::date,null::uuid,false,now(),true,false,false),
 (3,'Same Name','types@example.test','5551112222','','adult',null::date,null::uuid,false,now(),true,false,false),
 (4,'Same Name','types@example.test','5551112222','','youth',null::date,null::uuid,false,now(),true,false,false),
 (5,'Same Name','dates@example.test','5551112222','','adult','1982-01-01'::date,null::uuid,false,now(),true,false,false),
 (6,'Same Name','dates@example.test','5551112222','','adult','1983-01-01'::date,null::uuid,false,now(),true,false,false),
 (7,'Jane Doe','duplicates@example.test','(555) 111-2222','','adult','1982-01-01'::date,null::uuid,false,now(),true,false,false),
 (8,'JANE DOE','duplicates@example.test','5551112222','','adult','1982-01-01'::date,null::uuid,false,now(),true,false,false)
), normalized_exhibitors as (
      select
        e.id,
        regexp_replace(lower(coalesce(e.display_name, '')), '[^a-z0-9]+', '', 'g') as name_key,
        lower(regexp_replace(coalesce(e.email, ''), '\s+', '', 'g')) as email_key,
        regexp_replace(coalesce(e.phone, ''), '\D', '', 'g') as phone_key,
        upper(regexp_replace(coalesce(e.arba_number, ''), '\s+', '', 'g')) as arba_key,
        e.type,
        e.birth_date,
        e.owner_user_id,
        e.is_local_only,
        e.created_at
      from fixtures e
      where e.is_active
        and not e.is_merged
        and not e.is_test
    ),
    eligible_groups as (
      select name_key, email_key, phone_key
      from normalized_exhibitors
      where name_key <> ''
        and email_key <> ''
        and length(phone_key) >= 7
      group by name_key, email_key, phone_key
      having count(*) > 1
        and count(distinct owner_user_id) filter (where owner_user_id is not null) <= 1
        and count(distinct nullif(arba_key, '')) <= 1
        and count(distinct type) = 1
        and count(type) = count(*)
        and count(distinct birth_date) <= 1
    )
select coalesce(array_agg(email_key order by email_key),array[]::text[]) = array['duplicates@example.test'] as regression_passed from eligible_groups;
