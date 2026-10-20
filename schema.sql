-- دكانك: مخطط قاعدة بيانات Supabase
-- نفّذ هذا الملف كاملاً من Supabase > SQL Editor بعد اختيار المشروع الصحيح.
create extension if not exists pgcrypto;

create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 100),
  tagline text default '',
  whatsapp text not null,
  city text default '',
  category text default 'متنوع',
  currency text default 'ر.س',
  delivery_fee numeric(12,2) not null default 0 check (delivery_fee >= 0),
  min_order numeric(12,2) not null default 0 check (min_order >= 0),
  hours text default '',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 140),
  description text default '',
  icon text default '🛍️', -- يمكن أن تكون إيموجي أو رابط صورة https
  price numeric(12,2) not null check (price >= 0),
  old_price numeric(12,2) check (old_price is null or old_price >= 0),
  sold_out boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  store_name text not null,
  buyer uuid not null references auth.users(id) on delete restrict,
  buyer_name text not null default '',
  phone text default '',
  addr text default '',
  notes text default '',
  items jsonb not null default '[]'::jsonb,
  delivery numeric(12,2) not null default 0 check (delivery >= 0),
  total numeric(12,2) not null check (total >= 0),
  mode text not null default 'd' check (mode in ('d','p')),
  pay text not null default 'كاش' check (pay in ('كاش','تحويل')),
  status text not null default 'new' check (status in ('new','done','cancelled')),
  created_at timestamptz not null default now()
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  buyer uuid not null references auth.users(id) on delete cascade,
  buyer_name text default '',
  order_id uuid not null unique references public.orders(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text default '',
  created_at timestamptz not null default now()
);

create table if not exists public.visits (
  store_id uuid primary key references public.stores(id) on delete cascade,
  n bigint not null default 0 check (n >= 0)
);

create index if not exists products_store_id_idx on public.products(store_id);
create index if not exists orders_store_created_idx on public.orders(store_id, created_at desc);
create index if not exists orders_buyer_created_idx on public.orders(buyer, created_at desc);
create index if not exists reviews_store_id_idx on public.reviews(store_id);

alter table public.stores enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.reviews enable row level security;
alter table public.visits enable row level security;

-- إزالة السياسات بالاسم نفسه حتى يمكن إعادة تشغيل الملف بأمان.
drop policy if exists stores_public_read on public.stores;
drop policy if exists stores_owner_insert on public.stores;
drop policy if exists stores_owner_update on public.stores;
drop policy if exists stores_owner_delete on public.stores;
drop policy if exists products_public_read on public.products;
drop policy if exists products_owner_insert on public.products;
drop policy if exists products_owner_update on public.products;
drop policy if exists products_owner_delete on public.products;
drop policy if exists orders_participant_read on public.orders;
drop policy if exists orders_buyer_insert on public.orders;
drop policy if exists orders_store_owner_update on public.orders;
drop policy if exists reviews_public_read on public.reviews;
drop policy if exists reviews_buyer_insert on public.reviews;
drop policy if exists visits_owner_read on public.visits;

create policy stores_public_read on public.stores for select using (active = true or owner = auth.uid());
create policy stores_owner_insert on public.stores for insert to authenticated with check (owner = auth.uid());
create policy stores_owner_update on public.stores for update to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
create policy stores_owner_delete on public.stores for delete to authenticated using (owner = auth.uid());

create policy products_public_read on public.products for select using (
  exists (select 1 from public.stores s where s.id = store_id and (s.active = true or s.owner = auth.uid()))
);
create policy products_owner_insert on public.products for insert to authenticated with check (
  exists (select 1 from public.stores s where s.id = store_id and s.owner = auth.uid())
);
create policy products_owner_update on public.products for update to authenticated using (
  exists (select 1 from public.stores s where s.id = store_id and s.owner = auth.uid())
) with check (
  exists (select 1 from public.stores s where s.id = store_id and s.owner = auth.uid())
);
create policy products_owner_delete on public.products for delete to authenticated using (
  exists (select 1 from public.stores s where s.id = store_id and s.owner = auth.uid())
);

create policy orders_participant_read on public.orders for select to authenticated using (
  buyer = auth.uid() or exists (select 1 from public.stores s where s.id = store_id and s.owner = auth.uid())
);
create policy orders_buyer_insert on public.orders for insert to authenticated with check (
  buyer = auth.uid() and exists (select 1 from public.stores s where s.id = store_id and s.active = true)
);
create policy orders_store_owner_update on public.orders for update to authenticated using (
  exists (select 1 from public.stores s where s.id = store_id and s.owner = auth.uid())
) with check (
  exists (select 1 from public.stores s where s.id = store_id and s.owner = auth.uid())
);

create policy reviews_public_read on public.reviews for select using (true);
create policy reviews_buyer_insert on public.reviews for insert to authenticated with check (
  buyer = auth.uid() and exists (
    select 1 from public.orders o
    where o.id = order_id and o.buyer = auth.uid() and o.store_id = reviews.store_id and o.status = 'done'
  )
);
create policy visits_owner_read on public.visits for select to authenticated using (
  exists (select 1 from public.stores s where s.id = store_id and s.owner = auth.uid())
);

-- يزيد عداد الزيارة دون منح الزائر صلاحية الكتابة المباشرة إلى جدول الزيارات.
create or replace function public.track_visit(sid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.stores where id = sid and active = true) then
    insert into public.visits(store_id, n) values (sid, 1)
    on conflict (store_id) do update set n = public.visits.n + 1;
  end if;
end;
$$;
revoke all on function public.track_visit(uuid) from public;
grant execute on function public.track_visit(uuid) to anon, authenticated;

-- صلاحيات الجداول الأساسية لمستخدمي API؛ سياسات RLS هي التي تحدد الصفوف المسموح بها.
grant select, insert, update, delete on public.stores to anon, authenticated;
grant select, insert, update, delete on public.products to anon, authenticated;
grant select, insert on public.orders to authenticated;
grant update (status) on public.orders to authenticated;
grant select, insert on public.reviews to anon, authenticated;
grant select on public.visits to authenticated;
