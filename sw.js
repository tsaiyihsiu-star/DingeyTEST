const CACHE_NAME = 'TESTtodo-v502.49';

// 核心本地檔：同源、可靠 → 原子式快取（必須全部成功）
const CORE_ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './icon.png'
];
// 外部資源：非致命 → 抓不到就略過，不讓它拖垮整個安裝
const EXTRA_ASSETS = [
  'https://cdn.jsdelivr.net/npm/idb-keyval@6/dist/umd/index.js'
];

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(CORE_ASSETS);                                // 核心：全有或全無
    await Promise.allSettled(EXTRA_ASSETS.map(u => cache.add(u)));  // 外部：非致命
  })());
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map(k => (k !== CACHE_NAME ? caches.delete(k) : null)));  // 此時核心已快取，刪舊才安全
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;   // 只接管 GET；同步等 POST 交給網路自己處理

  // 導覽請求（從主畫面開啟 App）：快取優先，離線且沒對到時 fallback 到 index.html → 保證離線開得起來
  if (req.mode === 'navigate') {
    e.respondWith((async () => {
      const cached = await caches.match(req, { ignoreSearch: true });
      if (cached) return cached;
      try { return await fetch(req); }
      catch (err) {
        return (await caches.match('./index.html'))
            || (await caches.match('./'))
            || Response.error();
      }
    })());
    return;
  }

  // 其他資源：快取優先、網路 fallback
  e.respondWith(
    caches.match(req).then(r => r || fetch(req).catch(() => r || Response.error()))
  );
});
