-- ふたりの家計簿：Supabase 初期設定（SQL Editor に貼り付けて Run）
-- 何度実行しても壊れないように書いてあります（作り直し・再実行OK）

-- 1) 支出テーブル（日時は、アプリと同じ 'YYYY/MM/DD HH:mm' 形式の文字列で保存）
create table if not exists public.expenses (
  id            text primary key,
  date          text not null,
  amount        bigint not null default 0,
  category      text not null default '',
  store         text not null default '',
  memo          text not null default '',
  payer         text not null default '夫',
  receipt_image text,
  created_at    text not null default '',
  created_by    text not null default '',
  updated_by    text not null default '',
  updated_at    text not null default '',
  history       jsonb not null default '[]'::jsonb,
  -- 一覧取得時に写真本体を転送せずに「写真あり」を判定するための列
  has_image     boolean generated always as (receipt_image is not null) stored,
  -- 写真の参照（なし=null／行内の旧形式 Base64='data'／Storage 上のパス）。一覧取得で写真本体を転送せずに差分を判定する
  image_ref     text generated always as (case when receipt_image like 'data:%' then 'data' else receipt_image end) stored
);

-- 既存のテーブル（以前のSQLで作成済み）にも image_ref 列を追加（新規作成時は何もしない）
alter table public.expenses add column if not exists image_ref text
  generated always as (case when receipt_image like 'data:%' then 'data' else receipt_image end) stored;

-- 2) 共有設定テーブル（カテゴリ・色・店舗マスター・月別予算・タイトル/名前を key ごとに保存）
create table if not exists public.household (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now()
);

-- 3) アクセス権（ログイン不要＝URLとキーを知っている端末だけが読み書きできる構成）
alter table public.expenses  enable row level security;
alter table public.household enable row level security;

grant usage on schema public to anon;
-- ※ Supabase は新しいテーブルに anon へ全権限（delete / truncate 等）を自動付与するため、いったん外してから必要な分だけ付け直す
revoke all on public.expenses  from anon;
revoke all on public.household from anon;
grant select, insert, update on public.expenses  to anon;
grant select, insert, update on public.household to anon;
-- ※ delete は許可しません（アプリに削除機能がないため。キー漏えい時の被害を減らします）

drop policy if exists "anon read expenses"   on public.expenses;
drop policy if exists "anon insert expenses" on public.expenses;
drop policy if exists "anon update expenses" on public.expenses;
create policy "anon read expenses"   on public.expenses for select to anon using (true);
create policy "anon insert expenses" on public.expenses for insert to anon with check (true);
create policy "anon update expenses" on public.expenses for update to anon using (true) with check (true);

drop policy if exists "anon read household"   on public.household;
drop policy if exists "anon insert household" on public.household;
drop policy if exists "anon update household" on public.household;
create policy "anon read household"   on public.household for select to anon using (true);
create policy "anon insert household" on public.household for insert to anon with check (true);
create policy "anon update household" on public.household for update to anon using (true) with check (true);

-- 4) リアルタイム配信を有効化（すでに登録済みなら何もしない）
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'expenses') then
    alter publication supabase_realtime add table public.expenses;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'household') then
    alter publication supabase_realtime add table public.household;
  end if;
end $$;

-- 5) レシート写真の保管場所（Storage）。非公開バケット＋「読む・追加する」だけを許可（削除・上書きは不可）
--    写真本体はここに置き、支出の行にはパス（r/<id>_<hash>.jpg）だけを持たせる＝データベースが肥大化しない
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "anon read receipts"   on storage.objects;
drop policy if exists "anon insert receipts" on storage.objects;
create policy "anon read receipts"   on storage.objects for select to anon using (bucket_id = 'receipts');
create policy "anon insert receipts" on storage.objects for insert to anon with check (bucket_id = 'receipts');
