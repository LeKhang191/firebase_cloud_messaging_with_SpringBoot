import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { BellRing, Loader2, Send, Smartphone } from 'lucide-react';
import MessageForm from '../components/MessageForm';
import Notice from '../components/Notice';
import { sendSelfTest, errorText } from '../lib/api';

const DEFAULT_TITLE = 'Test thiết bị';
const DEFAULT_BODY = 'FCM push test thành công!';

function PhaseNotice({ phase }) {
  switch (phase) {
    case 'noconfig':
      return (
        <Notice tone="error" title="Máy chủ chưa có cấu hình Firebase">
          Tạo file <b>src/main/resources/static/firebase-config.js</b> từ file mẫu, điền thông tin Firebase và VAPID key, rồi tải lại trang.
        </Notice>
      );
    case 'ios-install':
      return (
        <Notice tone="warn" title="Trên iPhone/iPad cần thêm trang vào Màn hình chính">
          Mở trong Safari, bấm nút Chia sẻ, chọn <b>Thêm vào MH chính</b>, rồi mở lại từ biểu tượng vừa tạo. Apple chỉ cho phép thông báo web với ứng dụng đã cài như vậy (iOS 16.4 trở lên).
        </Notice>
      );
    case 'unsupported':
      return (
        <Notice tone="error" title="Trình duyệt này không nhận được thông báo đẩy">
          Dùng Chrome, Edge hoặc Firefox bản mới nhất. Brave tắt dịch vụ Google theo mặc định, nên cần bật lại trong cài đặt. Trang phải chạy bằng HTTPS (hoặc localhost).
        </Notice>
      );
    case 'denied':
      return (
        <Notice tone="error" title="Thông báo đang bị chặn cho trang này">
          Bấm biểu tượng ổ khóa cạnh thanh địa chỉ, đổi <b>Thông báo</b> sang <b>Cho phép</b>, rồi tải lại trang.
        </Notice>
      );
    default:
      return null;
  }
}

export default function LecturerPage({ fcm, log }) {
  const { phase, token, name, setName, connect, disconnect } = fcm;
  const [title, setTitle] = useState(DEFAULT_TITLE);
  const [body, setBody] = useState(DEFAULT_BODY);
  const [sending, setSending] = useState(false);

  const connected = phase === 'connected';
  const blocked = ['noconfig', 'ios-install', 'unsupported', 'denied', 'checking'].includes(phase);

  const send = async () => {
    setSending(true);
    try {
      await sendSelfTest(token, title, body);
      log('ok', `Đã gửi thử tới thiết bị "${name}". Thông báo sẽ hiện trong vài giây.`);
      toast.success('Đã gửi. Thông báo sắp hiện trên máy này.');
    } catch (e) {
      log('error', `Gửi thử thất bại: ${errorText(e)}`);
      toast.error(errorText(e));
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="space-y-6">
        <PhaseNotice phase={phase} />

        <section className="panel" aria-labelledby="connect-h">
          <h2 id="connect-h" className="flex items-center gap-2 text-lg font-bold">
            <Smartphone size={20} /> Kết nối thiết bị này
          </h2>
          <p className="mt-1 text-sm text-muted">
            Đặt một cái tên để người trình bày nhận ra máy của bạn trong danh sách, rồi cho phép thông báo.
          </p>

          <div className="mt-4">
            <label htmlFor="device-name" className="mb-1.5 block text-sm font-medium">Tên thiết bị</label>
            <input id="device-name" className="field" value={name} maxLength={60} disabled={connected || phase === 'connecting'}
                   placeholder="Ví dụ: Thầy Đức, iPhone của cô Lan" onChange={(e) => setName(e.target.value)} />
          </div>

          <div className="mt-4 flex flex-wrap items-center gap-3">
            {!connected ? (
              <button type="button" className="btn btn-primary" disabled={blocked || phase === 'connecting' || !name.trim()}
                      onClick={() => connect(name)}>
                {phase === 'connecting' ? <Loader2 size={18} className="animate-spin" /> : <BellRing size={18} />}
                {phase === 'connecting' ? 'Đang kết nối…' : 'Cho phép thông báo'}
              </button>
            ) : (
              <>
                <span className="inline-flex items-center gap-2 rounded-lg bg-ok/10 px-3 py-2 text-sm font-semibold text-ok">
                  <span className="h-2 w-2 rounded-full bg-ok" /> Đã kết nối với tên “{name}”
                </span>
                <button type="button" className="btn btn-quiet" onClick={disconnect}>Hủy kết nối</button>
              </>
            )}
          </div>
        </section>

        <section className="panel" aria-labelledby="test-h">
          <h2 id="test-h" className="flex items-center gap-2 text-lg font-bold">
            <Send size={20} /> Gửi thử cho chính thiết bị này
          </h2>
          <p className="mt-1 text-sm text-muted">Sửa nội dung tùy ý, bấm gửi và nhìn thông báo hiện lên.</p>
          <div className="mt-4">
            <MessageForm title={title} body={body} onTitle={setTitle} onBody={setBody}
                         defaultTitle={DEFAULT_TITLE} defaultBody={DEFAULT_BODY} />
          </div>
          <button type="button" className="btn btn-primary mt-5" disabled={!connected || sending} onClick={send}>
            {sending ? <Loader2 size={18} className="animate-spin" /> : <Send size={18} />}
            {sending ? 'Đang gửi…' : 'Gửi thử'}
          </button>
          {!connected && <p className="mt-2 text-sm text-muted">Hãy kết nối thiết bị ở bước trên trước.</p>}
        </section>
    </div>
  );
}
