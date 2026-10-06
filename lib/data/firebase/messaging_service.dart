import 'package:firebase_messaging/firebase_messaging.dart';

class MessagingService {
  MessagingService({FirebaseMessaging? messaging}) : _messaging = messaging ?? FirebaseMessaging.instance;
  final FirebaseMessaging _messaging;

  Future<String?> requestAndGetToken() async {
    await _messaging.requestPermission();
    return _messaging.getToken();
  }

  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;
}
