/// Readable message when the phone cannot reach the server (REQ013), so the
/// user never sees raw text like "ClientException with SocketException".
const String kNoInternetMessage =
    'No internet connection. Please check your connection and try again.';

/// True when an error (or its message) means the server could not be reached.
bool isNetworkError(Object? error) {
  final text = (error is String ? error : '$error').toLowerCase();
  return text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('clientexception') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('connection closed') ||
      text.contains('connection timed out') ||
      text.contains('timeoutexception') ||
      text.contains('handshakeexception');
}
