// Same file as src/main/resources/static/firebase-messaging-sw.js (keep both in sync).
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');
importScripts('/firebase-config.js');

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(clients.claim()));

firebase.initializeApp(self.FIREBASE_CONFIG);
const messaging = firebase.messaging();

// Messages that carry a "notification" block are displayed by the FCM SDK itself.
// Data-only messages are displayed here.
messaging.onBackgroundMessage((payload) => {
  if (payload.notification) return;
  const d = payload.data || {};
  self.registration.showNotification(d.title || 'Thông báo', {
    body: d.body || '',
    icon: '/icon-192.png',
    data: d,
  });
});

// Focus the open tab if there is one, otherwise open the app.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if ('focus' in c) return c.focus();
      }
      return clients.openWindow('/');
    })
  );
});
