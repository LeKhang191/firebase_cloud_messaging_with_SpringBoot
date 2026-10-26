import React from 'react';
import { AlertTriangle, CheckCircle2, Info } from 'lucide-react';

const styles = {
  warn: 'border-flame/60 bg-flame/15 text-ink',
  error: 'border-danger/40 bg-danger/10 text-danger',
  ok: 'border-ok/40 bg-ok/10 text-ok',
  info: 'border-line bg-canvas text-ink',
};
const icons = { warn: AlertTriangle, error: AlertTriangle, ok: CheckCircle2, info: Info };

export default function Notice({ tone = 'info', title, children }) {
  const Icon = icons[tone];
  return (
    <div className={`flex gap-3 rounded-xl border p-3.5 text-sm ${styles[tone]}`} role={tone === 'error' ? 'alert' : 'status'}>
      <Icon size={18} className="mt-0.5 shrink-0" />
      <div className="min-w-0">
        {title && <p className="font-semibold">{title}</p>}
        <div className={title ? 'mt-0.5' : ''}>{children}</div>
      </div>
    </div>
  );
}
