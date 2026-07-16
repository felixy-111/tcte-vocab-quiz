-- ============================================================
-- 統測字彙練習 App — Supabase 資料表設定
-- 使用方式：到 Supabase 專案 → SQL Editor → 貼上整份 → Run
--
-- ⚠️ 開雲端前「必做」：
--   Supabase → Authentication → Providers → Email →
--   關閉「Allow new users to sign up」（自助註冊）。
--   不關的話，任何知道網址的人都能自己註冊帳號、變成有全權的「老師」，
--   讀寫所有學生與成績。老師帳號請改用「Add user」手動建立。
--
-- 三張表：
--   students    學生名單
--   assignments 老師派出的線上卷（含代碼）
--   attempts    每一題的作答結果（紙本批改 mode='paper'／線上 mode='online'）
--
-- 權限（RLS，資料列安全鎖）設計：
--   老師（登入後 authenticated）：三張表全權讀寫。
--   學生端（未登入 anon）：
--     · students   只能 SELECT（挑自己的名字）→ 名字請用暱稱，見 README
--     · assignments 只能 SELECT（用代碼開卷）
--     · attempts   只能 INSERT，且限 mode='online'（紙本批改只有老師能寫）；
--                  不能讀、不能改、不能刪 → 學生看不到、也改不了任何成績。
-- ============================================================

create table if not exists students (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  archived   boolean not null default false,   -- 封存（不再顯示於挑選清單）
  updated_at timestamptz not null default now()
);

create table if not exists assignments (
  id           uuid primary key default gen_random_uuid(),
  code         text unique not null,           -- 6 碼易讀代碼，如 A3F7KQ
  student_id   uuid references students(id),    -- 可為 null（不指定學生）
  title        text not null,
  question_ids jsonb not null default '[]',     -- 題目 id 陣列
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists attempts (
  id          uuid primary key default gen_random_uuid(),
  student_id  uuid not null references students(id),        -- 綁真學生，擋偽造 id
  question_id text not null check (char_length(question_id) < 120),
  word        text not null check (char_length(word) < 100),
  paper_ref   text not null check (char_length(paper_ref) < 200),
  correct     boolean not null,
  mode        text not null check (mode in ('paper', 'online')),
  answered_at timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 加速常用查詢
create index if not exists attempts_student_idx on attempts (student_id);
create index if not exists attempts_paper_idx   on attempts (student_id, paper_ref, mode);

-- ============================================================
-- 開啟 RLS
-- ============================================================
alter table students    enable row level security;
alter table assignments enable row level security;
alter table attempts    enable row level security;

-- ---- 老師（authenticated）：三張表全權 ----
create policy "auth_all_students"    on students    for all to authenticated using (true) with check (true);
create policy "auth_all_assignments" on assignments for all to authenticated using (true) with check (true);
create policy "auth_all_attempts"    on attempts    for all to authenticated using (true) with check (true);

-- ---- 學生端（anon）：最小權限 ----
create policy "anon_select_students"    on students    for select to anon using (true);
create policy "anon_select_assignments" on assignments for select to anon using (true);
-- 只能寫入 mode='online'：紙本批改（paper）一律被擋，只有老師能寫。
create policy "anon_insert_attempts"    on attempts    for insert to anon with check (mode = 'online');
-- 注意：故意不給 anon 對 attempts 的 select／update／delete，
--       所以學生端只能「寫入自己的線上作答」，讀不到、改不了任何人的成績。

-- ============================================================
-- 給既有使用者的欄位補充（migration）
-- 若你之前建過 students 表卻沒有 archived 欄位，補跑這行即可（重複跑也安全）。
-- ============================================================
alter table students add column if not exists archived boolean not null default false;

-- ============================================================
-- （選用）進一步強化：把老師權限綁到「你自己的帳號 uid」
--
-- 上面的 authenticated 政策是「任何登入帳號都全權」。只要你有照最上面的
-- 警告關掉自助註冊、且只手動建自己一個帳號，這樣已經夠安全。
--
-- 若想更保險（例如日後可能多開帳號），可把老師權限鎖到單一 uid：
--   1. Supabase → Authentication → Users → 點你自己的帳號 → 複製 User UID
--   2. 把下面每個 '00000000-0000-0000-0000-000000000000' 換成你的 UID
--   3. 先 drop 掉上面三條 auth_all_* 政策，再跑這段
--
-- drop policy "auth_all_students"    on students;
-- drop policy "auth_all_assignments" on assignments;
-- drop policy "auth_all_attempts"    on attempts;
--
-- create policy "owner_students"    on students    for all to authenticated
--   using (auth.uid() = '00000000-0000-0000-0000-000000000000')
--   with check (auth.uid() = '00000000-0000-0000-0000-000000000000');
-- create policy "owner_assignments" on assignments for all to authenticated
--   using (auth.uid() = '00000000-0000-0000-0000-000000000000')
--   with check (auth.uid() = '00000000-0000-0000-0000-000000000000');
-- create policy "owner_attempts"    on attempts    for all to authenticated
--   using (auth.uid() = '00000000-0000-0000-0000-000000000000')
--   with check (auth.uid() = '00000000-0000-0000-0000-000000000000');
-- ============================================================
