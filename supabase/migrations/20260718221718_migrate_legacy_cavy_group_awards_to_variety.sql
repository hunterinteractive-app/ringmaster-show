-- Persist the terminology change for cavy awards that were selected before
-- variety awards replaced group awards. The scoring function also normalizes
-- these legacy codes, but rewriting the source rows keeps exports and editing
-- screens consistent with the current standard.
update public.entry_awards as ea
set
  award_code = case upper(trim(ea.award_code))
    when 'BOG' then 'BOV'
    when 'BOSG' then 'BOSV'
  end,
  updated_at = now()
from public.entries as e
where e.id = ea.entry_id
  and lower(e.species::text) = 'cavy'
  and upper(trim(ea.award_code)) in ('BOG', 'BOSG');
