-- Private reward images. Object names are:
--   <auth.uid()>/<reward_id>/<object_uuid>.(jpg|webp)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'reward-images',
  'reward-images',
  false,
  1048576,
  array['image/jpeg', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy reward_images_select_own on storage.objects for select to authenticated
using (bucket_id = 'reward-images' and (storage.foldername(name))[1] = auth.uid()::text);

create policy reward_images_insert_own on storage.objects for insert to authenticated
with check (
  bucket_id = 'reward-images'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name ~* '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|webp)$'
);

create policy reward_images_update_own on storage.objects for update to authenticated
using (bucket_id = 'reward-images' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'reward-images' and (storage.foldername(name))[1] = auth.uid()::text);

create policy reward_images_delete_own on storage.objects for delete to authenticated
using (bucket_id = 'reward-images' and (storage.foldername(name))[1] = auth.uid()::text);
