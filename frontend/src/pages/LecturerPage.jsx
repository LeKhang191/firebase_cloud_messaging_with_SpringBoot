import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { Laptop, Send, Loader2 } from 'lucide-react';
import MessageForm from '../components/MessageForm';
import Notice from '../components/Notice';
import LogPanel from '../components/LogPanel';
import { errorText, sendToDevice } from '../lib/api';

const DEFAULT_TITLE = 'Test thiết bị';
const DEFAULT_BODY = 'FCM push test thành công!';

export default function LecturerPage({ fcm, log, logs = [], onClearLogs }) {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [sending, setSending] = useState(false);

  const testSelf = async () => {
    if (!fcm.deviceId) return;
    setSending(true);
    try {
      await sendToDevice(fcm.deviceId, title || DEFAULT_TITLE, body || DEFAULT_BODY);
      log('ok', 'Đã yêu cầu server gửi thông báo cho chính máy này (200 OK).');
    } catch (e) {
      log('error', `Gửi thử thất bại: ${errorText(e)}`);
      toast.error(errorText(e));
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="space-y-6">
      <section className="panel" aria-labelledby="connect-h">
        <h2 id="connect-h" className="flex items-center gap-2 text-lg font-bold">
          <Laptop size={20} /> Kết nối thiết bị này
        </h2>
        <p className="mt-1 text-sm text-muted">
          Đặt một cái tên để người trình bày nhận ra máy của bạn trong danh sách, rồi cho phép thông báo.
        </p>

        <div className="mt-4 max-w-md">
          <label htmlFor="user-name" className="mb-1.5 block text-sm font-medium">Tên thiết bị</label>
          <input
            id="user-name"
            className="field"
            value={fcm.userId}
            disabled={fcm.registered}
            placeholder="Ví dụ: Laptop Dell, Điện thoại…"
            onChange={(e) => fcm.setUserId(e.target.value)}
          />
        </div>

        <div className="mt-4 flex flex-wrap items-center gap-3">
          {fcm.registered ? (
            <>
              <span className="inline-flex items-center gap-1.5 rounded-lg bg-emerald-50 px-3 py-2 text-sm font-medium text-emerald-700">
                <span className="h-2 w-2 rounded-full bg-emerald-500 animate-pulse" />
                Đã kết nối với tên “{fcm.userId}”
              </span>
              <button
                type="button"
                className="btn border border-line bg-white hover:bg-canvas px-4 py-2 text-sm font-medium text-ink transition-colors"
                onClick={fcm.unregister}
              >
                Hủy kết nối
              </button>
            </>
          ) : (
            <button
              type="button"
              className="btn btn-primary"
              disabled={!fcm.userId.trim() || fcm.loading}
              onClick={fcm.register}
            >
              {fcm.loading ? 'Đang cấp quyền…' : 'Bật nhận thông báo'}
            </button>
          )}
        </div>

        {fcm.error && <div className="mt-3"><Notice tone="error">{fcm.error}</Notice></div>}
      </section>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-stretch">
        <section className="panel lg:col-span-6 flex flex-col justify-between" aria-labelledby="test-h">
          <div>
            <h2 id="test-h" className="flex items-center gap-2 text-lg font-bold">
              <Send size={18} /> Gửi thử cho chính thiết bị này
            </h2>
            <p className="mt-1 text-sm text-muted">
              Sửa nội dung tùy ý, bấm gửi và nhìn thông báo hiện lên.
            </p>

            <div className="mt-4">
              <MessageForm
                title={title}
                body={body}
                onTitle={setTitle}
                onBody={setBody}
                defaultTitle={DEFAULT_TITLE}
                defaultBody={DEFAULT_BODY}
                optional
              />
            </div>
          </div>

          <div className="mt-5">
            <button
              type="button"
              className="btn bg-amber-500 hover:bg-amber-600 text-white font-semibold flex items-center gap-2 px-5 py-2.5 rounded-lg shadow-sm"
              disabled={!fcm.registered || sending}
              onClick={testSelf}
            >
              {sending ? <Loader2 size={18} className="animate-spin" /> : <Send size={18} />}
              {sending ? 'Đang gửi…' : 'Gửi thử'}
            </button>
          </div>
        </section>

        <div className="lg:col-span-6 flex flex-col min-h-[380px]">
          <LogPanel entries={logs} onClear={onClearLogs} />
        </div>
      </div>
    </div>
  );
}