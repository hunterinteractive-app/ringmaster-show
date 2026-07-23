alter table public.show_closeout_state
  add column if not exists exhibitor_emails_sent_at timestamptz,
  add column if not exists club_reports_sent_at timestamptz;
