importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAFa5071HC5_4zvOuhKb_4aWZrLrrfOrs0',
  authDomain: 'yanegi-684f9.firebaseapp.com',
  projectId: 'yanegi-684f9',
  storageBucket: 'yanegi-684f9.firebasestorage.app',
  messagingSenderId: '266662976182',
  appId: '1:266662976182:web:placeholder',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw] Background message received:', payload);
});
