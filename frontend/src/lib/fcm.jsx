import { useCallback, useEffect, useRef, useState } from 'react';
import { initializeApp, getApps } from 'firebase/app';
import { getMessaging, getToken, deleteToken, onMessage, isSupported } from 'firebase/messaging';
import toast from 'react-hot-toast';
import { registerDevice, subscribeTopic, unregisterDevice, unsubscribeTopic, errorText } from './api';

export const BROADCAST_TOPIC = 'all_devices';
const NAME_KEY = 'fcm-demo:name';

const cfg = () => window.FIREBASE_CONFIG;
export const isConfigured = () => {
  const c = cfg();
  return !!(c && c.apiKey && !String(c.apiKey).startsWith('YOUR_') && window.VAPID_KEY && !String(window.VAPID_KEY).startsWith('YOUR_'));
};

const ua = () => navigator.userAgent || '';
export const isIos = () => /iPad|iPhone|iPod/.test(ua()) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
export const isStandalone = () => window.matchMedia?.('(display-mode: standalone)').matches || navigator.standalone === true;
const platform = () => (isIos() ? 'ios' : /Android/i.test(ua()) ? 'android' : 'web');

let messagingInstance = null;
const getMessagingInstance = () => {
  if (!messagingInstance) {
    const app = getApps()[0] || initializeApp(cfg());
    messagingInstance = getMessaging(app);
  }
  return messagingInstance;
};

/**
 * One hook owns the whole device flow:
 * permission -> service worker -> FCM token -> POST /api/devices/register -> subscribe to all_devices.
 * phase: checking | noconfig | unsupported | ios-install | denied | idle | connecting | connected
 */
export function useFcm(log) {
  const [phase, setPhase] = useState('checking');
  const [token, setToken] = useState(null);
  const [name, setName] = useState(() => localStorage.getItem(NAME_KEY) || '');
  const listening = useRef(false);
  const booted = useRef(false);

  const showForeground = useCallback(async (payload) => {
    const title = payload.notification?.title || payload.data?.title || 'Thông báo';
    const body = payload.notification?.body || payload.data?.body || '';
    log('ok', `[NHẬN] Máy này vừa nhận thông báo: "${title}" - ${body}`);
    toast.custom((t) => (
      <div className={`notif-land w-[22rem] max-w-[92vw] rounded-2xl bg-ink px-4 py-3 text-white shadow-lg ${t.visible ? '' : 'opacity-0'}`}>
        <p className="text-sm font-semibold">{title}</p>
        <p className="mt-0.5 text-sm text-white/80">{body}</p>
      </div>
    ), { duration: 5000, position: 'top-center' });
  }, [log]);

  const connect = useCallback(async (rawName) => {
    const userId = rawName.trim();
    if (!userId) { toast.error('Hãy nhập tên thiết bị trước.'); return false; }
    setPhase('connecting');
    try {
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') {
        setPhase(permission === 'denied' ? 'denied' : 'idle');
        log('warn', 'Chưa được cấp quyền thông báo.');
        return false;
      }
      await navigator.serviceWorker.register('/firebase-messaging-sw.js');
      const sw = await navigator.serviceWorker.ready;
      const messaging = getMessagingInstance();
      const t = await getToken(messaging, { vapidKey: window.VAPID_KEY, serviceWorkerRegistration: sw });
      if (!t) throw new Error('FCM không trả về token.');
      log('ok', `Lấy token FCM thành công: ${t.slice(0, 28)}... (${t.length} ký tự)`);

      await registerDevice(userId, t, platform());
      log('ok', `Đã đăng ký thiết bị "${userId}" với máy chủ.`);
      try {
        await subscribeTopic(t, BROADCAST_TOPIC);
        log('ok', `Đã tham gia nhóm "${BROADCAST_TOPIC}" để nhận thông báo chung.`);
      } catch (e) {
        log('warn', `Chưa tham gia được nhóm "${BROADCAST_TOPIC}": ${errorText(e)}`);
      }
      if (!listening.current) {
        listening.current = true;
        onMessage(messaging, showForeground);
      }
      localStorage.setItem(NAME_KEY, userId);
      setName(userId);
      setToken(t);
      setPhase('connected');
      return true;
    } catch (e) {
      log('error', `Kết nối thất bại: ${errorText(e)}`);
      toast.error('Không kết nối được thiết bị. Xem Nhật ký để biết lý do.');
      setPhase('idle');
      return false;
    }
  }, [log, showForeground]);

  const disconnect = useCallback(async () => {
    if (!token) return;
    try {
      await unsubscribeTopic(token, BROADCAST_TOPIC).catch(() => {});
      await unregisterDevice(token);
      await deleteToken(getMessagingInstance());
      log('info', 'Đã hủy đăng ký thiết bị này.');
    } catch (e) {
      log('error', `Hủy đăng ký thất bại: ${errorText(e)}`);
    }
    setToken(null);
    setPhase('idle');
  }, [token, log]);

  // Decide what this browser can do. Reconnect silently if permission was already granted.
  useEffect(() => {
    if (booted.current) return;
    booted.current = true;
    (async () => {
      if (!isConfigured()) { setPhase('noconfig'); return; }
      if (isIos() && !isStandalone()) { setPhase('ios-install'); return; }
      const ok = await isSupported().catch(() => false);
      if (!ok) { setPhase('unsupported'); return; }
      if (Notification.permission === 'denied') { setPhase('denied'); return; }
      const saved = localStorage.getItem(NAME_KEY);
      if (Notification.permission === 'granted' && saved) {
        await connect(saved);
      } else {
        setPhase('idle');
      }
    })();
  }, [connect]);

  return { phase, token, name, setName, connect, disconnect };
}
