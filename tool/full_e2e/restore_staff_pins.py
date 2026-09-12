"""Restore inspected historical PIN schema for synthetic browser rehearsals."""
import json,sys
from local import Local,ROOT

def restore(lab):
    sql=['''begin;
    create table if not exists public.show_staff_approval_pins (
      id uuid primary key default gen_random_uuid(),
      show_id uuid not null references public.shows(id) on delete cascade,
      user_id uuid not null, role text not null, pin_code text not null,
      is_active boolean default true, created_at timestamptz default now());
    alter table public.show_staff_approval_pins enable row level security;
    revoke all on public.show_staff_approval_pins from public, anon, authenticated;
    grant all on public.show_staff_approval_pins to service_role;
    create unique index if not exists uniq_show_user_pin on public.show_staff_approval_pins(show_id,user_id);
    create unique index if not exists uniq_show_pin_code on public.show_staff_approval_pins(show_id,pin_code);
    ''']
    for filename in ('e2e_historical_staff_pins.json','e2e_historical_validate_staff_pin.json'):
        for f in json.loads((ROOT/'supabase/local'/filename).read_text()):
            signature='uuid,text' if f['proname']=='validate_show_staff_pin' else 'uuid'
            sql += [f['definition'].replace(' SECURITY DEFINER',' SECURITY DEFINER\n SET search_path = \'\'')+';',
                    f"revoke all on function public.{f['proname']}({signature}) from public,anon;",
                    f"grant execute on function public.{f['proname']}({signature}) to authenticated,service_role;"]
    sql+= ["notify pgrst,'reload schema'; commit;"]
    lab.sql('\n'.join(sql))
if __name__=='__main__':restore(Local(sys.argv[1]))
