 -- Minimal catalog for the real report view in the isolated finance database.
create table breeds(id uuid, name text, species public.fixture_species, uses_variety_awards boolean, uses_group_awards boolean);
create table varieties(id uuid, breed_id uuid, name text, group_id uuid, sort_order integer);
create table variety_groups(id uuid, name text, sort_order integer);
create view public.report_entry_base_v as
 SELECT e.id AS entry_id,
    e.show_id,
    e.section_id,
    e.exhibitor_id,
    e.tattoo,
    e.breed,
    e.variety,
    e.sex,
    e.class_name,
    e.notes,
    e.scratched_at,
    e.status,
    e.placement,
    e.disqualified_reason,
    e.is_shown,
    e.is_disqualified,
    e.judged_by_show_judge_id,
    e.created_at,
    e.updated_at,
    b.id AS breed_id,
    COALESCE(b.species, e.species) AS species,
    COALESCE(b.uses_variety_awards, true) AS uses_variety_awards,
    COALESCE(b.uses_group_awards, false) AS uses_group_awards,
    v.group_id,
    vg.name AS group_name,
    vg.sort_order AS group_sort_order,
    v.sort_order AS variety_sort_order,
        CASE
            WHEN lower(COALESCE(e.class_name, ''::text)) ~~ '%senior%'::text THEN 1
            WHEN lower(COALESCE(e.class_name, ''::text)) ~~ '%intermediate%'::text THEN 2
            WHEN lower(COALESCE(e.class_name, ''::text)) ~~ '%junior%'::text THEN 3
            ELSE 999
        END AS class_sort_order,
        CASE
            WHEN lower(COALESCE(e.class_name, ''::text)) ~~ '%senior%'::text THEN 'Senior'::text
            WHEN lower(COALESCE(e.class_name, ''::text)) ~~ '%intermediate%'::text THEN 'Intermediate'::text
            WHEN lower(COALESCE(e.class_name, ''::text)) ~~ '%junior%'::text THEN 'Junior'::text
            ELSE e.class_name
        END AS class_age_label,
        CASE
            WHEN lower(COALESCE(e.sex, ''::text)) = ANY (ARRAY['buck'::text, 'boar'::text]) THEN 1
            WHEN lower(COALESCE(e.sex, ''::text)) = ANY (ARRAY['doe'::text, 'sow'::text]) THEN 2
            ELSE 999
        END AS sex_sort_order,
    s.letter AS section_letter,
    COALESCE(s.display_name, ''::text) AS section_display_name,
    s.kind AS section_kind,
    s.sort_order AS section_sort_order,
    ex.display_name AS exhibitor_display_name,
    ex.showing_name AS exhibitor_showing_name,
    ex.first_name AS exhibitor_first_name,
    ex.last_name AS exhibitor_last_name,
    ex.arba_number AS exhibitor_arba_number,
    ex.address_line1 AS exhibitor_address_line1,
    ex.address_line2 AS exhibitor_address_line2,
    ex.city AS exhibitor_city,
    ex.state AS exhibitor_state,
    ex.zip AS exhibitor_zip,
    ex.phone AS exhibitor_phone,
    ex.email AS exhibitor_email,
    COALESCE(NULLIF(ex.display_name, ''::text), NULLIF(ex.showing_name, ''::text), NULLIF(TRIM(BOTH FROM concat_ws(' '::text, ex.first_name, ex.last_name)), ''::text), ''::text) AS exhibitor_label,
    e.animal_name
   FROM entries e
     LEFT JOIN breeds b ON lower(TRIM(BOTH FROM b.name)) = lower(TRIM(BOTH FROM e.breed)) AND lower(TRIM(BOTH FROM b.species::text)) = lower(TRIM(BOTH FROM e.species::text))
     LEFT JOIN varieties v ON lower(TRIM(BOTH FROM v.name)) = lower(TRIM(BOTH FROM e.variety)) AND v.breed_id = b.id
     LEFT JOIN variety_groups vg ON vg.id = v.group_id
     LEFT JOIN show_sections s ON s.id = e.section_id
     LEFT JOIN exhibitors ex ON ex.id = e.exhibitor_id;
