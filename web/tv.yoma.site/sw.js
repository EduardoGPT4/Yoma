'use strict';
const CACHE = 'seasonav1-public-20261018-experience-v5';
const ROOT = new URL('./', self.location.href);
const FILES = [
  'offline.html',
  'assets/offline.js',
  'assets/theme.js',
  'assets/sidebar.js',
  'assets/app.js',
  'assets/catalog.js',
  'assets/catalog-tools.js',
  'assets/account.js',
  'assets/bridge.js',
  'assets/bridge-ui.js',
  'assets/downloads.js',
  'assets/state-client.js',
  'assets/queue-api.js',
  'assets/library-view.js',
  'assets/library-transfer.js',
  'assets/feature-ui.js',
  'assets/player-controller.js',
  'assets/player-experience.js',
  'assets/experience-ui.js',
  'assets/accessibility.js',
  'assets/radio-library.js',
  'assets/mal-ui.js',
  'assets/radio.js',
  'assets/radio-view.js',
  'assets/pwa.js',
  'assets/app.css',
  'assets/features.css',
  'assets/icon-192.png',
  'assets/icon-32.png',
  'assets/icon-180.png',
  'assets/icon-512.png',
  'data/offline-catalog.json',
];
const PUBLIC_INDEX = 'catalog-public.php';
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) =>
        cache.addAll(
          FILES.map((p) => new Request(new URL(p, ROOT), { cache: 'reload' }))
        )
      )
      .then(() => self.skipWaiting())
  );
});
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((k) => k.startsWith('seasonav1-public-') && k !== CACHE)
            .map((k) => caches.delete(k))
        )
      )
      .then(() => self.clients.claim())
  );
});
self.addEventListener('fetch', (event) => {
  const req = event.request,
    url = new URL(req.url);
  if (req.method !== 'GET') return;
  if (
    req.mode === 'navigate' &&
    url.origin === ROOT.origin &&
    url.pathname.startsWith(ROOT.pathname)
  ) {
    event.respondWith(
      fetch(req).catch(() => caches.match(new URL('offline.html', ROOT)))
    );
    return;
  }
  // API replies, OAuth callbacks, settings, receipts and all private account data are never cached.
  if (
    url.origin === ROOT.origin &&
    url.pathname.startsWith(ROOT.pathname) &&
    [...FILES,PUBLIC_INDEX].some((p) => url.pathname === new URL(p, ROOT).pathname)
  ) {
    event.respondWith(
      caches.open(CACHE).then(async (cache) => {
        const canonical = new URL(url.pathname, url.origin).href;
        const old = await cache.match(canonical);
        try {
          const response = await fetch(req);
          if (response.ok) {
            // The host may return a browser verification page with status 200.
            // Never replace a valid JSON catalog with that HTML response.
            const isIndex = [PUBLIC_INDEX,'data/offline-catalog.json'].some(p=>url.pathname===new URL(p,ROOT).pathname);
            if (!isIndex || (response.headers.get('Content-Type')||'').includes('application/json'))
              await cache.put(canonical,response.clone());
            else if (old) return old;
          }
          if (!response.ok && old) return old;
          return response;
        } catch (error) {
          if (old) return old; // Includes requests such as app.css?v=new when offline.
          throw error;
        }
      })
    );
  }
});
