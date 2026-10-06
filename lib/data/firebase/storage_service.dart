import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  StorageService({FirebaseStorage? storage}) : _storage = storage ?? FirebaseStorage.instance;
  final FirebaseStorage _storage;

  Future<String> uploadBytes({required String path, required Uint8List bytes, String? contentType}) async {
    final ref = _storage.ref(path);
    final task = await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return task.ref.getDownloadURL();
  }

  Future<void> deleteFile(String path) => _storage.ref(path).delete();
}
