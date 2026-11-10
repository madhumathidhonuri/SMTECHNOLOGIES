importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: 'AIzaSyA_dummy_web_key_replace_me',
  appId: '1:1234567890:web:dummy123456789',
  messagingSenderId: '1234567890',
  projectId: 'dealerfleet-app',
  authDomain: 'dealerfleet-app.firebaseapp.com',
  storageBucket: 'dealerfleet-app.appspot.com',
});

const messaging = firebase.messaging();
