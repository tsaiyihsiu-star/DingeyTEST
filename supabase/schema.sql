-- 宜修待辦 資料庫結構
-- 規則:結構變更一律先改此檔,再到 test-todo 與 yihsiu-todo 兩邊執行
-- v1: 2026-07-07 初版(驗證原型用最小結構)

create table tasks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  title text not null,
  status text default 'todo',
  updated_at timestamptz default now()
);

alter table tasks enable row level security;

create policy "own_data" on tasks
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create index idx_tasks_owner on tasks(owner_id);
