import React from 'react';

/** Title + body inputs shared by every send mode. Blank = server default text. */
export default function MessageForm({ title, body, onTitle, onBody, defaultTitle, defaultBody, optional }) {
  return (
    <div className="space-y-4">
      <div>
        <label htmlFor="msg-title" className="mb-1.5 block text-sm font-medium">
          Title {optional && <span className="font-normal text-muted">(optional)</span>}
        </label>
        <input id="msg-title" className="field" value={title} maxLength={200}
               placeholder={defaultTitle} onChange={(e) => onTitle(e.target.value)} />
      </div>
      <div>
        <label htmlFor="msg-body" className="mb-1.5 block text-sm font-medium">
          Body {optional && <span className="font-normal text-muted">(optional)</span>}
        </label>
        <textarea id="msg-body" rows={3} className="field resize-y" value={body} maxLength={1000}
                  placeholder={defaultBody} onChange={(e) => onBody(e.target.value)} />
      </div>
    </div>
  );
}
