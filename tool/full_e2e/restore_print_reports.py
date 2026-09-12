"""Restore inspected print contracts in an isolated local rehearsal only."""
import json
import sys
from local import Local, ROOT


def restore(lab):
    base=json.loads((ROOT/'supabase/local/e2e_historical_print_base.json').read_text())['definition']
    functions=json.loads((ROOT/'supabase/local/e2e_historical_print_reports.json').read_text())
    # Preserve the older local base view used by other fixtures. These two print
    # functions use a separate view with the inspected production projection.
    script=["begin; set local search_path=public;",
        'create or replace view public.local_event_print_entry_base_v with (security_invoker=true) as '+base,
        'grant select on public.local_event_print_entry_base_v to authenticated,service_role;',
        'drop function if exists public.report_checkin_entries(uuid,uuid,boolean);']
    for f in functions:
        definition=f['definition'].replace('public.report_entry_base_v','public.local_event_print_entry_base_v')
        if f['proname']=='report_checkin_entries':
            # The simplified local balance report exposes one row per cart;
            # the inspected hosted contract exposes one row per exhibitor.
            # Aggregate the fixture before this one-to-one print join so a
            # separate cash-change cart cannot duplicate every printed animal.
            start=definition.index('show_balances as (')
            end=definition.index('\n)\n\nselect',start)
            fields=('balance_due_cents','calculated_total_cents','discount_cents',
                    'paid_online_cents','paid_manual_cents','refunded_cents')
            aggregate=',\n    '.join(f'sum(rsb.{field}) as {field}' for field in fields)
            definition=definition[:start]+f'''show_balances as (
  select rsb.exhibitor_id,
    {aggregate}
  from public.report_show_exhibitor_balances(p_show_id) rsb
  group by rsb.exhibitor_id'''+definition[end:]
        script.append(definition+';')
        signature='uuid,boolean,uuid' if f['proname']=='report_checkin_entries' else 'uuid,uuid,boolean'
        script += [f"revoke all on function public.{f['proname']}({signature}) from public,anon;",
                   f"grant execute on function public.{f['proname']}({signature}) to authenticated,service_role;"]
    for f in json.loads((ROOT/'supabase/local/e2e_historical_browser_permissions.json').read_text()):
        assert f['proname']=='user_can_manage_judges'
        script += [f['definition']+';',
            'revoke all on function public.user_can_manage_judges(uuid,uuid) from public,anon;',
            'grant execute on function public.user_can_manage_judges(uuid,uuid) to authenticated,service_role;']
    # Inspected SELECT policies only. Do not import the historical permissive
    # INSERT policies. All records in this isolated database are synthetic.
    policies=json.loads((ROOT/'supabase/local/e2e_historical_print_policies.json').read_text())
    policies+=json.loads((ROOT/'supabase/local/e2e_historical_delivery_policy.json').read_text())
    existing={(r['tablename'],r['policyname']) for r in lab.rows("select tablename,policyname from pg_policies where schemaname='public'")}
    for p in policies:
        if (p['tablename'],p['policyname']) not in existing:
            assert p['cmd']=='SELECT' and p['roles']=='{authenticated}'
            name=p['policyname'].replace('"','""')
            script.append(f'create policy "{name}" on public.{p["tablename"]} for select to authenticated using ({p["qual"]});')
    script += ["notify pgrst,'reload schema';",'commit;']
    lab.sql('\n'.join(script))


if __name__=='__main__':restore(Local(sys.argv[1]))
