/* Firebase Cloud Messaging service worker for ProjectOS Dashboard. */
importScripts('https://www.gstatic.com/firebasejs/10.12.5/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.5/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDnhRkFqbAU6RvBF0okym8T95Ooh7oG-6E',
  authDomain: 'project-management-dashb-aa77a.firebaseapp.com',
  projectId: 'project-management-dashb-aa77a',
  storageBucket: 'project-management-dashb-aa77a.firebasestorage.app',
  messagingSenderId: '1051281746131',
  appId: '1:1051281746131:web:decb710a96982193460c26',
  measurementId: 'G-EJHXR1WNSG',
});

firebase.messaging();
