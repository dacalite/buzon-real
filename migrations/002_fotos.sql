-- Fotos opcionales de los regalos.
-- Se guardan comprimidas (JPEG en base64) en una tabla aparte para que el
-- tablero no las descargue: la web solo las pide cuando alguien pulsa "Ver foto".

create table if not exists public.item_photos (
  item_id     bigint primary key references public.items(id) on delete cascade,
  data        text not null check (
                char_length(data) <= 700000
                and data ~ '^data:image/(jpeg|png|webp);base64,'),
  updated_at  timestamptz not null default now()
);

alter table public.item_photos enable row level security;
revoke all on public.item_photos from anon, authenticated;

-- El tablero ahora incluye "photo": null si no hay foto, o un número de versión si la hay.
create or replace function public.buzon_board(p text, me int)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  perform _buzon_check(p, me);
  return json_build_object(
    'mine', coalesce((
      select json_agg(json_build_object(
        'id', i.id, 'name', i.name, 'details', i.details, 'link', i.link,
        'photo', (select extract(epoch from ph.updated_at)::bigint from item_photos ph where ph.item_id = i.id)
      ) order by i.created_at, i.id)
      from items i where i.owner_id = me), '[]'::json),
    'others', coalesce((
      select json_agg(json_build_object(
        'id', m.id,
        'name', m.name,
        'items', coalesce((
          select json_agg(json_build_object(
            'id', i.id, 'name', i.name, 'details', i.details, 'link', i.link,
            'photo', (select extract(epoch from ph.updated_at)::bigint from item_photos ph where ph.item_id = i.id),
            'bought', i.bought_by is not null,
            'by_me',  coalesce(i.bought_by = me, false)
          ) order by i.created_at, i.id)
          from items i where i.owner_id = m.id), '[]'::json)
      ) order by m.sort, m.name)
      from members m where m.id <> me), '[]'::json)
  );
end $$;

-- Ver la foto de un regalo (cualquier miembro con la contraseña).
create or replace function public.buzon_photo(p text, me int, photo_item_id bigint)
returns text
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  perform _buzon_check(p, me);
  return (select ph.data from item_photos ph where ph.item_id = photo_item_id);
end $$;

-- Poner, cambiar o quitar (photo = null) la foto de un regalo de MI carta.
create or replace function public.buzon_set_photo(p text, me int, photo_item_id bigint, photo text)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  perform _buzon_check(p, me);
  if not exists (select 1 from items i where i.id = photo_item_id and i.owner_id = me) then
    return false;
  end if;
  if photo is null or photo = '' then
    delete from item_photos ph where ph.item_id = photo_item_id;
    return true;
  end if;
  if char_length(photo) > 700000 then raise exception 'photo_too_big'; end if;
  if photo !~ '^data:image/(jpeg|png|webp);base64,' then raise exception 'bad_photo'; end if;
  insert into item_photos as ph (item_id, data, updated_at)
  values (photo_item_id, photo, now())
  on conflict on constraint item_photos_pkey
  do update set data = excluded.data, updated_at = now();
  return true;
end $$;

revoke all on function public.buzon_photo(text, int, bigint) from public, authenticated;
revoke all on function public.buzon_set_photo(text, int, bigint, text) from public, authenticated;
grant execute on function public.buzon_photo(text, int, bigint)           to anon;
grant execute on function public.buzon_set_photo(text, int, bigint, text) to anon;
