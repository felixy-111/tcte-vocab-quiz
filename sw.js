// 離線快取：把 app 核心檔案快取起來，沒網路也開得起來。
// 改版時把 CACHE 版本號 +1，舊快取會自動清掉。
const CACHE = "tsvt-v3";
const ASSETS = [
  "./", "./index.html", "./manifest.webmanifest",
  "./icon-192.png", "./icon-512.png", "./apple-touch-icon.png",
  "./vendor/supabase.js",
  "./data/manifest.json", "./data/u1_upper.json", "./data/u1_lower.json",
  "./data/u2_upper.json", "./data/u2_lower.json"
];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// 網路優先、失敗回快取。Supabase 網域一律直接走網路（不快取雲端 API）。
self.addEventListener("fetch", (e) => {
  if (e.request.method !== "GET") return;
  if (e.request.url.indexOf("supabase.co") > -1) return;
  e.respondWith(
    fetch(e.request)
      .then((res) => { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); return res; })
      .catch(() => caches.match(e.request).then((r) => r || caches.match("./index.html")))
  );
});
