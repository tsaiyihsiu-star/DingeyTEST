-- ============================================================
-- 宜修待辦 資料庫結構 v2
-- 規則:結構變更一律先改此檔,再到 test-todo 與 yihsiu-todo 兩邊執行
-- v1: 2026-07-07 驗證原型用最小結構(tasks)
-- v2: 2026-07-07 完整結構(依 GAS v502.53 翻譯 + 四項決策定案)
--   決策1: TaskOps/CustomerOps 不搬(增量同步改用 updated_at)
--   決策2: 任務 ID 用 text 型別、值放 uuid(舊 T- 格式 ID 相容,舊備份可還原)
--   決策3: 客戶主從模型照搬(group_key 雙重語意保留);編號唯一約束改由資料庫強制
--   決策4: TaskCount/FirstSeen/LastSeen 不搬,需要時即算
-- ============================================================

-- ---------- 共用: updated_at 自動更新觸發器 ----------
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ============================================================
-- 1. tasks 任務(原 Tasks 工作表)
-- ============================================================
-- ⚠ 全量重建腳本:執行即清空以下 8 張表的所有資料
-- 開發期(無正式資料)可直接跑;未來有正式資料後,結構變更改走增量 migration
drop table if exists tasks, customers, customer_contacts, categories,
  external_links, user_settings, export_logs, sync_logs cascade;
create table tasks (
  id            text primary key,                       -- 新資料放 uuid 字串;舊 T- 格式相容
  owner_id      uuid not null default auth.uid(),
  title         text not null,                          -- 原 Task
  category      text not null default '',               -- 原 Category(存分類名,同現況)
  due_date      date,                                   -- 原 DueDate(舊資料序號值於搬遷時轉換)
  status        text not null default 'Pending',        -- 原 Status(Pending/Done)
  priority      int  not null default 99,               -- 原 Priority(99=未排序)
  note          text not null default '',               -- 原 Note
  customer      text not null default '',               -- 原 Customer(存客戶名稱,聚合依名稱走主從)
  customer_hint text not null default '',               -- 原 CustomerHint
  photos        jsonb not null default '[]',            -- 原 Photos(Drive 檔案 ID 陣列,格式不變)
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()      -- 原 mTime;增量同步依據
);
alter table tasks enable row level security;
create policy "own_data" on tasks for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create index idx_tasks_sync on tasks(owner_id, updated_at);   -- 增量同步主索引
create index idx_tasks_customer on tasks(owner_id, customer); -- 客戶聚合查詢
create trigger trg_tasks_updated before update on tasks
  for each row execute function set_updated_at();

-- ============================================================
-- 2. customers 客戶(原 Customers 工作表)
--    不搬: FirstSeen/LastSeen/TaskCount(決策4,由 tasks 即算)
-- ============================================================
create table customers (
  id           text primary key default gen_random_uuid()::text,
  owner_id     uuid not null default auth.uid(),
  name         text not null,                           -- 客戶名稱(前端主要識別)
  cust_code    text not null default '',                -- 原 CustCode 客戶編號(匯入比對第一優先)
  group_id     text not null default '',                -- 原 GroupId(同組=同 ID;空=獨立)
  role         text not null default '',                -- 原 Role(''/master/sub)
  master_key   text not null default '',                -- 原 MasterKey(子記主的 GroupId)
  is_stop_word boolean not null default false,          -- 原 IsStopWord
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (owner_id, name)                               -- 名稱為業務識別,同人內唯一
);
alter table customers enable row level security;
create policy "own_data" on customers for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- 編號唯一(空值除外):取代舊架構手動 checkDuplicateCustCode 掃描
create unique index idx_customers_code on customers(owner_id, cust_code)
  where cust_code <> '';
create index idx_customers_sync on customers(owner_id, updated_at);
create index idx_customers_group on customers(owner_id, group_id);
create trigger trg_customers_updated before update on customers
  for each row execute function set_updated_at();

-- ============================================================
-- 3. customer_contacts 客戶聯絡資料(原 CustomerContacts 工作表)
--    group_key 雙重語意照搬:有分組=GroupId、歷史舊資料=客戶名
-- ============================================================
create table customer_contacts (
  id         text primary key,                          -- 原 RowID(C...);新資料放 uuid
  owner_id   uuid not null default auth.uid(),
  group_key  text not null,                             -- 原 GroupKey(掛載鍵)
  type       text not null default 'note',              -- 原 Type(address/phone/note...)
  label      text not null default '',                  -- 原 Label
  content    text not null default '',                  -- 原 Content
  sort_order int  not null default 0,                   -- 原 SortOrder
  origin     text not null default '',                  -- 原 Origin(匯入來源公司簡稱)
  nav_fix    text not null default '',                  -- 原 NavFix(座標字串,格式照舊)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table customer_contacts enable row level security;
create policy "own_data" on customer_contacts for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create index idx_contacts_group on customer_contacts(owner_id, group_key, sort_order);
create index idx_contacts_sync on customer_contacts(owner_id, updated_at);
-- 匯入判重(同 GroupKey+Type+Content 跳過)改由資料庫強制
create unique index idx_contacts_dedup
  on customer_contacts(owner_id, group_key, type, md5(content));
create trigger trg_contacts_updated before update on customer_contacts
  for each row execute function set_updated_at();

-- ============================================================
-- 4. categories 分類(原 Categories 工作表)
-- ============================================================
create table categories (
  id         text primary key default gen_random_uuid()::text,
  owner_id   uuid not null default auth.uid(),
  name       text not null,                             -- 原 Category Name
  sort_order int  not null default 0,
  color      text not null default '#007AFF',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, name)
);
alter table categories enable row level security;
create policy "own_data" on categories for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create index idx_categories_sync on categories(owner_id, updated_at);
create trigger trg_categories_updated before update on categories
  for each row execute function set_updated_at();

-- ============================================================
-- 5. external_links 外部連結(原 ExternalLinks 工作表)
-- ============================================================
create table external_links (
  id         text primary key,                          -- 原 Id(L...);新資料放 uuid
  owner_id   uuid not null default auth.uid(),
  name       text not null,
  url        text not null,
  sort_order int  not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table external_links enable row level security;
create policy "own_data" on external_links for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create index idx_extlinks_sync on external_links(owner_id, updated_at);
create trigger trg_extlinks_updated before update on external_links
  for each row execute function set_updated_at();

-- ============================================================
-- 6. user_settings 個人設定(新;原 Settings 密碼廢除,由 Auth 取代)
--    Gemini key、偏好設定;一人一列
-- ============================================================
create table user_settings (
  owner_id       uuid primary key default auth.uid(),
  gemini_api_key text not null default '',              -- 使用者自備 key(匯出備份時排除)
  prefs          jsonb not null default '{}',           -- 字級/音效等偏好
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
alter table user_settings enable row level security;
create policy "own_data" on user_settings for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create trigger trg_settings_updated before update on user_settings
  for each row execute function set_updated_at();

-- ============================================================
-- 7. export_logs 匯出紀錄(新;藍圖定案:單日第2次告警、上限3次)
-- ============================================================
create table export_logs (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null default auth.uid(),
  exported_at timestamptz not null default now(),
  row_counts  jsonb not null default '{}',              -- 各表筆數 {"tasks":210,...}
  note        text not null default ''
);
alter table export_logs enable row level security;
create policy "own_data" on export_logs for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create index idx_export_daily on export_logs(owner_id, exported_at);

-- ============================================================
-- 8. sync_logs 全量同步紀錄(新;藍圖定案:reason 歸因、manual_reset 告警)
-- ============================================================
create table sync_logs (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null default auth.uid(),
  occurred_at timestamptz not null default now(),
  reason      text not null,                            -- manual_reset/account_switch/fresh_install
  meta        jsonb not null default '{}'
);
alter table sync_logs enable row level security;
create policy "own_data" on sync_logs for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create index idx_sync_daily on sync_logs(owner_id, occurred_at);

-- ============================================================
-- 不建立的表(明確記錄,防止未來誤加)
-- - TaskOps / CustomerOps: 決策1,增量同步由 updated_at 索引取代,
--   離線佇列保留在前端 IndexedDB
-- - Settings(password): Supabase Auth 取代
-- - licenses 授權表: 依「授權在認證之後」原則,待邀請碼機制設計時
--   另立 v3,啟用前先為既有使用者插入永久有效紀錄
-- ============================================================
