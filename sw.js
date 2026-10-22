// يمسح النسخة القديمة المخزّنة ثم يلغي نفسه
self.addEventListener('install',e=>self.skipWaiting());
self.addEventListener('activate',e=>e.waitUntil(
  caches.keys().then(k=>Promise.all(k.map(c=>caches.delete(c))))
  .then(()=>self.registration.unregister())
  .then(()=>self.clients.matchAll())
  .then(cs=>cs.forEach(c=>c.navigate(c.url)))));
