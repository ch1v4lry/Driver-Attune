import 'dart:io';

import 'package:driver_attune/features/evidence/drowsiness_evidence_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory supportDir;
  late DrowsinessEvidenceStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('evidence_test');
    supportDir = await Directory('${tempDir.path}/support').create();
    // path_provider has no implementation under `flutter test`, so stand in for
    // the application-support directory with a temp folder.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationSupportDirectory'
          ? supportDir.path
          : null,
    );
    store = DrowsinessEvidenceStore();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Stand-in for encoded JPEG bytes.
  Uint8List fakeJpeg() => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

  test('saves a capture and lists it back', () async {
    final at = DateTime(2026, 7, 1, 8, 30);
    await store.saveBytes(fakeJpeg(), at);

    final items = await store.list();
    expect(items, hasLength(1));
    expect(items.single.capturedAt, at);
    expect(items.single.file.existsSync(), isTrue);
  });

  test('writes the given bytes to disk', () async {
    final saved = await store.saveBytes(fakeJpeg(), DateTime(2026, 7, 1));
    expect(await saved.file.readAsBytes(), fakeJpeg());
  });

  test('lists newest first', () async {
    await store.saveBytes(fakeJpeg(), DateTime(2026, 7, 1));
    await store.saveBytes(fakeJpeg(), DateTime(2026, 7, 3));
    await store.saveBytes(fakeJpeg(), DateTime(2026, 7, 2));

    final items = await store.list();
    expect(
      items.map((e) => e.capturedAt).toList(),
      [DateTime(2026, 7, 3), DateTime(2026, 7, 2), DateTime(2026, 7, 1)],
    );
  });

  test('keeps everything by default', () async {
    // Auto-delete is opt-in: these are the driver's own records, so nothing is
    // removed unless they ask for it.
    for (var i = 0; i < DrowsinessEvidenceStore.maxPhotos + 5; i++) {
      await store.saveBytes(
        fakeJpeg(),
        DateTime(2026, 1, 1).add(Duration(minutes: i)),
      );
    }

    expect(
      await store.list(),
      hasLength(DrowsinessEvidenceStore.maxPhotos + 5),
    );
  });

  test('prunes the oldest past the cap when auto-delete is on', () async {
    store.autoDeleteEnabled = true;
    for (var i = 0; i < DrowsinessEvidenceStore.maxPhotos + 5; i++) {
      await store.saveBytes(
        fakeJpeg(),
        DateTime(2026, 1, 1).add(Duration(minutes: i)),
      );
    }

    final items = await store.list();
    expect(items, hasLength(DrowsinessEvidenceStore.maxPhotos));
    // The survivors are the most recent ones.
    expect(
        items.first.capturedAt,
        DateTime(2026, 1, 1).add(
          const Duration(minutes: DrowsinessEvidenceStore.maxPhotos + 4),
        ));
  });

  test('turning auto-delete on does not erase what is already saved', () async {
    for (var i = 0; i < DrowsinessEvidenceStore.maxPhotos + 5; i++) {
      await store.saveBytes(
        fakeJpeg(),
        DateTime(2026, 1, 1).add(Duration(minutes: i)),
      );
    }

    // Flipping the setting must not retroactively delete anything; trimming
    // only happens as new photos arrive.
    store.autoDeleteEnabled = true;
    expect(
      await store.list(),
      hasLength(DrowsinessEvidenceStore.maxPhotos + 5),
    );
  });

  test('deletes a single photo', () async {
    await store.saveBytes(fakeJpeg(), DateTime(2026, 7, 1));
    await store.saveBytes(fakeJpeg(), DateTime(2026, 7, 2));

    final items = await store.list();
    await store.delete(items.first);

    final left = await store.list();
    expect(left, hasLength(1));
    expect(left.single.capturedAt, DateTime(2026, 7, 1));
  });

  test('deletes everything', () async {
    await store.saveBytes(fakeJpeg(), DateTime(2026, 7, 1));
    await store.saveBytes(fakeJpeg(), DateTime(2026, 7, 2));

    await store.deleteAll();

    expect(await store.list(), isEmpty);
  });

  test('ignores unrelated files in the folder', () async {
    await store.saveBytes(fakeJpeg(), DateTime(2026, 7, 1));
    final dir = Directory('${supportDir.path}/drowsiness_evidence');
    await File('${dir.path}/notes.txt').writeAsString('stray');

    final items = await store.list();
    expect(items, hasLength(1));
  });

  test('starts empty', () async {
    expect(await store.list(), isEmpty);
  });
}
