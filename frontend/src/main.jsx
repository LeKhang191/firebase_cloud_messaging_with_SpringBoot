import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.jsx';
import './style.css';

// Only ONE service worker may control "/": firebase-messaging-sw.js, registered in lib/fcm.js.
// (The old Note app registered its own sw.js here; that would replace the FCM worker.)
ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
