import 'package:flutter/material.dart';

import '../driving_record/driving_record.dart';
import '../driving_record/seven_day_driving_report.dart';

/// Aggregate driving trends and all-time totals.
class SummariesScreen extends StatelessWidget {
  const SummariesScreen({
    super.key,
    required this.record,
  });

  final DrivingRecord record;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Summaries')),
      body: ListenableBuilder(
        listenable: record,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (record.sessions.isNotEmpty)
                _SevenDayReportCard(
                  report: SevenDayDrivingReport.build(record.sessions),
                ),
              if (record.sessions.isNotEmpty) const SizedBox(height: 12),
              if (record.enabled)
                _DrivingRecordCard(record: record)
              else
                const _RecordingOffCard(),
            ],
          );
        },
      ),
    );
  }
}

class _SevenDayReportCard extends StatelessWidget {
  const _SevenDayReportCard({required this.report});

  final SevenDayDrivingReport report;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final end = report.periodEnd.subtract(const Duration(days: 1));
    final dateRange = '${localizations.formatShortDate(report.periodStart)}'
        ' – ${localizations.formatShortDate(end)}';
    final attentive = report.estimatedAttentiveFraction;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Seven-day report', style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              dateRange,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (report.sessionCount == 0)
              Text(
                'No completed drives in the last seven days.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              _StatRow(
                label: 'Driving days',
                value: '${report.drivingDayCount} of 7',
              ),
              const Divider(height: 20),
              _StatRow(
                label: 'Completed drives',
                value: report.sessionCount.toString(),
              ),
              const Divider(height: 20),
              _StatRow(
                label: 'Confirmed moving time',
                value: _formatDuration(report.movingDuration),
              ),
              const Divider(height: 20),
              _StatRow(
                label: 'Reliable camera coverage',
                value: '${(report.reliableCoverage * 100).round()}%',
              ),
              const SizedBox(height: 20),
              _ReportSection(
                icon: Icons.trending_up,
                title: 'Attention trend',
                body: _trendDescription(report),
              ),
              const SizedBox(height: 12),
              _ReportSection(
                icon: Icons.calendar_view_week_outlined,
                title: 'Daily consistency',
                body: _consistencyDescription(report),
              ),
              const SizedBox(height: 20),
              if (attentive != null)
                _StatRow(
                  label: 'Estimated attentive time',
                  value: '${(attentive * 100).round()}%',
                )
              else
                Text(
                  'At least 10 minutes of driving with 70% reliable camera '
                  'coverage is needed for a seven-day attention estimate.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              const Divider(height: 20),
              _StatRow(
                label: 'Attention reminders',
                value: report.attentionReminderCount.toString(),
              ),
              const Divider(height: 20),
              _StatRow(
                label: 'Drowsiness warnings',
                value: report.drowsinessEventCount.toString(),
              ),
              const Divider(height: 20),
              _StatRow(
                label: 'Possible phone-use time',
                value: _formatDuration(report.possiblePhoneUseDuration),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'Trends are estimates for reflection only, not a safety rating. '
              'Review this report only after parking.',
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

  String _trendDescription(SevenDayDrivingReport report) {
    final change = report.attentionTrendChange;
    return switch (report.attentionTrend) {
      AttentionTrend.improving => 'Estimated attentive time improved by '
          '${(change! * 100).abs().round()} points versus the previous '
          'seven days.',
      AttentionTrend.declining => 'Estimated attentive time decreased by '
          '${(change! * 100).abs().round()} points versus the previous '
          'seven days.',
      AttentionTrend.steady =>
        'Estimated attentive time was steady versus the previous seven days.',
      AttentionTrend.insufficientData =>
        'At least 10 minutes of driving with 70% reliable camera coverage is '
            'needed in both seven-day periods.',
    };
  }

  String _consistencyDescription(SevenDayDrivingReport report) {
    final spread = report.dailyAttentionSpread;
    return switch (report.dailyConsistency) {
      DailyConsistency.consistent => 'Attentive estimates were consistent across '
          '${report.qualifiedDrivingDayCount} reliable driving days'
          '${spread == null ? "." : " (${(spread * 100).round()}-point range)."}',
      DailyConsistency.somewhatVariable =>
        'Attentive estimates varied somewhat across '
            '${report.qualifiedDrivingDayCount} reliable driving days'
            '${spread == null ? "." : " (${(spread * 100).round()}-point range)."}',
      DailyConsistency.variable => 'Attentive estimates varied across '
          '${report.qualifiedDrivingDayCount} reliable driving days'
          '${spread == null ? "." : " (${(spread * 100).round()}-point range)."}',
      DailyConsistency.insufficientData =>
        'At least two driving days with 70% reliable camera coverage are '
            'needed to assess consistency.',
    };
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(body, style: textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingOffCard extends StatelessWidget {
  const _RecordingOffCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Driving record is off', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Turn on "Driving record" in Settings to start tracking how much '
              'of your driving time is distracted versus attentive.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrivingRecordCard extends StatelessWidget {
  const _DrivingRecordCard({required this.record});

  final DrivingRecord record;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final hasData = record.totalDuration > Duration.zero;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('All-time driving record', style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'All time behind the wheel with recording on.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (!hasData)
              Text(
                'No driving recorded yet. Turn on Driving mode and drive to '
                'build your record.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              Text(
                '${(record.distractedFraction * 100).toStringAsFixed(0)}%',
                style: textTheme.displaySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'of your driving time was distracted',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _StatRow(
                label: 'Time driven distracted',
                value: _formatDuration(record.distractedDuration),
              ),
              const Divider(height: 20),
              _StatRow(
                label: 'Time driven attentive',
                value: _formatDuration(record.attentiveDuration),
              ),
              const Divider(height: 20),
              _StatRow(
                label: 'Total driving time',
                value: _formatDuration(record.totalDuration),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _confirmClear(context),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear record'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear driving record?'),
        content: const Text(
          'This permanently erases your session summaries and all-time driving '
          'totals on this phone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      record.clear();
    }
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

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  return '${seconds}s';
}
