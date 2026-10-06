class IdGenerator {
  static String make(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch;
    return '${prefix}_$now';
  }
}
