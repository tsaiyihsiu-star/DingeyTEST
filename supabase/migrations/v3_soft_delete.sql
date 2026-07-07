-- ============================================================
-- 宜修待辦 schema v3 (增量 migration)
-- 前提: 已執行 v2;本檔為 alter 模式,不清除任何資料
-- 執行順序: test-todo 先跑並驗證,再跑 yihsiu-todo
--
-- v3: 2026-07-07 刪除機制與還原世代
--   1. 軟刪除欄位 deleted: 服務「日常手動刪除」的跨裝置同步
--      (定期清理走規則式真刪,不經此欄;規則雲端/本地各自執行)
--   2. 部分索引: 活資料查詢不受已刪資料影響
--   3. user_settings.data_generation: 還原紀元號
--      還原成功 +1;裝置同步前核對,不一致即放棄本地全量重拉
-- ============================================================

begin;

-- ---------- 1. 軟刪除欄位(五張同步表) ----------
alter table tasks             add column if not exists deleted boolean not null default false;
alter table customers         add column if not exists deleted boolean not null default false;
alter table customer_contacts add column if not exists deleted boolean not null default false;
alter table categories        add column if not exists deleted boolean not null default false;
alter table external_links    add column if not exists deleted boolean not null default false;

-- ---------- 2. 活資料部分索引 ----------
-- 增量同步索引維持全量(deleted 變更也要被拉取);另建活資料索引供列表查詢
create index if not exists idx_tasks_alive
  on tasks(owner_id, status, due_date) where deleted = false;
create index if not exists idx_contacts_alive
  on customer_contacts(owner_id, group_key, sort_order) where deleted = false;

-- ---------- 3. 還原紀元號 ----------
alter table user_settings add column if not exists data_generation int not null default 1;

commit;

-- ============================================================
-- 附註(規則式清理,不在本檔執行,由前端定期節流執行):
--   週期清理: delete from tasks
--             where status='Done' and updated_at < now() - interval '12 months';
--   清墓:     delete from <表>
--             where deleted = true and updated_at < now() - interval '90 days';
--   照片清理(前端持 drive.file token 執行):
--             Done 滿 30 天 → Drive 檔案丟垃圾桶 + photos 清空
-- ============================================================
