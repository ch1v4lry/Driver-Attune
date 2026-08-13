import 'package:flutter/material.dart';

import '../driving_record/driving_record.dart';
import '../driving_record/driving_session_summary.dart';
import '../evidence/drowsiness_evidence_store.dart';
import '../evidence/evidence_gallery_screen.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({
    super.key,
    required this.record,
    required this.evidenceStore,
    required this.visitId,
  });

  final DrivingRecord record;
  final DrowsinessEvidenceStore evidenceStore;

  /// Changes each time the user enters this tab.
  final int visitId;

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  DateTime? _selectedStartedAt;

  @override
  void initState() {
    super.initState();
    _selectLatest();
  }

  @override
  void didUpdateWidget(RecordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visitId != oldWidget.visitId) {
      _selectLatest();
    }
  }

  void _selectLatest() {
    _selectedStartedAt = widget.record.latestSession?.startedAt;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Records')),
      body: ListenableBuilder(
        listenable: widget.record,
        builder: (context, _) {
          final sessions = widget.record.sessions;
          final selected = sessions.cast<DrivingSessionSummary?>().firstWhere(
                (session) => session?.startedAt == _selectedStartedAt,
                orElse: () => sessions.isEmpty ? null : sessions.first,
              );
          if (selected != null && selected.startedAt != _selectedStartedAt) {
            _selectedStartedAt = selected.startedAt;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _RecordSelector(
                sessions: sessions,
                selectedStartedAt: selected?.startedAt,
                onChanged: (startedAt) {
                  setState(() => _selectedStartedAt = startedAt);
                },
              ),
              const SizedBox(height: 12),
              if (selected != null)
                _DriveRecordCard(session: selected)
              else
                const _NoDriveRecordsCard(),
              const SizedBox(height: 12),
              _EvidenceCard(store: widget.evidenceStore),
            ],
          );
        },
      ),
    );
  }
}

class _RecordSelector extends StatelessWidget {
  const _RecordSelector({
    required this.sessions,
    required this.selectedStartedAt,
    required this.onChanged,
  });

  final List<DrivingSessionSummary> sessions;
  final DateTime? selectedStartedAt;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return DropdownButtonFormField<DateTime>(
      key: ValueKey(selectedStartedAt),
      initialValue: selectedStartedAt,
      decoration: const InputDecoration(
        labelText: 'Driving record',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.history),
      ),
      hint: const Text('No completed drives'),
      items: [
        for (final session in sessions)
          DropdownMenuItem(
            value: session.startedAt,
            child: Text(
              _recordLabel(session, localizations),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: sessions.isEmpty ? null : onChanged,
    );
  }

  String _recordLabel(
    DrivingSessionSummary session,
    MaterialLocalizations localizations,
  ) {
    final started = session.startedAt.toLocal();
    final date = localizations.formatMediumDate(started);
    final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(started));
    return '$date at $time · ${_formatDuration(session.movingDuration)}';
  }
}

class _DriveRecordCard extends StatelessWidget {
  const _DriveRecordCard({required this.session});

  static const _minimumCoverageForEstimate = 0.7;

  final DrivingSessionSummary session;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final coverage = session.reliableCoverage;
    final attentive = coverage >= _minimumCoverageForEstimate
        ? session.estimatedAttentiveFraction
        : null;
    final localizations = MaterialLocalizations.of(context);
    final started = session.startedAt.toLocal();
    final startedLabel = '${localizations.formatMediumDate(started)} at '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(started))}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Drive record', style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              startedLabel,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _StatRow(
              label: 'Confirmed moving time',
              value: _formatDuration(session.movingDuration),
            ),
            const Divider(height: 20),
            _StatRow(
              label: 'Reliable observation time',
              value: _formatDuration(session.reliableObservationDuration),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: coverage.clamp(0, 1),
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 6),
            Text(
              '${(coverage * 100).round()}% reliable camera coverage',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (attentive != null) ...[
              Text(
                '${(attentive * 100).round()}%',
                style: textTheme.displaySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'estimated attentive time during reliable observations',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ] else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Not enough reliable camera coverage to estimate attentive '
                  'time for this drive.',
                ),
              ),
            const SizedBox(height: 20),
            _StatRow(
              label: 'Attentive time',
              value: _formatDuration(session.attentiveDuration),
            ),
            const Divider(height: 20),
            _StatRow(
              label: 'Sustained looking-away time',
              value: _formatDuration(session.lookingAwayDuration),
            ),
            const Divider(height: 20),
            _StatRow(
              label: 'Attention reminders',
              value: session.attentionReminderCount.toString(),
            ),
            const Divider(height: 20),
            _StatRow(
              label: 'Drowsiness warnings',
              value: session.drowsinessEventCount.toString(),
            ),
            const Divider(height: 20),
            _StatRow(
              label: 'Possible phone-use time',
              value: _formatDuration(session.possiblePhoneUseDuration),
            ),
            const Divider(height: 20),
            _StatRow(
              label: 'Face not visible',
              value: _formatDuration(session.faceNotVisibleDuration),
            ),
            const Divider(height: 20),
            _StatRow(
              label: 'Other low-quality time',
              value: _formatDuration(session.lowQualityDuration),
            ),
            const SizedBox(height: 14),
            Text(
              'Estimates are for reflection only, not a safety rating. Review '
              'this record only after parking.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoDriveRecordsCard extends StatelessWidget {
  const _NoDriveRecordsCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'No completed drive records yet. A drive is saved after at least one '
          'minute of confirmed movement.',
        ),
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.store});

  final DrowsinessEvidenceStore store;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: FutureBuilder<List<DrowsinessEvidence>>(
        future: store.list(),
        builder: (context, snapshot) {
          final count = snapshot.data?.length;
          return ListTile(
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text('Drowsiness photos', style: textTheme.titleMedium),
            subtitle: Text(
              count == null
                  ? 'Kept on this phone only.'
                  : count == 0
                      ? 'None saved yet. Kept on this phone only.'
                      : '$count saved, on this phone only.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EvidenceGalleryScreen(store: store),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: textTheme.bodyLarge)),
        const SizedBox(width: 12),
        Text(
          value,
          textAlign: TextAlign.end,
          style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  return '${seconds}s';
}
