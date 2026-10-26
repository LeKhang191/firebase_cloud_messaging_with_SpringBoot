import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Toaster } from 'react-hot-toast';
import { Flame } from 'lucide-react';
import LecturerPage from './pages/LecturerPage';
import AdminPage from './pages/AdminPage';
import { useFcm } from './lib/fcm';
import { setApiLogger } from './lib/api';

const tabFromHash = () => (window.location.hash === '#admin' ? 'admin' : 'lecturer');

export default function App() {
  const [tab, setTab] = useState(tabFromHash);
  const [logs, setLogs] = useState([]);
  const seq = useRef(0);

  const log = useCallback((level, text) => {
    seq.current += 1;
    const time = new Date().toLocaleTimeString('vi-VN');
    setLogs((prev) => [...prev, { id: seq.current, level, text, time }].slice(-200));
  }, []);

  const fcm = useFcm(log);

  useEffect(() => { setApiLogger(log); }, [log]);

  useEffect(() => {
    const onHash = () => setTab(tabFromHash());
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);

  const go = (next) => {
    window.location.hash = next === 'admin' ? '#admin' : '';
    setTab(next);
  };

  const tabBtn = (value, label) => (
    <button type="button" role="tab" aria-selected={tab === value} onClick={() => go(value)}
            className={`rounded-lg px-4 py-2 text-sm font-semibold transition-colors ${
              tab === value ? 'bg-flame text-flame-ink' : 'text-white/80 hover:bg-white/10'}`}>
      {label}
    </button>
  );

  return (
    <div className="min-h-screen">
      <header className="bg-ink text-white">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-4 sm:px-6">
          <div className="flex items-center gap-3">
            <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-flame text-flame-ink"><Flame size={22} strokeWidth={2.4} /></span>
            <div>
              <h1 className="text-lg font-bold leading-tight">FCM Demo</h1>
              <p className="text-sm text-white/70">Thông báo đẩy với Firebase và Spring Boot</p>
            </div>
          </div>
          <div role="tablist" aria-label="Vai trò" className="flex gap-1 rounded-xl bg-white/10 p-1">
            {tabBtn('lecturer', 'Máy của tôi')}
            {tabBtn('admin', 'Admin')}
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-4 py-6 sm:px-6 sm:py-8">
        {tab === 'lecturer' ? (
          <LecturerPage
            fcm={fcm}
            log={log}
            logs={logs}
            onClearLogs={() => setLogs([])}
          />
        ) : (
          <AdminPage log={log} logs={logs} onClearLogs={() => setLogs([])} />
        )}
      </main>

      <Toaster position="top-center" />
    </div>
  );
}