/* DM Record — cleanup worker.
   The earlier version cached a broken copy of the app. This replacement
   deletes those caches, unregisters itself, and reloads any open tab so
   the fresh version loads. Offline caching will be added back later,
   once the app is confirmed working. */
self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => caches.delete(k)));
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: "window" });
    clients.forEach((client) => client.navigate(client.url));
  })());
});
