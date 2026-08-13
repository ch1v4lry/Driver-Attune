import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// One saved drowsiness photo.
class DrowsinessEvidence {
  const DrowsinessEvidence({required this.file, required this.capturedAt});

  final File file;
  final DateTime capturedAt;
}

/// Stores drowsiness photos in the app's private application-support directory.
///
/// This is private app storage, not the camera roll and not a shared album, so
/// the photos are not visible to other apps or to the system photo picker, and
/// nothing is uploaded anywhere. Platform configuration excludes this directory
/// from Android and iOS device backups. Deleting the app removes it.
class DrowsinessEvidenceStore {
  static const _folderName = 'drowsiness_evidence';

  /// How many photos are kept when [autoDeleteEnabled] is on. Oldest go first.
  static const int maxPhotos = 50;

  /// Whether old photos are pruned automatically.
  ///
  /// Off by default: these are the driver's own records, and some will want to
  /// keep a long trip's worth or hold on to them for their own reasons, so
  /// nothing is deleted on their behalf unless they ask for it.
  bool autoDeleteEnabled = false;

  Directory? _cached;

  Future<Directory> _directory() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/$_folderName');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _cached = dir;
    return dir;
  }

  /// Writes encoded JPEG bytes to storage, named by capture time, and prunes
  /// the oldest once past [maxPhotos].
  Future<DrowsinessEvidence> saveBytes(
    Uint8List jpeg,
    DateTime capturedAt,
  ) async {
    final dir = await _directory();
    final name = 'drowsy_${capturedAt.millisecondsSinceEpoch}.jpg';
    final target = File('${dir.path}/$name');
    await target.writeAsBytes(jpeg, flush: true);
    if (autoDeleteEnabled) {
      await _prune();
    }
    return DrowsinessEvidence(file: target, capturedAt: capturedAt);
  }

  /// All saved photos, newest first.
  Future<List<DrowsinessEvidence>> list() async {
    final dir = await _directory();
    if (!dir.existsSync()) {
      return const [];
    }
    final items = <DrowsinessEvidence>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) {
        continue;
      }
      final at = _timestampOf(entity);
      if (at != null) {
        items.add(DrowsinessEvidence(file: entity, capturedAt: at));
      }
    }
    items.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return items;
  }

  Future<void> delete(DrowsinessEvidence evidence) async {
    if (evidence.file.existsSync()) {
      await evidence.file.delete();
    }
  }

  Future<void> deleteAll() async {
    final dir = await _directory();
    if (!dir.existsSync()) {
      return;
    }
    for (final entity in dir.listSync()) {
      if (entity is File) {
        await entity.delete();
      }
    }
  }

  /// Trims to the newest [maxPhotos]. Only called with auto-delete on, and only
  /// when saving. Flipping the setting doesn't retroactively erase what the
  /// driver already has.
  Future<void> _prune() async {
    final items = await list();
    if (items.length <= maxPhotos) {
      return;
    }
    for (final old in items.skip(maxPhotos)) {
      await delete(old);
    }
  }

  /// Recovers the capture time from the filename. Returns null for anything
  /// that doesn't match, so stray files are ignored rather than shown.
  static DateTime? _timestampOf(File file) {
    final name = file.uri.pathSegments.last;
    final match = RegExp(r'^drowsy_(\d+)\.jpg$').firstMatch(name);
    if (match == null) {
      return null;
    }
    final millis = int.tryParse(match.group(1)!);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
