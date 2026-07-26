const CACHE_NAME = "dastarkhwan-pos-v3";
const SHELL_FILES = [
  "pos.html",
  "css/style.css",
  "js/config.js",
  "js/supabaseClient.js",
  "manifest.json",
  "icons/icon-192.png",
  "icons/icon-512.png",
  "branding/chai-jaan-logo.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
    )
  );
  self.clients.claim();
});

// Network-first for the app shell files (HTML/CSS/JS/icons): always try
// to fetch the latest version first, so a code update shows up on the
// very next open — not "one load behind", which is what a cache-first
// strategy does (serve the old cached copy immediately, only refresh the
// cache quietly in the background for NEXT time). Cache is only used as
// a fallback when there's genuinely no signal, so the till still opens
// offline. Live data (menu, orders, PIN checks) still goes over the
// network every time regardless — this only covers the app shell.
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  const isShellFile = SHELL_FILES.some((f) => url.pathname.endsWith(f));
  if (!isShellFile) return;

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, response.clone()));
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});
