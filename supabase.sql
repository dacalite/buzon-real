-- =====================================================================
--  EL BUZÓN REAL · Lista de regalos familiar
--  Pégalo entero en Supabase → SQL Editor → Run.
--  Antes de ejecutarlo, cambia:
--    Nada: contraseña y nombres ya están puestos al final.
--    (La contraseña se escribe siempre en minúsculas y sin tildes;
--     la web ya normaliza lo que escribe cada uno.)
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tablas ----------------------------------------------------

create table if not exists public.settings (
  id            int primary key default 1 check (id = 1),
  password_hash text not null
);

create table if not exists public.members (
  id    serial primary key,
  name  text not null unique,
  sort  int  not null default 0
);

create table if not exists public.items (
  id          bigserial primary key,
  owner_id    int  not null references public.members(id),
  name        text not null check (char_length(name) between 1 and 120),
  details     text check (details is null or char_length(details) <= 200),
  link        text check (link is null or (char_length(link) <= 800 and link ~* '^https?://')),
  bought_by   int  references public.members(id),
  bought_at   timestamptz,
  created_at  timestamptz not null default now(),
  check (bought_by is null or bought_by <> owner_id)
);

create index if not exists items_owner_idx on public.items(owner_id);

-- Nadie toca las tablas directamente: todo pasa por las funciones de abajo,
-- que comprueban la contraseña y aplican las reglas.
alter table public.settings enable row level security;
alter table public.members  enable row level security;
alter table public.items    enable row level security;
revoke all on public.settings, public.members, public.items from anon, authenticated;

-- ---------- Funciones internas ---------------------------------------

create or replace function public._buzon_check(p text, me int default null)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if p is null or not exists (
    select 1 from settings where password_hash = crypt(p, password_hash)
  ) then
    raise exception 'bad_password';
  end if;
  if me is not null and not exists (select 1 from members where id = me) then
    raise exception 'unknown_member';
  end if;
end $$;

revoke all on function public._buzon_check(text, int) from public, anon, authenticated;

-- ---------- API (llamada desde la web) --------------------------------

-- Comprueba la contraseña y devuelve la lista de nombres para el desplegable.
create or replace function public.buzon_login(p text)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  perform _buzon_check(p);
  return coalesce(
    (select json_agg(json_build_object('id', id, 'name', name) order by sort, name) from members),
    '[]'::json);
end $$;

-- Devuelve mi carta (SIN estado de compra) y las cartas de los demás
-- (con estado de compra, pero sin decir quién lo compró).
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
        'id', i.id, 'name', i.name, 'details', i.details, 'link', i.link
      ) order by i.created_at, i.id)
      from items i where i.owner_id = me), '[]'::json),
    'others', coalesce((
      select json_agg(json_build_object(
        'id', m.id,
        'name', m.name,
        'items', coalesce((
          select json_agg(json_build_object(
            'id', i.id, 'name', i.name, 'details', i.details, 'link', i.link,
            'bought', i.bought_by is not null,
            'by_me',  coalesce(i.bought_by = me, false)
          ) order by i.created_at, i.id)
          from items i where i.owner_id = m.id), '[]'::json)
      ) order by m.sort, m.name)
      from members m where m.id <> me), '[]'::json)
  );
end $$;

-- Añadir un regalo a MI carta. No existe función para borrar ni editar.
create or replace function public.buzon_add_item(p text, me int, item_name text, item_details text, item_link text)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  n text := nullif(btrim(item_name), '');
  d text := nullif(btrim(item_details), '');
  l text := nullif(btrim(item_link), '');
  new_id bigint;
begin
  perform _buzon_check(p, me);
  if n is null then raise exception 'empty_name'; end if;
  if l is not null and l !~* '^https?://' then raise exception 'bad_link'; end if;
  if (select count(*) from items where owner_id = me) >= 50 then
    raise exception 'too_many_items';
  end if;
  insert into items(owner_id, name, details, link) values (me, n, d, l)
  returning id into new_id;
  return json_build_object('id', new_id);
end $$;

-- Marcar como comprado. Devuelve false si otra persona se ha adelantado.
create or replace function public.buzon_mark(p text, me int, item_id bigint)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  perform _buzon_check(p, me);
  update items set bought_by = me, bought_at = now()
   where id = item_id and bought_by is null and owner_id <> me;
  return found;
end $$;

-- Desmarcar. Solo funciona si lo marcó la misma persona.
create or replace function public.buzon_unmark(p text, me int, item_id bigint)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  perform _buzon_check(p, me);
  update items set bought_by = null, bought_at = null
   where id = item_id and bought_by = me;
  return found;
end $$;

grant execute on function public.buzon_login(text)                         to anon;
grant execute on function public.buzon_board(text, int)                    to anon;
grant execute on function public.buzon_add_item(text, int, text, text, text) to anon;
grant execute on function public.buzon_mark(text, int, bigint)             to anon;
grant execute on function public.buzon_unmark(text, int, bigint)           to anon;

-- ---------- Datos iniciales (EDITA ESTO) ------------------------------

insert into public.settings(id, password_hash)
values (1, extensions.crypt('turron', extensions.gen_salt('bf')))
on conflict (id) do update set password_hash = excluded.password_hash;

-- Pon los nombres tal y como queréis que salgan en el desplegable.
-- "sort" es el orden en el que aparecen.
insert into public.members(name, sort) values
  ('Sergio',   1),
  ('Pilar',    2),
  ('Benito',   3),
  ('Marina',   4),
  ('Natalia',  5),
  ('Patricia', 6),
  ('Juan',     7),
  ('Boni',     8)
on conflict (name) do nothing;
