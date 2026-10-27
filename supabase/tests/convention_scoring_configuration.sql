begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create temporary table convention_actors (kind text primary key, id uuid default gen_random_uuid());
insert into convention_actors(kind) values ('secretary'), ('super_admin');
insert into auth.users(id) select id from convention_actors;
insert into public.super_admins(user_id) select id from convention_actors where kind='super_admin';

-- A probe without RLS tests the column guard even if a caller already has
-- full table permissions through another policy or a privileged RPC.
create temporary table convention_probe(id integer primary key, is_arba_convention boolean not null default false, note text);
create trigger convention_probe_guard before insert or update of is_arba_convention on convention_probe
for each row execute function public.guard_arba_convention_configuration();
grant select on convention_actors to authenticated;
grant select,insert,update on convention_probe to authenticated,service_role;

select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from convention_actors where kind='secretary'),'role','authenticated','user_metadata',jsonb_build_object('super_admin',true))::text,true);
set local role authenticated;
select lives_ok($$insert into convention_probe(id,note) values(1,'ordinary show')$$,'secretary can create a regular show');
select throws_ok($$insert into convention_probe(id,is_arba_convention) values(2,true)$$,'42501','Only Super Admins can change ARBA Convention scoring.','secretary cannot create a Convention even with forged user metadata');
select throws_ok($$update convention_probe set is_arba_convention=true where id=1$$,'42501','Only Super Admins can change ARBA Convention scoring.','secretary cannot enable Convention through direct API update');
select lives_ok($$update convention_probe set is_arba_convention=false,note='edited regular show' where id=1$$,'unchanged flag remains compatible with older clients');
reset role;

-- A SECURITY DEFINER RPC must not turn the caller into a trusted DB operator.
select throws_ok($$update convention_probe set is_arba_convention=true where id=1$$,'42501','Only Super Admins can change ARBA Convention scoring.','postgres effective role cannot bypass a signed-in secretary identity');
select set_config('request.jwt.claims','{}',true);
select lives_ok($$update convention_probe set is_arba_convention=true where id=1$$,'trusted SQL editor can enable Convention');

select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from convention_actors where kind='secretary'),'role','authenticated')::text,true);
set local role authenticated;
select lives_ok($$update convention_probe set note='secretary edit' where id=1$$,'ordinary secretary saves preserve a database-enabled Convention flag');
select lives_ok($$update convention_probe set is_arba_convention=true where id=1$$,'unchanged true flag can be saved');
select throws_ok($$update convention_probe set is_arba_convention=false where id=1$$,'42501','Only Super Admins can change ARBA Convention scoring.','secretary cannot clear a Convention flag');
select is((select is_arba_convention from convention_probe where id=1),true,'Convention remains enabled after ordinary saves');
reset role;

select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from convention_actors where kind='super_admin'),'role','authenticated')::text,true);
set local role authenticated;
select lives_ok($$update convention_probe set is_arba_convention=false where id=1$$,'verified Super Admin can disable Convention');
select lives_ok($$insert into convention_probe(id,is_arba_convention) values(2,true)$$,'verified Super Admin can enable Convention');
reset role;

select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select lives_ok($$update convention_probe set is_arba_convention=true where id=1$$,'trusted service role can configure Convention');
reset role;
select ok(exists(select 1 from pg_trigger where tgrelid='public.shows'::regclass and tgname='guard_arba_convention_configuration' and not tgisinternal),'guard is attached to real shows table');
select ok(not (select prosecdef from pg_proc where oid='public.guard_arba_convention_configuration()'::regprocedure),'guard uses invoker permissions');
select ok(not has_function_privilege('authenticated','public.guard_arba_convention_configuration()','execute'),'trigger helper is not an authenticated RPC');
select * from finish();
rollback;
