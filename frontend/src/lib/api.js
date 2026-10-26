import axios from 'axios';

let adminKey = '';
export const setAdminKey = (key) => { adminKey = key.trim(); };

const api = axios.create({ baseURL: '/api', timeout: 20000 });

api.interceptors.request.use((config) => {
  if (adminKey) config.headers['X-Admin-Key'] = adminKey;
  return config;
});

// Terminal-style trace of every API call, shown in the activity panel.
let logger = null;
export const setApiLogger = (fn) => { logger = fn; };
const line = (cfg, status, text) => `${(cfg?.method || '').toUpperCase()} /api${cfg?.url || ''} -> ${status} ${text}`;
const brief = (d) => { const j = typeof d === 'string' ? d : JSON.stringify(d); return j && j.length > 110 ? j.slice(0, 110) + '...' : j; };

api.interceptors.response.use(
  (res) => {
    // The device list is polled every 5s by the admin page; skip it to keep the log readable.
    if (!(res.config.method === 'get' && res.config.url === '/devices')) {
      logger?.('ok', `${line(res.config, res.status, res.statusText || 'OK')} ${brief(res.data) || ''}`);
    }
    return res;
  },
  (err) => {
    const r = err.response;
    logger?.('error', r ? `${line(err.config, r.status, r.statusText || 'Error')} ${brief(r.data) || ''}` : `${line(err.config, 'ERR', err.message)}`);
    return Promise.reject(err);
  }
);

/** Turns a failed request into one readable Vietnamese sentence. */
export function errorText(e) {
  const d = e?.response?.data;
  if (d?.error === 'ADMIN_KEY_REQUIRED') return 'Thiếu hoặc sai mã admin.';
  if (d?.error === 'FCM_ERROR') return `FCM từ chối gửi (${d.code}): ${d.message}`;
  if (d?.error === 'VALIDATION_FAILED') return 'Dữ liệu chưa hợp lệ: ' + Object.values(d.fields || {}).join(', ');
  if (e?.response?.status === 404) return 'Không tìm thấy (thiết bị có thể đã bị xóa, hãy tải lại danh sách).';
  if (e?.response) return `Máy chủ trả lỗi ${e.response.status}.`;
  if (e?.code === 'ERR_NETWORK') return 'Không kết nối được máy chủ Spring Boot.';
  return e?.message || 'Có lỗi không xác định.';
}

/** Blank title/body are left out so the server applies its default text. */
const payloadOf = (title, body) => {
  const p = {};
  if (title?.trim()) p.title = title.trim();
  if (body?.trim()) p.body = body.trim();
  return p;
};

export const getConfig = () => api.get('/config').then((r) => r.data);
export const listDevices = () => api.get('/devices').then((r) => r.data);
export const registerDevice = (userId, token, platform) =>
  api.post('/devices/register', { userId, token, platform }).then((r) => r.data);
export const unregisterDevice = (token) => api.delete('/devices', { params: { token } }).then((r) => r.data);
export const subscribeTopic = (token, topic) => api.post('/topics/subscribe', { token, topic }).then((r) => r.data);
export const unsubscribeTopic = (token, topic) => api.post('/topics/unsubscribe', { token, topic }).then((r) => r.data);

export const sendSelfTest = (token, title, body) =>
  api.post('/notifications/token', { token, payload: payloadOf(title, body) }).then((r) => r.data);
export const sendToDevice = (id, title, body) =>
  api.post(`/notifications/device/${id}`, payloadOf(title, body)).then((r) => r.data);
export const sendToTopic = (topic, title, body) =>
  api.post(`/notifications/topic/${encodeURIComponent(topic)}`, payloadOf(title, body)).then((r) => r.data);

export default api;
