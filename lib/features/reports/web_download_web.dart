// lib/features/reports/web_download_web.dart
// Compiled only on web targets (via conditional import in report_generator.dart).
// Uses package:web to trigger a browser download without a server round-trip.
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void downloadBytesOnWeb(List<int> bytes, String filename) {
  final data = Uint8List.fromList(bytes);
  final blob = web.Blob(
    [data.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.setAttribute('download', filename);
  anchor.style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();

  Future.delayed(const Duration(seconds: 2), () {
    web.URL.revokeObjectURL(url);
    anchor.remove();
  });
}
