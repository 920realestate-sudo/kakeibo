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
  has_image     boolean generated always as (receipt_image is not null) stored
);

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
