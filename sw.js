// ============================================================
// 宜修待辦 Supabase 世代 Service Worker
// 【切換日部署用】開發測試期間不啟用(supa-test-todo.html 目前主動解除 SW)
// 切換日三件事(同一個 commit):
//   1. 本檔改名 sw.js 覆蓋舊檔,CORE_ASSETS 的頁面改成接管後的 index.html
//   2. CACHE_NAME 與 APP_VERSION 同步 bump
//   3. 前端把「解除註冊」改回「註冊 sw.js」
// ============================================================
const CACHE_NAME = 'SUPATESTtodo-v600.65';   // 每次改版必同步 bump

const CORE_ASSETS = [
  './',
  './index.html',        // 切換日:v600 接管 index.html 後生效
  './manifest.json',
  './icon.png',
  './version.json'
];
// 外部資源:非致命,抓不到就略過
// v600 重要:supabase-js 必須快取——離線開 App 時認證閘才起得來(getSession 走本機)
const EXTRA_ASSETS = [
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2'
];

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(CORE_ASSETS);                                // 核心:全有或全無
    await Promise.allSettled(EXTRA_ASSETS.map(u => cache.add(u)));  // 外部:非致命
  })());
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map(k => (k !== CACHE_NAME ? caches.delete(k) : null)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  // version.json 永遠走網路優先(版本檢查要即時;離線退快取)
  if (req.url.includes('version.json')) {
    e.respondWith(fetch(req).catch(() => caches.match(req, { ignoreSearch: true })));
    return;
  }
  // Supabase/Google API 一律不快取(資料與認證必須即時)
  if (req.url.includes('supabase.co') || req.url.includes('googleapis.com')
      || req.url.includes('script.google.com') || req.url.includes('generativelanguage')) return;
  if (req.mode === 'navigate') {
    e.respondWith((async () => {
      const cached = await caches.match(req, { ignoreSearch: true });
      if (cached) return cached;
      try { return await fetch(req); }
      catch (err) {
        return (await caches.match('./index.html')) || (await caches.match('./')) || Response.error();
      }
    })());
    return;
  }
  e.respondWith(
    caches.match(req).then(r => r || fetch(req).catch(() => r || Response.error()))
  );
});
