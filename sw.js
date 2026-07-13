/* DM Record — minimal service worker.
   Caches the app shell so it installs to the home screen and opens
   even with no signal. Live data (readings, stats) always needs a
   connection to Supabase. Bump CACHE when you change these files. */
const CACHE = "dm-record-v1";
const SHELL = ["./", "./index.html", "./manifest.json",
               "./apple-touch-icon.png", "./icon-192.png", "./icon-512.png"];

self.addEventListener("install", (e)=>{
  e.waitUntil(caches.open(CACHE).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting()));
});
self.addEventListener("activate", (e)=>{
  e.waitUntil(caches.keys().then(keys=>
    Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))
  ).then(()=>self.clients.claim()));
});
self.addEventListener("fetch", (e)=>{
  const url = new URL(e.request.url);
  // Never cache Supabase / cross-origin API calls — always go to network.
  if(url.origin !== self.location.origin){ return; }
  // App shell: cache-first, fall back to network.
  e.respondWith(
    caches.match(e.request).then(hit => hit || fetch(e.request))
  );
});
