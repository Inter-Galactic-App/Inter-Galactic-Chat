self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

function parsePushPayload(event) {
  if (!event.data) {
    return {};
  }

  try {
    return event.data.json();
  } catch (_) {
    const text = event.data.text();

    try {
      return JSON.parse(text);
    } catch (_) {
      return {
        body: text,
      };
    }
  }
}

function normalizeNotification(payload) {
  const source = payload.notification ?? payload;
  const data = {
    room_id: source.room_id ?? source.roomId ?? null,
    client_id: source.client_id ?? source.clientId ?? null,
    event_id: source.event_id ?? source.eventId ?? null,
    open_url: source.open_url ?? source.url ?? null,
  };

  return {
    title:
      source.title ?? source.senderName ?? source.sender ?? 'Inter Galactic',
    options: {
      body:
        source.body ??
        source.content ??
        'Open Inter Galactic to view this update.',
      icon: source.icon ?? 'icons/Icon-192.png',
      badge: source.badge ?? 'icons/Icon-192.png',
      tag: source.tag ?? data.room_id ?? 'intergalactic-webpush',
      data,
      renotify: true,
    },
  };
}

function isMeaningfullyVisible(client) {
  return client?.visibilityState === 'visible' || client?.focused === true;
}

function isGenericFallbackNotification(notification) {
  if (!notification) {
    return false;
  }

  const title = String(notification.title ?? '').trim().toLowerCase();
  const body = String(notification.options?.body ?? '').trim().toLowerCase();

  return (
    title === 'new inter galactic activity' ||
    title === 'new inter galactic activity' ||
    body === 'open Inter Galactic to view the latest activity.' ||
    body === 'open inter galactic to view this update.' ||
    body === 'open inter galactic to view the latest activity.'
  );
}

async function requestDecryptedNotification(payload) {
  const source = payload.notification ?? payload;
  const roomId = source.room_id ?? source.roomId ?? null;
  const clientId = source.client_id ?? source.clientId ?? null;
  const eventId = source.event_id ?? source.eventId ?? null;

  if (!roomId || !eventId) {
    return null;
  }

  const windowClients = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });

  if (!windowClients.length) {
    return null;
  }

  const requestId =
    'intergalactic-preview-' +
    Math.random().toString(36).slice(2) +
    '-' +
    Date.now().toString(36);

  return new Promise((resolve) => {
    const timeoutId = setTimeout(() => {
      cleanup();
      resolve(null);
    }, 10000);

    function cleanup() {
      clearTimeout(timeoutId);
      self.removeEventListener('message', onMessage);
    }

    function onMessage(event) {
      const data = event.data;
      if (!data || data.type !== 'intergalactic-decrypt-notification-response') {
        return;
      }

      if (data.requestId !== requestId) {
        return;
      }

      if (!data.notification) {
        return;
      }

      cleanup();
      resolve(data.notification);
    }

    self.addEventListener('message', onMessage);

    for (const client of windowClients) {
      client.postMessage({
        type: 'intergalactic-decrypt-notification',
        requestId,
        room_id: roomId,
        client_id: clientId,
        event_id: eventId,
        payload: source,
      });
    }
  });
}

function mergeNotificationPayload(payload, decryptedNotification) {
  if (!decryptedNotification) {
    return payload;
  }

  const source = payload.notification ?? payload;
  const merged = {
    ...source,
    ...decryptedNotification,
  };

  if (source.title && decryptedNotification.body) {
    merged.title = source.title;
  }

  return merged;
}

function unreadCountFromPayload(payload) {
  const source = payload.notification ?? payload;
  const counts = source.counts;
  if (!counts || typeof counts !== 'object') {
    return null;
  }

  const unread = Number(counts.unread);
  if (!Number.isFinite(unread) || unread < 0) {
    return null;
  }

  return Math.trunc(unread);
}

async function updateAppBadge(payload) {
  if (!('setAppBadge' in navigator) || !('clearAppBadge' in navigator)) {
    return;
  }

  const unread = unreadCountFromPayload(payload);
  if (unread === null) {
    return;
  }

  try {
    if (unread > 0) {
      await navigator.setAppBadge(unread);
    } else {
      await navigator.clearAppBadge();
    }
  } catch (_) {
    // Ignore badge update failures on browsers that expose the API but reject it.
  }
}

function buildAppUrl(data) {
  if (data.open_url) {
    return new URL(data.open_url, self.location.origin).toString();
  }

  const appUrl = new URL(self.registration.scope);
  appUrl.pathname = appUrl.pathname.replace(/push-notifications\/?$/, '');

  if (data.room_id) {
    appUrl.searchParams.set('room_id', data.room_id);
  }

  if (data.client_id) {
    appUrl.searchParams.set('client_id', data.client_id);
  }

  return appUrl.toString();
}

self.addEventListener('push', (event) => {
  event.waitUntil(
    (async () => {
      const payload = parsePushPayload(event);
      await updateAppBadge(payload);
      const windowClients = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });

      if (windowClients.some(isMeaningfullyVisible)) {
        return;
      }

      const decryptedNotification = await requestDecryptedNotification(payload);
      const notification = normalizeNotification(
        mergeNotificationPayload(payload, decryptedNotification),
      );

      if (!decryptedNotification && isGenericFallbackNotification(notification)) {
        return;
      }

      return self.registration.showNotification(
        notification.title,
        notification.options,
      );
    })(),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const targetUrl = buildAppUrl(event.notification.data ?? {});

  event.waitUntil(
    self.clients
      .matchAll({
        type: 'window',
        includeUncontrolled: true,
      })
      .then((windowClients) => {
        if (windowClients.length > 0) {
          const client = windowClients[0];

          if ('navigate' in client) {
            return client.navigate(targetUrl).then(() => client.focus());
          }

          return client.focus();
        }

        if (self.clients.openWindow) {
          return self.clients.openWindow(targetUrl);
        }

        return undefined;
      }),
  );
});
