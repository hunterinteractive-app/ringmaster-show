alter table public.shows
  add column if not exists national_show_section_id uuid;

alter table public.shows
  drop constraint if exists shows_national_show_section_id_fkey;

alter table public.shows
  add constraint shows_national_show_section_id_fkey
  foreign key (national_show_section_id)
  references public.show_sections(id)
  on delete set null;

create index if not exists shows_national_show_section_id_idx
  on public.shows (national_show_section_id)
  where national_show_section_id is not null;

comment on column public.shows.national_show_section_id is
  'The enabled show section that receives national-show reporting rules when is_national_show is true.';
