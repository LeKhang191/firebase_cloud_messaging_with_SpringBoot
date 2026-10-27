import React, { useEffect, useRef } from 'react';

const tone = {
  cmd: 'text-white font-semibold',
  info: 'text-white/70',
  ok: 'text-[#5EEAD4]',
  warn: 'text-flame',
  error: 'text-[#FCA5A5]',
};

/** Terminal view: every API call ("$ POST ...", "<- 200 OK ...") and every message received, newest at the bottom. */
export default function LogPanel({ entries, onClear }) {
  const box = useRef(null);
  useEffect(() => { if (box.current) box.current.scrollTop = box.current.scrollHeight; }, [entries]);

  return (
    <section className="flex h-[360px] flex-col overflow-hidden rounded-2xl bg-ink-soft text-white lg:absolute lg:inset-0 lg:h-auto" aria-label="Terminal">
      <div className="flex items-center justify-between border-b border-white/10 px-4 py-2.5">
        <h2 className="font-mono text-sm font-semibold">Terminal</h2>
        <button type="button" onClick={onClear} className="font-mono text-xs text-white/60 underline underline-offset-2 hover:text-white">clear</button>
      </div>
      <div ref={box} className="flex-1 space-y-1 overflow-auto px-4 py-3 font-mono text-[12.5px] leading-relaxed" aria-live="polite">
        {entries.length === 0 && <p className="text-white/50">$ No command found. Every request sent to the server and every message received will appear here.</p>}
        {entries.map((e) => (
          <p key={e.id} className={`whitespace-pre-wrap break-all ${tone[e.level] || tone.info}`}>
            <span className="text-white/35">{e.time}</span>{'  '}{e.text}
          </p>
        ))}
      </div>
    </section>
  );
}
