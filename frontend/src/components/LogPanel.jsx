import React from 'react';

export default function LogPanel({ entries = [], onClear }) {
  return (
    <div className="flex flex-col h-full min-h-[380px] max-h-[460px] rounded-2xl bg-[#131b26] text-slate-100 shadow-md border border-[#1f2937] overflow-hidden">
      <div className="flex items-center justify-between border-b border-[#232f3e] px-5 py-3.5 select-none">
        <h2 className="text-sm font-bold text-white tracking-wide">
          Nhật ký hoạt động
        </h2>
        {onClear && (
          <button
            type="button"
            onClick={onClear}
            className="text-xs text-slate-400 hover:text-white underline transition-colors"
          >
            Xóa
          </button>
        )}
      </div>

      <div className="flex-1 p-5 overflow-y-auto font-mono text-xs leading-relaxed space-y-3">
        {entries.length === 0 ? (
          <div className="text-slate-400 text-xs leading-relaxed">
            Chưa có hoạt động. Lấy token, mã trạng thái 200 OK và thông báo nhận được sẽ hiện ở đây.
          </div>
        ) : (
          entries.map((entry) => {
            const isOk =
              entry.level === 'ok' ||
              entry.text?.includes('200') ||
              entry.text?.toLowerCase().includes('ok') ||
              entry.text?.includes('thành công');
            const isErr =
              entry.level === 'error' ||
              entry.text?.includes('thất bại') ||
              entry.text?.includes('Error');

            return (
              <div key={entry.id} className="flex items-start gap-2 break-all">
                <span className="select-none text-slate-500 text-[11px] whitespace-nowrap">
                  [{entry.time}]
                </span>
                <span className="select-none text-slate-500">&gt;</span>
                <span
                  className={
                    isOk
                      ? 'text-emerald-400 font-medium'
                      : isErr
                      ? 'text-rose-400 font-medium'
                      : 'text-slate-300'
                  }
                >
                  {entry.text}
                </span>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}