import React, { useCallback, useEffect, useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import { KeyRound, Loader2, Radio, RefreshCw, Send, User } from 'lucide-react';
import MessageForm from '../components/MessageForm';
import Notice from '../components/Notice';
import LogPanel from '../components/LogPanel';
import { BROADCAST_TOPIC } from '../lib/fcm';
import { errorText, getConfig, hasAdminKey, listDevices, sendToDevice, sendToTopic, setAdminKey } from '../lib/api';

const DEFAULT_TITLE = 'Thông báo';
const DEFAULT_BODY = 'Bạn có một thông báo mới';
const TOPIC_RE = /^[a-zA-Z0-9\-_.~%]+$/;

export default function AdminPage({ log, logs = [], onClearLogs }) {
  const [keyRequired, setKeyRequired] = useState(null); // null = still asking the server
  const [keyInput, setKeyInput] = useState('');
  const [unlocked, setUnlocked] = useState(false);
  const [devices, setDevices] = useState([]);
  const [listError, setListError] = useState('');
  const [loading, setLoading] = useState(false);

  const [mode, setMode] = useState('device'); // device | topic
  const [deviceId, setDeviceId] = useState('');
  const [topic, setTopic] = useState(BROADCAST_TOPIC);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [sending, setSending] = useState(false);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const list = await listDevices();
      setDevices(list);
      setListError('');
      setUnlocked(true);
    } catch (e) {
      setListError(errorText(e));
      if (e?.response?.status === 401) {
        setUnlocked(false);
        setDevices([]);
        setAdminKey(''); // Forget a stale/invalid saved key so it cannot loop after refresh.
        setKeyInput('');
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    getConfig()
      .then((c) => {
        setKeyRequired(c.adminKeyRequired);
        // On F5, re-validate the tab's saved key with the server before restoring admin access.
        if (!c.adminKeyRequired || hasAdminKey()) refresh();
      })
      .catch((e) => { setKeyRequired(false); setListError(errorText(e)); });
  }, [refresh]);

  // Keep the list fresh while the admin is presenting.
  useEffect(() => {
    if (!unlocked) return undefined;
    const id = setInterval(() => { if (!document.hidden) refresh(); }, 5000);
    return () => clearInterval(id);
  }, [unlocked, refresh]);

  // Drop a selection whose device disappeared (e.g. removed as UNREGISTERED).
  useEffect(() => {
    if (deviceId && !devices.some((d) => String(d.id) === deviceId)) setDeviceId('');
  }, [devices, deviceId]);

  const unlock = async (e) => {
    e.preventDefault();
    setAdminKey(keyInput);
    await refresh();
  };

  const target = useMemo(() => devices.find((d) => String(d.id) === deviceId), [devices, deviceId]);
  const topicValid = TOPIC_RE.test(topic);
  const canSend = unlocked && !sending && (mode === 'device' ? !!target : topicValid);

  const send = async () => {
    setSending(true);
    try {
      if (mode === 'device') {
        await sendToDevice(target.id, title, body);
        toast.success(`Sent to ${target.userId}.`);
      } else {
        await sendToTopic(topic, title, body);
        toast.success(`Sent to topic “${topic}”.`);
      }
    } catch (e) {
      log('error', `Failed to send: ${errorText(e)}`);
      toast.error(errorText(e));
      if (mode === 'device') refresh(); // a dead token is deleted by the server
    } finally {
      setSending(false);
    }
  };

  const modeBtn = (value, Icon, label) => (
    <button type="button" role="radio" aria-checked={mode === value} onClick={() => setMode(value)}
            className={`flex flex-1 items-center justify-center gap-2 rounded-lg px-3 py-2.5 text-sm font-semibold transition-colors ${
              mode === value ? 'bg-ink text-white' : 'text-ink hover:bg-canvas'}`}>
      <Icon size={17} /> {label}
    </button>
  );

  return (
    <div className="space-y-6">
        {keyRequired && !unlocked && (
          <section className="panel" aria-labelledby="key-h">
            <h2 id="key-h" className="flex items-center gap-2 text-lg font-bold"><KeyRound size={20} /> Enter Admin Key</h2>
            <p className="mt-1 text-sm text-muted">The server is running with an admin key (ADMIN_KEY environment variable) to prevent unauthorized notifications.</p>
            <form onSubmit={unlock} className="mt-4 flex flex-wrap gap-3">
              <input type="password" className="field max-w-xs" value={keyInput} autoComplete="off"
                     aria-label="Admin Key" onChange={(e) => setKeyInput(e.target.value)} />
              <button type="submit" className="btn btn-primary" disabled={!keyInput.trim()}>Unlock</button>
            </form>
            {listError && <div className="mt-3"><Notice tone="error">{listError}</Notice></div>}
          </section>
        )}

        <div className="grid grid-cols-1 items-stretch gap-6 lg:grid-cols-2">
        <section className="panel" aria-labelledby="compose-h">
          <div className="flex items-start justify-between gap-3">
            <div>
              <h2 id="compose-h" className="text-lg font-bold">Compose and Send Notification</h2>
              <p className="mt-1 text-sm text-muted">
                {unlocked ? `${devices.length} devices are registered.` : 'Need to unlock to view devices.'}
              </p>
            </div>
            <button type="button" className="btn btn-quiet px-3" onClick={refresh} disabled={loading || (keyRequired && !unlocked)}
                    aria-label="Refresh device list">
              <RefreshCw size={17} className={loading ? 'animate-spin' : ''} />
            </button>
          </div>

          {listError && unlocked && <div className="mt-3"><Notice tone="error">{listError}</Notice></div>}

          <div role="radiogroup" aria-label="Send type" className="mt-4 flex gap-1 rounded-xl border border-line bg-white p-1">
            {modeBtn('device', User, 'Send to a specific device')}
            {modeBtn('topic', Radio, 'Send to all devices')}
          </div>

          <div className="mt-4">
            {mode === 'device' ? (
              <>
                <label htmlFor="device" className="mb-1.5 block text-sm font-medium">Thiết bị nhận</label>
                <select id="device" className="field" value={deviceId} disabled={!unlocked || devices.length === 0}
                        onChange={(e) => setDeviceId(e.target.value)}>
                  <option value="">{devices.length ? 'Select device…' : 'No devices available'}</option>
                  {devices.map((d) => (
                    <option key={d.id} value={d.id}>{d.userId} ({d.platform})</option>
                  ))}
                </select>
                {unlocked && devices.length === 0 && (
                  <p className="mt-2 text-sm text-muted">Open this link on another device, enter a name, and click "Allow Notifications". That device will then appear here.</p>
                )}
              </>
            ) : (
              <>
                <label htmlFor="topic" className="mb-1.5 block text-sm font-medium">Topic</label>
                <input id="topic" className="field" value={topic} onChange={(e) => setTopic(e.target.value.trim())}
                       aria-invalid={!topicValid} />
                {!topicValid ? (
                  <p className="mt-2 text-sm text-danger">Only letters, numbers and characters - _ . ~ % are allowed</p>
                ) : (
                  <p className="mt-2 text-sm text-muted">All connected devices are in the “{BROADCAST_TOPIC}” group and will receive the notification.</p>
                )}
              </>
            )}
          </div>

          <div className="mt-5">
            <MessageForm title={title} body={body} onTitle={setTitle} onBody={setBody}
                         defaultTitle={DEFAULT_TITLE} defaultBody={DEFAULT_BODY} optional />
          </div>

          <button type="button" className="btn btn-primary mt-5" disabled={!canSend} onClick={send}>
            {sending ? <Loader2 size={18} className="animate-spin" /> : <Send size={18} />}
            {sending ? 'Sending…' : mode === 'device' ? 'Send to specific device' : 'Send to all devices'}
          </button>
        </section>
          <div className="relative min-h-[360px]">
            <LogPanel entries={logs} onClear={onClearLogs} />
          </div>
        </div>
    </div>
  );
}
