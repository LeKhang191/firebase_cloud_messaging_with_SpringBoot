import React, { useEffect, useRef } from 'react';

const tone = { info: 'text-white/80', ok: 'text-[#5EEAD4]', warn: 'text-flame', error: 'text-[#FCA5A5]' };

/** Always-visible activity feed (token, HTTP status, received messages), newest at the bottom. */
export default function LogPanel({ entries, onClear }) {
  const box = useRef(null);
  useEffect(() => { if (box.current) box.current.scrollTop = box.current.scrollHeight; }, [entries]);

  return (
    <section className="flex h-[70vh] min-h-[320px] flex-col overflow-hidden rounded-2xl bg-ink-soft text-white lg:h-[calc(100vh-3rem)]" aria-label="Nhật ký hoạt động">
      <div className="flex items-center justify-between border-b border-white/10 px-4 py-3">
        <h2 className="text-sm font-semibold">Nhật ký hoạt động</h2>
        <button type="button" onClick={onClear} className="text-sm text-white/60 underline underline-offset-2 hover:text-white">Xóa</button>
      </div>
      <div ref={box} className="flex-1 space-y-1.5 overflow-auto px-4 py-3 text-[13px] leading-relaxed" aria-live="polite">
        {entries.length === 0 && <p className="text-white/50">Chưa có hoạt động. Lấy token, mã trạng thái 200 OK và thông báo nhận được sẽ hiện ở đây.</p>}
        {entries.map((e) => (
          <p key={e.id} className={`break-words ${tone[e.level]}`}>
            <span className="text-white/40">{e.time}</span> {e.text}
          </p>
        ))}
      </div>
    </section>
  );
}
