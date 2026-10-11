const CACHE = 'dedalo-v1';
const PRECACHE = [
    '/',
    '/index.html',
    '/manifest.json',
];

self.addEventListener('install', e => {
    e.waitUntil(
        caches.open(CACHE).then(c => c.addAll(PRECACHE))
            .then(() => self.skipWaiting())
    );
});

self.addEventListener('activate', e => {
    e.waitUntil(
        caches.keys().then(keys =>
            Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
        ).then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', e => {
    const url = new URL(e.request.url);

    // Always network-first for ROM downloads (they're huge and external)
    if (url.hostname !== location.hostname) {
        return; // don't intercept external (CDN, ROM hosts)
    }

    // Cache-first for our own pages
    e.respondWith(
        caches.match(e.request).then(hit => hit || fetch(e.request).then(res => {
            if (res && res.status === 200) {
                const clone = res.clone();
                caches.open(CACHE).then(c => c.put(e.request, clone));
            }
            return res;
        }))
    );
});
