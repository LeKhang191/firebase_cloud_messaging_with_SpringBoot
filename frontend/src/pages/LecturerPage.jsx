import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { Laptop, Loader2, Send } from 'lucide-react';
import MessageForm from '../components/MessageForm';
import Notice from '../components/Notice';
import LogPanel from '../components/LogPanel';
import { errorText, sendSelfTest } from '../lib/api';

const DEFAULT_TITLE = 'Device test';
const DEFAULT_BODY = 'FCM push test successful!';

function PhaseNotice({ phase }) {
  switch (phase) {
    case 'noconfig':
      return (
        <Notice tone="error" title="Server has no Firebase configuration">
          Create the file <b>src/main/resources/static/firebase-config.js</b> from the template, fill in the Firebase and VAPID key information, then reload the page.
        </Notice>
      );
    case 'ios-install':
      return (
        <Notice tone="warn" title="On iPhone/iPad, you need to add the page to the Home Screen">
          Open in Safari, tap the Share button, select <b>Add to Home Screen</b>, then open again from the created icon (iOS 16.4 and above).
        </Notice>
      );
    case 'unsupported':
      return (
        <Notice tone="error" title="This browser does not support push notifications">
          Use Chrome, Edge or Firefox latest versions. Brave disables Google services by default. The page must be served over HTTPS (or localhost).
        </Notice>
      );
    case 'denied':
      return (
        <Notice tone="error" title="Push notifications are blocked for this page">
          Click the lock icon next to the address bar, change <b>Notifications</b> to <b>Allow</b>, then reload the page.
        </Notice>
      );
    default:
      return null;
  }
}

export default function LecturerPage({ fcm, log, logs = [], onClearLogs }) {
  const { phase, token, name, setName, connect, disconnect } = fcm;
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [sending, setSending] = useState(false);

  const connected = phase === 'connected';
  const connecting = phase === 'connecting';
  const blocked = ['noconfig', 'ios-install', 'unsupported', 'denied', 'checking'].includes(phase);

  const testSelf = async () => {
    setSending(true);
    try {
      await sendSelfTest(token, title || DEFAULT_TITLE, body || DEFAULT_BODY);
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
          <Laptop size={20} /> Connect this device
        </h2>
        <p className="mt-1 text-sm text-muted">
          Set a name so the presenter can identify your device in the list, then allow notifications.
        </p>

        <div className="mt-4 max-w-md">
          <label htmlFor="user-name" className="mb-1.5 block text-sm font-medium">Device Name</label>
          <input id="user-name" className="field" value={name} maxLength={60} disabled={connected || connecting}
                 placeholder="e.g., Dell Laptop, Phone…" onChange={(e) => setName(e.target.value)} />
        </div>

        <div className="mt-4 flex flex-wrap items-center gap-3">
          {connected ? (
            <>
              <span className="inline-flex items-center gap-2 rounded-lg bg-ok/10 px-3 py-2 text-sm font-semibold text-ok">
                <span className="h-2 w-2 rounded-full bg-ok" /> Connected with name “{name}”
              </span>
              <button type="button" className="btn btn-quiet" onClick={disconnect}>Disconnect</button>
            </>
          ) : (
            <button type="button" className="btn btn-primary" disabled={blocked || connecting || !name.trim()}
                    onClick={() => connect(name)}>
              {connecting && <Loader2 size={18} className="animate-spin" />}
              {connecting ? 'Granting permission…' : 'Enable Notifications'}
            </button>
          )}
        </div>
      </section>

      <div className="grid grid-cols-1 items-stretch gap-6 lg:grid-cols-2">
        <section className="panel flex flex-col justify-between" aria-labelledby="test-h">
          <div>
            <h2 id="test-h" className="flex items-center gap-2 text-lg font-bold">
              <Send size={18} /> Test sending to this device
            </h2>
            <p className="mt-1 text-sm text-muted">Modify the content as needed, click send, and observe the notification appear.</p>
            <div className="mt-4">
              <MessageForm title={title} body={body} onTitle={setTitle} onBody={setBody}
                           defaultTitle={DEFAULT_TITLE} defaultBody={DEFAULT_BODY} optional />
            </div>
          </div>
          <div className="mt-5">
            <button type="button" className="btn btn-primary" disabled={!connected || sending} onClick={testSelf}>
              {sending ? <Loader2 size={18} className="animate-spin" /> : <Send size={18} />}
              {sending ? 'Sending…' : 'Test Send'}
            </button>
            {!connected && <p className="mt-2 text-sm text-muted">Please connect the device in the step above first.</p>}
          </div>
        </section>

        <div className="relative min-h-[360px]">
          <LogPanel entries={logs} onClear={onClearLogs} />
        </div>
      </div>
    </div>
  );
}
