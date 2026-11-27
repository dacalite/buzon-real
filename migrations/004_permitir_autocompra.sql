-- Permite que el dueño de un regalo figure como comprador (se lo compra él mismo).
-- La web sigue impidiendo marcar tus propios regalos: buzon_mark exige owner_id <> me.
alter table public.items drop constraint if exists items_check;
