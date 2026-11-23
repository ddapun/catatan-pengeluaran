-- Skema awal Catatan Pengeluaran
-- Semua tabel memakai UUID dari klien dan soft delete agar sinkronisasi offline aman.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  currency text not null default 'IDR',
  created_at timestamptz not null default now()
);

create table public.categories (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  type text not null check (type in ('expense', 'income')),
  color text,
  icon text,
  archived_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index categories_user_idx on public.categories (user_id);

create table public.transactions (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  type text not null check (type in ('expense', 'income')),
  amount bigint not null check (amount > 0),
  category_id uuid references public.categories (id),
  note text,
  occurred_on date not null,
  receipt_path text,
  source text not null default 'app' check (source in ('app', 'whatsapp')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index transactions_user_date_idx on public.transactions (user_id, occurred_on);
create index transactions_user_cat_date_idx on public.transactions (user_id, category_id, occurred_on);

create table public.budgets (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  category_id uuid not null references public.categories (id),
  month date not null,
  limit_amount bigint not null check (limit_amount > 0),
  updated_at timestamptz not null default now(),
  unique (user_id, category_id, month)
);

create index budgets_user_month_idx on public.budgets (user_id, month);

create table public.wa_links (
  user_id uuid primary key references auth.users (id) on delete cascade,
  phone_e164 text unique not null,
  verified_at timestamptz,
  verify_code text,
  verify_expires_at timestamptz,
  pending jsonb,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Profil otomatis saat pendaftaran
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets enable row level security;
alter table public.wa_links enable row level security;

create policy "profil milik sendiri" on public.profiles
  for all using (id = auth.uid()) with check (id = auth.uid());

create policy "kategori milik sendiri" on public.categories
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "transaksi milik sendiri" on public.transactions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "anggaran milik sendiri" on public.budgets
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Hanya boleh membaca status tautan sendiri; pembuatan kode lewat RPC di bawah.
create policy "tautan wa milik sendiri" on public.wa_links
  for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Fungsi bantu
-- ---------------------------------------------------------------------------

-- Normalisasi nomor Indonesia ke format E.164 (+62...).
create or replace function public.normalize_phone(p_phone text)
returns text
language plpgsql
immutable
as $$
declare
  digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
  if digits like '0%' then
    digits := '62' || substr(digits, 2);
  elsif digits like '8%' then
    digits := '62' || digits;
  end if;
  if length(digits) < 9 or length(digits) > 15 then
    raise exception 'Nomor WhatsApp tidak valid';
  end if;
  return '+' || digits;
end;
$$;

-- Minta kode verifikasi; kode dikirim pengguna ke bot lewat WhatsApp.
create or replace function public.request_whatsapp_link(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.normalize_phone(p_phone);
  v_code text := lpad((floor(random() * 1000000))::int::text, 6, '0');
begin
  insert into public.wa_links (user_id, phone_e164, verify_code, verify_expires_at, verified_at, pending, updated_at)
  values (auth.uid(), v_phone, v_code, now() + interval '15 minutes', null, null, now())
  on conflict (user_id) do update
    set phone_e164 = excluded.phone_e164,
        verify_code = excluded.verify_code,
        verify_expires_at = excluded.verify_expires_at,
        verified_at = null,
        pending = null,
        updated_at = now();
  return jsonb_build_object('phone_e164', v_phone, 'verify_code', v_code, 'expires_at', now() + interval '15 minutes');
end;
$$;

create or replace function public.unlink_whatsapp()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.wa_links where user_id = auth.uid();
$$;

-- Hapus akun beserta seluruh data (dipakai dari layar Pengaturan).
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;

-- Ringkasan bulanan di server (dipakai bot WhatsApp dan ekspor).
create or replace function public.monthly_summary(p_month date)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  with bounds as (
    select date_trunc('month', p_month)::date as start_on,
           (date_trunc('month', p_month) + interval '1 month - 1 day')::date as end_on
  ),
  rows as (
    select t.type, t.amount, t.category_id, c.name as category_name
    from public.transactions t
    left join public.categories c on c.id = t.category_id
    cross join bounds b
    where t.user_id = auth.uid()
      and t.deleted_at is null
      and t.occurred_on between b.start_on and b.end_on
  )
  select jsonb_build_object(
    'month', to_char(p_month, 'YYYY-MM'),
    'expense', coalesce(sum(amount) filter (where type = 'expense'), 0),
    'income', coalesce(sum(amount) filter (where type = 'income'), 0),
    'by_category', coalesce((
      select jsonb_agg(jsonb_build_object('category_id', category_id, 'name', category_name, 'total', total) order by total desc)
      from (
        select category_id, max(category_name) as category_name, sum(amount) as total
        from rows where type = 'expense'
        group by category_id
      ) s
    ), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------------
-- Storage foto struk (bucket privat)
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

create policy "struk milik sendiri" on storage.objects
  for all
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- Hak eksekusi RPC
-- ---------------------------------------------------------------------------

grant execute on function public.request_whatsapp_link(text) to authenticated;
grant execute on function public.unlink_whatsapp() to authenticated;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.monthly_summary(date) to authenticated;
