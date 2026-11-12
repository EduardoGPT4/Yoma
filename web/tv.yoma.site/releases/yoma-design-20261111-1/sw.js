'use strict';
const RELEASE = 'yoma-design-20261111-1';
const CACHE = 'seasonav1-public-yoma-design-20261111-1';
const ROOT = new URL('./', self.location.href);
const FILES = [
  'releases/yoma-design-20261111-1/offline.html',
  'releases/yoma-design-20261111-1/assets/offline.js',
  'releases/yoma-design-20261111-1/assets/theme.js',
  'releases/yoma-design-20261111-1/assets/sidebar.js',
  'releases/yoma-design-20261111-1/assets/app.js',
  'releases/yoma-design-20261111-1/assets/catalog.js',
  'releases/yoma-design-20261111-1/assets/catalog-tools.js',
  'releases/yoma-design-20261111-1/assets/account.js',
  'releases/yoma-design-20261111-1/assets/account-avatar.js',
  'releases/yoma-design-20261111-1/assets/bridge.js',
  'releases/yoma-design-20261111-1/assets/bridge-ui.js',
  'releases/yoma-design-20261111-1/assets/downloads.js',
  'releases/yoma-design-20261111-1/assets/state-client.js',
  'releases/yoma-design-20261111-1/assets/transport.js',
  'releases/yoma-design-20261111-1/assets/dom-renderer.js',
  'releases/yoma-design-20261111-1/assets/health-ui.js',
  'releases/yoma-design-20261111-1/assets/player-view.js',
  'releases/yoma-design-20261111-1/assets/player-layout.js',
  'releases/yoma-design-20261111-1/assets/mobile-player.js',
  'releases/yoma-design-20261111-1/assets/mobile-app.js',
  'releases/yoma-design-20261111-1/assets/mobile-app.css',
  'releases/yoma-design-20261111-1/assets/app-downloads.js',
  'releases/yoma-design-20261111-1/assets/app-releases.json',
  'releases/yoma-design-20261111-1/assets/player-shelves.js',
  'releases/yoma-design-20261111-1/assets/player-template.js',
  'releases/yoma-design-20261111-1/assets/personal-ui.js',
  'releases/yoma-design-20261111-1/assets/queue-api.js',
  'releases/yoma-design-20261111-1/assets/library-view.js',
  'releases/yoma-design-20261111-1/assets/library-transfer.js',
  'releases/yoma-design-20261111-1/assets/feature-ui.js',
  'releases/yoma-design-20261111-1/assets/notification-panel.js',
  'releases/yoma-design-20261111-1/assets/player-controller.js',
  'releases/yoma-design-20261111-1/assets/player-experience.js',
  'releases/yoma-design-20261111-1/assets/experience-ui.js',
  'releases/yoma-design-20261111-1/assets/accessibility.js',
  'releases/yoma-design-20261111-1/assets/radio-library.js',
  'releases/yoma-design-20261111-1/assets/mal-ui.js',
  'releases/yoma-design-20261111-1/assets/radio.js',
  'releases/yoma-design-20261111-1/assets/radio-view.js',
  'releases/yoma-design-20261111-1/assets/pwa.js',
  'releases/yoma-design-20261111-1/assets/app.css',
  'releases/yoma-design-20261111-1/assets/features.css',
  'releases/yoma-design-20261111-1/assets/fonts.css',
  'releases/yoma-design-20261111-1/assets/medianoche.css',
  'releases/yoma-design-20261111-1/assets/yoma.css',
  'releases/yoma-design-20261111-1/assets/yoma-anime.png',
  'releases/yoma-design-20261111-1/assets/fonts/dm-sans-400-latin.woff2',
  'releases/yoma-design-20261111-1/assets/fonts/dm-sans-500-latin.woff2',
  'releases/yoma-design-20261111-1/assets/fonts/dm-sans-600-latin.woff2',
  'releases/yoma-design-20261111-1/assets/fonts/dm-sans-700-latin.woff2',
  'releases/yoma-design-20261111-1/assets/fonts/shippori-mincho-b1-700-latin.woff2',
  'releases/yoma-design-20261111-1/assets/fonts/shippori-mincho-b1-800-latin.woff2',

  'releases/yoma-design-20261111-1/assets/icon-192.png',
  'releases/yoma-design-20261111-1/assets/icon-32.png',
  'releases/yoma-design-20261111-1/assets/icon-180.png',
  'releases/yoma-design-20261111-1/assets/icon-512.png',
  'releases/yoma-design-20261111-1/data/offline-catalog.json',
];
self.addEventListener('message',event=>{if(event.data?.type==='ACTIVATE_UPDATE')self.skipWaiting();});
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
      .then(() => undefined)
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
      fetch(req).catch(() => caches.match(new URL('releases/yoma-design-20261111-1/offline.html', ROOT)))
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
            const isIndex = [PUBLIC_INDEX,'releases/yoma-design-20261111-1/data/offline-catalog.json'].some(p=>url.pathname===new URL(p,ROOT).pathname);
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
