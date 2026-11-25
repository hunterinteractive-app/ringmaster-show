-- Release 1.00.58: replace only the obsolete published manual-payment answer.
-- No customer entries or payments are changed. Match the old text so a newer
-- administrator edit cannot be overwritten. Clear the prior review attribution
-- because this is a deployment content correction, not that person's new review.
with replacement as (
  select $answer$Secretaries can record payments already received in Show Settings → Show Finances → Record payment. On the updated layout, use Manage Show → Finances → Balances & Payment History. Find the exhibitor, enter the amount received, choose the payment method and receipt date, and add a reference if available. Check-In does not need to be enabled.

This records money the club already received; it does not charge an exhibitor. Review Payment history before recording a payment so the same receipt is not entered twice. For a waived charge, use Apply credit instead of recording a payment. Chester cannot record payments or verify an individual balance in chat.$answer$::text as content
)
update assistant_private.answers a
set answer = replacement.content,
    published_answer = replacement.content,
    version = a.version + 1,
    updated_at = now(),
    published_at = now(),
    reviewed_by = null
from replacement
where a.question = 'How do I record manual payments?'
  and a.published_at is not null
  and a.published_answer like 'Recording manual payments through check-in is currently in limited testing%'
returning a.question, a.version;
