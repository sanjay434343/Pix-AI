import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class DownloadService {
  static const MethodChannel _channel = MethodChannel('pollinai.media_scanner');

  /// Downloads an image from [url] and saves it to the Downloads directory with [filename].
  /// Returns the saved file path.
  static Future<String> downloadAndSaveImage(String url, {String? filename}) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download image');
    }

    // Get Downloads directory
    Directory? downloadsDir;
    if (Platform.isAndroid) {
      downloadsDir = Directory('/storage/emulated/0/Download');
    } else {
      downloadsDir = await getDownloadsDirectory();
    }
    if (downloadsDir == null) {
      throw Exception('Cannot access Downloads directory');
    }

    final fileName = filename ?? 'pixai_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${downloadsDir.path}/$fileName');
    await file.writeAsBytes(response.bodyBytes);

    // Trigger media scan on Android
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('scanFile', {'path': file.path});
      } catch (_) {}
    }

    return file.path;
  }
}
