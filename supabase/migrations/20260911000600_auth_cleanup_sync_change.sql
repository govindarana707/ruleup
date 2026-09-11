-- Account deletion cascades through application tables after the auth.users
-- owner is no longer FK-visible. Do not create per-row tombstones for an
-- identity whose entire private change feed is being deleted.
create or replace function public.record_sync_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  change_operation public.sync_operation;
begin
  if tg_op = 'DELETE' then
    if not exists (select 1 from auth.users where id = old.user_id) then
      return old;
    end if;
    insert into public.sync_changes(user_id, entity_type, entity_id, operation, updated_at)
    values (old.user_id, tg_argv[0]::public.sync_entity_type, old.id, 'delete', old.updated_at);
    return old;
  end if;
  change_operation := case
    when to_jsonb(new)->>'archived_at' is not null then 'archive'::public.sync_operation
    else 'upsert'::public.sync_operation
  end;
  insert into public.sync_changes(user_id, entity_type, entity_id, operation, updated_at)
  values (new.user_id, tg_argv[0]::public.sync_entity_type, new.id, change_operation, new.updated_at);
  return new;
end;
$$;
