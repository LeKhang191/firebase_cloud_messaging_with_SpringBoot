/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['"Be Vietnam Pro"', 'system-ui', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'ui-monospace', 'Consolas', 'Menlo', 'monospace'],
      },
      colors: {
        ink: { DEFAULT: '#0E1726', soft: '#162033' },
        muted: '#5B6678',
        line: '#D5DBE4',
        canvas: '#E9EDF2',
        flame: { DEFAULT: '#FFB300', dark: '#E69F00', ink: '#1A1200' },
        ok: '#0F766E',
        danger: '#B42318',
      },
      borderRadius: { phone: '36px' },
    },
  },
  plugins: [],
};
