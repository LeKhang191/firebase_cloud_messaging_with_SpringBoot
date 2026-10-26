import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Dev: the UI runs on :5173 and Spring Boot on :8080.
// /api and /firebase-config.js are proxied so the browser sees ONE origin (no CORS, SW scope works).
const backend = process.env.VITE_BACKEND || 'http://localhost:8080';

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': backend,
      '/firebase-config.js': backend,
    },
  },
});
