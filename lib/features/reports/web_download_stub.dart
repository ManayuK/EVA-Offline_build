// lib/features/reports/web_download_stub.dart
// Used on mobile / desktop — web download is handled natively via open_file.
// ignore_for_file: avoid_unused_import_or_implementation
void downloadBytesOnWeb(List<int> bytes, String filename) {
  // No-op on non-web platforms.
}
