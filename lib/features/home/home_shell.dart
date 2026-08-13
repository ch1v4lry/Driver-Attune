import 'dart:async';

import 'package:flutter/material.dart';

import '../drive_session/drive_session_screen.dart';
import '../driving_record/driving_record.dart';
import '../driving_record/driving_record_store.dart';
import '../evidence/drowsiness_evidence_store.dart';
import '../records/records_screen.dart';
import '../summaries/summaries_screen.dart';

/// Hosts the app's tabs and owns the shared driving record.
///
/// The two screens live in an [IndexedStack] so the camera keeps running when
/// the user peeks at their summaries instead of tearing down and
/// reinitializing.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final DrivingRecord _record = DrivingRecord();
  final DrivingRecordStore _store = DrivingRecordStore();
  final DrowsinessEvidenceStore _evidenceStore = DrowsinessEvidenceStore();
  Timer? _saveTimer;
  bool _dirty = false;
  int _index = 0;
  int _recordsVisitId = 0;
  final GlobalKey _pagesKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _record.addListener(_markDirty);
    _loadRecord();
    // Flush periodically so a long trip's progress survives an unexpected exit.
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _flush());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _record.removeListener(_markDirty);
    unawaited(_flush());
    _record.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save whenever the app leaves the foreground.
    if (state != AppLifecycleState.resumed) {
      unawaited(_flush());
    }
  }

  Future<void> _loadRecord() async {
    final saved = await _store.load();
    final hadPendingChanges = _dirty;
    _record.restore(
      distracted: saved.distracted,
      attentive: saved.attentive,
      enabled: saved.enabled,
      sessions: saved.sessions,
    );
    // Loading alone isn't a real change, but preserve anything the user changed
    // while storage was loading so the next flush persists the merged result.
    _dirty = hadPendingChanges;
  }

  void _markDirty() => _dirty = true;

  Future<void> _flush() async {
    if (!_dirty) {
      return;
    }
    _dirty = false;
    await _store.save(
      distracted: _record.distractedDuration,
      attentive: _record.attentiveDuration,
      enabled: _record.enabled,
      sessions: _record.sessions,
    );
  }

  void _selectDestination(int index) {
    if (index == 1 && _index != 1) {
      _recordsVisitId++;
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
      key: _pagesKey,
      index: _index,
      children: [
        DriveSessionScreen(record: _record, evidenceStore: _evidenceStore),
        RecordsScreen(
          record: _record,
          evidenceStore: _evidenceStore,
          visitId: _recordsVisitId,
        ),
        SummariesScreen(record: _record),
      ],
    );

    return OrientationBuilder(
      builder: (context, _) {
        final orientation = MediaQuery.orientationOf(context);
        if (orientation == Orientation.landscape) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _selectDestination,
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.directions_car_outlined),
                      selectedIcon: Icon(Icons.directions_car),
                      label: Text('Drive'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.folder_outlined),
                      selectedIcon: Icon(Icons.folder),
                      label: Text('Records'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.insights_outlined),
                      selectedIcon: Icon(Icons.insights),
                      label: Text('Summaries'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages),
              ],
            ),
          );
        }

        return Scaffold(
          body: pages,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _selectDestination,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.directions_car_outlined),
                selectedIcon: Icon(Icons.directions_car),
                label: 'Drive',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: 'Records',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Summaries',
              ),
            ],
          ),
        );
      },
    );
  }
}
