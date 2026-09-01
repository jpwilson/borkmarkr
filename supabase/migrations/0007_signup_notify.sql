-- Email JP on every beta/lifetime signup. pg_net posts the new row to the
-- notify-signup Edge Function (shared-token auth), which sends via Resend.
-- Fire-and-forget: a failed notification must never fail the signup insert.

create extension if not exists pg_net;

create or replace function public.notify_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://pcjuxnhqxyfvgagnblzv.supabase.co/functions/v1/notify-signup',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-notify-token', 'bork-notify-8253'
    ),
    body := jsonb_build_object('email', new.email, 'source', new.source, 'at', now())
  );
  return new;
exception when others then
  return new;
end $$;

create trigger beta_signups_notify
  after insert on public.beta_signups
  for each row execute function public.notify_signup();
