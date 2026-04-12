import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class RecordingStorage {
  static const String prefsKey = 'recording_entries_v2';

  Future<List<RecordingEntry>> loadRecordings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => RecordingEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveRecordings(List<RecordingEntry> recordings) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(recordings.map((item) => item.toJson()).toList());
    await prefs.setString(prefsKey, encoded);
  }

  Future<String> persistVideo(XFile file) async {
    final documents = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory(p.join(documents.path, 'recordings'));
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }

    final extension = p.extension(file.path).isEmpty ? '.mp4' : p.extension(file.path);
    final target = File(
      p.join(
        recordingsDir.path,
        'bwc_${DateTime.now().millisecondsSinceEpoch}$extension',
      ),
    );
    await File(file.path).copy(target.path);
    return target.path;
  }
}

String formatStorage(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)}KB';
  }
  return '$bytes B';
}

extension FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
