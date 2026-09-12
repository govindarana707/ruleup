-- Check-in corrections are accepted only when the client mutation occurred
-- within the same local-first edit window. This allows an offline correction
-- made before the cutoff to replay safely, while rejecting late mutations.
create or replace function public.enforce_check_in_edit_window()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.client_updated_at > old.editable_until then
    raise exception 'check-in edit window has closed' using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists check_ins_edit_window on public.check_ins;
create trigger check_ins_edit_window
before update on public.check_ins
for each row execute function public.enforce_check_in_edit_window();
