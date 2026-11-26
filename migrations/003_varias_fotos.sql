-- Hasta 5 fotos por regalo.
-- La tabla item_photos pasa de "una foto por regalo" (clave = item_id)
-- a "varias fotos por regalo" (clave = id propio). Las fotos existentes se conservan.

alter table public.item_photos drop constraint if exists item_photos_pkey;
alter table public.item_photos add column if not exists id bigserial;
alter table public.item_photos add primary key (id);
alter table public.item_photos add column if not exists pos smallint not null default 0;
create index if not exists item_photos_item_idx on public.item_photos(item_id, pos, id);
revoke all on sequence public.item_photos_id_seq from anon, authenticated;

-- Tablero: "photos" = lista de ids de foto en orden (vacía si no hay).
-- Se mantiene "photo" (id de la primera foto o null) para páginas antiguas aún abiertas.
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
        'photos', coalesce((select json_agg(ph.id order by ph.pos, ph.id) from item_photos ph where ph.item_id = i.id), '[]'::json),
        'photo', (select ph.id from item_photos ph where ph.item_id = i.id order by ph.pos, ph.id limit 1)
      ) order by i.created_at, i.id)
      from items i where i.owner_id = me), '[]'::json),
    'others', coalesce((
      select json_agg(json_build_object(
        'id', m.id,
        'name', m.name,
        'items', coalesce((
          select json_agg(json_build_object(
            'id', i.id, 'name', i.name, 'details', i.details, 'link', i.link,
            'photos', coalesce((select json_agg(ph.id order by ph.pos, ph.id) from item_photos ph where ph.item_id = i.id), '[]'::json),
            'photo', (select ph.id from item_photos ph where ph.item_id = i.id order by ph.pos, ph.id limit 1),
            'bought', i.bought_by is not null,
            'by_me',  coalesce(i.bought_by = me, false)
          ) order by i.created_at, i.id)
          from items i where i.owner_id = m.id), '[]'::json)
      ) order by m.sort, m.name)
      from members m where m.id <> me), '[]'::json)
  );
end $$;

-- Ver una foto concreta por su id.
create or replace function public.buzon_photo_get(p text, me int, photo_id bigint)
returns text
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  perform _buzon_check(p, me);
  return (select ph.data from item_photos ph where ph.id = photo_id);
end $$;

-- Añadir una foto a un regalo de MI carta (máximo 5). Devuelve el id de la foto nueva.
create or replace function public.buzon_photo_add(p text, me int, photo_item_id bigint, photo text)
returns bigint
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  new_id bigint;
begin
  perform _buzon_check(p, me);
  if not exists (select 1 from items i where i.id = photo_item_id and i.owner_id = me) then
    raise exception 'not_owner';
  end if;
  if photo is null or char_length(photo) > 700000 then raise exception 'photo_too_big'; end if;
  if photo !~ '^data:image/(jpeg|png|webp);base64,' then raise exception 'bad_photo'; end if;
  perform 1 from items i where i.id = photo_item_id for update;  -- evita pasar de 5 con envíos simultáneos
  if (select count(*) from item_photos ph where ph.item_id = photo_item_id) >= 5 then
    raise exception 'too_many_photos';
  end if;
  insert into item_photos (item_id, data, pos, updated_at)
  values (photo_item_id, photo,
          coalesce((select max(ph.pos) + 1 from item_photos ph where ph.item_id = photo_item_id), 0),
          now())
  returning id into new_id;
  return new_id;
end $$;

-- Quitar una foto de un regalo de MI carta.
create or replace function public.buzon_photo_delete(p text, me int, photo_id bigint)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  perform _buzon_check(p, me);
  delete from item_photos ph
   using items i
   where ph.id = photo_id and i.id = ph.item_id and i.owner_id = me;
  return found;
end $$;

-- Compatibilidad con páginas antiguas aún abiertas: primera foto del regalo.
create or replace function public.buzon_photo(p text, me int, photo_item_id bigint)
returns text
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  perform _buzon_check(p, me);
  return (select ph.data from item_photos ph where ph.item_id = photo_item_id order by ph.pos, ph.id limit 1);
end $$;

-- Compatibilidad: sustituye todas las fotos del regalo por una (o las quita con null).
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
  if photo is not null and photo <> '' then
    if char_length(photo) > 700000 then raise exception 'photo_too_big'; end if;
    if photo !~ '^data:image/(jpeg|png|webp);base64,' then raise exception 'bad_photo'; end if;
  end if;
  delete from item_photos ph where ph.item_id = photo_item_id;
  if photo is not null and photo <> '' then
    insert into item_photos (item_id, data, pos, updated_at) values (photo_item_id, photo, 0, now());
  end if;
  return true;
end $$;

revoke all on function public.buzon_photo_get(text, int, bigint)          from public, authenticated;
revoke all on function public.buzon_photo_add(text, int, bigint, text)    from public, authenticated;
revoke all on function public.buzon_photo_delete(text, int, bigint)       from public, authenticated;
grant execute on function public.buzon_photo_get(text, int, bigint)       to anon;
grant execute on function public.buzon_photo_add(text, int, bigint, text) to anon;
grant execute on function public.buzon_photo_delete(text, int, bigint)    to anon;
