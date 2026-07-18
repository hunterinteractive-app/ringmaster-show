alter table public.show_sections
  drop constraint if exists show_sections_breed_scope_check;

alter table public.show_sections
  add constraint show_sections_breed_scope_check
  check (
    breed_scope in (
      'all',
      'single',
      'limited',
      'meat_only',
      'grouped_wool',
      'grouped_commercial',
      'grouped_under_3_5',
      'grouped_marked',
      'grouped_full_arch',
      'grouped_semi_arch',
      'grouped_lop'
    )
  );

comment on constraint show_sections_breed_scope_check
  on public.show_sections is
  'Allows standard section scopes and the seven ARBA grouped specialty presets.';
