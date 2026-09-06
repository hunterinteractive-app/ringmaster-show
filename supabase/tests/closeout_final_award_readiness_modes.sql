-- Every Results Entry final-award mode must block closeout until its required
-- section-level awards have been selected.

create extension if not exists pgtap with schema extensions;

begin;
select plan(9);

update public.breeds
set class_system = case when name = 'Jersey Wooly' then 'six' else 'four' end
where name in ('Mini Rex', 'Jersey Wooly');

insert into public.entries (
  id,
  show_id,
  section_id,
  exhibitor_id,
  species,
  tattoo,
  breed,
  variety,
  sex,
  class_name,
  status,
  is_shown,
  is_fur,
  placement,
  result_status,
  judged_by_show_judge_id
) values (
  '40000000-0000-0000-0000-000000000203',
  '20000000-0000-0000-0000-000000000004',
  '21000000-0000-0000-0000-000000000004',
  '30000000-0000-0000-0000-000000000001',
  'rabbit',
  'FINAL-SIX',
  'Jersey Wooly',
  'Black',
  'Doe',
  'Senior',
  'entered',
  true,
  false,
  '1',
  'Shown',
  '31000000-0000-0000-0000-000000000001'
);

delete from public.entry_awards ea
using public.entries e
where ea.entry_id = e.id
  and e.show_id = '20000000-0000-0000-0000-000000000004'
  and e.section_id = '21000000-0000-0000-0000-000000000004';

insert into public.entry_awards (show_id, entry_id, award_code) values
  (
    '20000000-0000-0000-0000-000000000004',
    '40000000-0000-0000-0000-000000000001',
    'BOB'
  ),
  (
    '20000000-0000-0000-0000-000000000004',
    '40000000-0000-0000-0000-000000000203',
    'BOB'
  );

update public.shows
set final_award_mode = 'four_six_bis'
where id = '20000000-0000-0000-0000-000000000004';

select is(
  (
    public.show_results_readiness_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'missing_final_award_count'
  )::integer,
  3,
  'four/six mode requires Best 4-Class, Best 6-Class, and BIS'
);

select is(
  (
    select array_agg(item ->> 'award_code' order by item ->> 'award_code')
    from jsonb_array_elements(
      public.show_results_readiness_scoped(
        '20000000-0000-0000-0000-000000000004',
        array['21000000-0000-0000-0000-000000000004']::uuid[]
      ) -> 'missing_final_awards'
    ) item
  ),
  array['B4C', 'B6C', 'BIS']::text[],
  'four/six mode exposes each missing award to Needs Fixed'
);

insert into public.entry_awards (show_id, entry_id, award_code) values
  (
    '20000000-0000-0000-0000-000000000004',
    '40000000-0000-0000-0000-000000000001',
    'Best 4-Class'
  ),
  (
    '20000000-0000-0000-0000-000000000004',
    '40000000-0000-0000-0000-000000000203',
    'Best 6-Class'
  ),
  (
    '20000000-0000-0000-0000-000000000004',
    '40000000-0000-0000-0000-000000000203',
    'Best In Show'
  );

select is(
  (
    public.show_results_readiness_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'missing_final_award_count'
  )::integer,
  0,
  'four/six mode passes when all three required awards are valid'
);

delete from public.entry_awards
where show_id = '20000000-0000-0000-0000-000000000004'
  and award_code in ('Best 4-Class', 'Best 6-Class', 'Best In Show');

update public.shows
set final_award_mode = 'bis_ris'
where id = '20000000-0000-0000-0000-000000000004';

select is(
  (
    public.show_results_readiness_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'missing_final_award_count'
  )::integer,
  2,
  'BIS/RIS mode requires both awards when multiple BOB winners exist'
);

insert into public.entry_awards (show_id, entry_id, award_code) values
  (
    '20000000-0000-0000-0000-000000000004',
    '40000000-0000-0000-0000-000000000001',
    'Best In Show'
  ),
  (
    '20000000-0000-0000-0000-000000000004',
    '40000000-0000-0000-0000-000000000203',
    'Reserve In Show'
  );

select is(
  (
    public.show_results_readiness_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'missing_final_award_count'
  )::integer,
  0,
  'BIS/RIS mode passes after BIS and RIS are selected'
);

select is(
  (
    public.show_results_readiness_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'invalid_final_award_count'
  )::integer,
  0,
  'valid BIS/RIS winners are accepted'
);

delete from public.entry_awards
where show_id = '20000000-0000-0000-0000-000000000004'
  and award_code = 'Reserve In Show';

update public.shows
set final_award_mode = 'bis_1ris_2ris'
where id = '20000000-0000-0000-0000-000000000004';

select is(
  (
    public.show_results_readiness_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'missing_final_award_count'
  )::integer,
  1,
  'legacy reserve mode still requires First Reserve after BIS'
);

insert into public.entry_awards (show_id, entry_id, award_code) values (
  '20000000-0000-0000-0000-000000000004',
  '40000000-0000-0000-0000-000000000203',
  '1RIS'
);

select is(
  (
    public.show_results_readiness_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'missing_final_award_count'
  )::integer,
  0,
  'legacy reserve mode passes after BIS and First Reserve are selected'
);

select is(
  (
    public.show_results_readiness_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'suggested_final_award_count'
  )::integer,
  1,
  'Second Reserve remains suggested instead of blocking'
);

select * from finish();
rollback;
