import 'package:flutter/material.dart';

import '../distraction_detection/glance_sensitivity.dart';
import '../motion/gps_accuracy.dart';
import 'about_screen.dart';

class DriveSettingsScreen extends StatefulWidget {
  const DriveSettingsScreen({
    super.key,
    required this.yawnEnabled,
    required this.onYawnEnabledChanged,
    required this.drowsinessAlarmEnabled,
    required this.onDrowsinessAlarmEnabledChanged,
    required this.recordingEnabled,
    required this.onRecordingEnabledChanged,
    required this.sensitivity,
    required this.onSensitivityChanged,
    required this.evidencePhotosEnabled,
    required this.onEvidencePhotosEnabledChanged,
    required this.evidenceAutoDeleteEnabled,
    required this.onEvidenceAutoDeleteEnabledChanged,
    required this.evidenceKeepLimit,
    required this.automaticDrivingModeEnabled,
    required this.onAutomaticDrivingModeEnabledChanged,
    required this.gpsAccuracy,
    required this.onGpsAccuracyChanged,
  });

  final bool yawnEnabled;
  final ValueChanged<bool> onYawnEnabledChanged;
  final bool drowsinessAlarmEnabled;
  final ValueChanged<bool> onDrowsinessAlarmEnabledChanged;
  final bool recordingEnabled;
  final ValueChanged<bool> onRecordingEnabledChanged;
  final GlanceSensitivity sensitivity;
  final ValueChanged<GlanceSensitivity> onSensitivityChanged;
  final bool evidencePhotosEnabled;
  final ValueChanged<bool> onEvidencePhotosEnabledChanged;
  final bool evidenceAutoDeleteEnabled;
  final ValueChanged<bool> onEvidenceAutoDeleteEnabledChanged;

  /// How many photos auto-delete keeps, for the description text.
  final int evidenceKeepLimit;

  final bool automaticDrivingModeEnabled;
  final Future<bool> Function(bool enabled)
      onAutomaticDrivingModeEnabledChanged;
  final GpsAccuracyMode gpsAccuracy;
  final ValueChanged<GpsAccuracyMode> onGpsAccuracyChanged;

  @override
  State<DriveSettingsScreen> createState() => _DriveSettingsScreenState();
}

class _DriveSettingsScreenState extends State<DriveSettingsScreen> {
  late bool _yawnEnabled = widget.yawnEnabled;
  late bool _drowsinessAlarmEnabled = widget.drowsinessAlarmEnabled;
  late bool _recordingEnabled = widget.recordingEnabled;
  late GlanceSensitivity _sensitivity = widget.sensitivity;
  late bool _evidencePhotosEnabled = widget.evidencePhotosEnabled;
  late bool _evidenceAutoDeleteEnabled = widget.evidenceAutoDeleteEnabled;
  late bool _automaticDrivingModeEnabled = widget.automaticDrivingModeEnabled;
  late GpsAccuracyMode _gpsAccuracy = widget.gpsAccuracy;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'How soon to warn',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'How long you may look away from the road before it counts as a '
              'distraction.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          RadioGroup<GlanceSensitivity>(
            groupValue: _sensitivity,
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _sensitivity = value);
              widget.onSensitivityChanged(value);
            },
            child: Column(
              children: [
                for (final option in GlanceSensitivity.values)
                  RadioListTile<GlanceSensitivity>(
                    value: option,
                    title: Text('${option.label} — ${option.secondsLabel}'),
                    subtitle: Text(option.description),
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          SwitchListTile(
            isThreeLine: true,
            title: const Text(
              'Automatically enable Driving mode when traveling by car',
            ),
            subtitle: const Text(
              'Uses low-power activity recognition while the app is open. '
              'Detection can mistake a passenger for the driver; use the '
              'Driving mode switch to override it at any time.',
            ),
            value: _automaticDrivingModeEnabled,
            onChanged: (value) async {
              setState(() => _automaticDrivingModeEnabled = value);
              final actual =
                  await widget.onAutomaticDrivingModeEnabledChanged(value);
              if (mounted && actual != _automaticDrivingModeEnabled) {
                setState(() => _automaticDrivingModeEnabled = actual);
              }
            },
          ),
          SwitchListTile(
            title: const Text('Yawn detection'),
            subtitle: const Text(
              'Experimental — may be inconsistent across faces. Calibrate with '
              'your mouth relaxed for the best results.',
            ),
            value: _yawnEnabled,
            onChanged: (value) {
              setState(() => _yawnEnabled = value);
              widget.onYawnEnabledChanged(value);
            },
          ),
          SwitchListTile(
            title: const Text('Loud drowsiness alarm'),
            subtitle: const Text(
              'Plays a loud 3-second alarm when drowsiness is detected while '
              'driving.',
            ),
            value: _drowsinessAlarmEnabled,
            onChanged: (value) {
              setState(() => _drowsinessAlarmEnabled = value);
              widget.onDrowsinessAlarmEnabledChanged(value);
            },
          ),
          SwitchListTile(
            isThreeLine: true,
            title: const Text('Driving record'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Track how much of your driving time is spent distracted '
                  'versus attentive. View it on the Summaries tab.',
                ),
                const SizedBox(height: 6),
                Text(
                  'Your data stays on this phone — it is never uploaded, '
                  'shared, or collected.',
                  style: textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            value: _recordingEnabled,
            onChanged: (value) {
              setState(() => _recordingEnabled = value);
              widget.onRecordingEnabledChanged(value);
            },
          ),
          SwitchListTile(
            isThreeLine: true,
            title: const Text('Save drowsiness photos'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Takes a photo when drowsiness is detected while driving, so '
                  'you can see what the app caught. View them on the Summaries '
                  'tab.',
                ),
                const SizedBox(height: 6),
                Text(
                  'Photos are kept on this phone only — not in your camera '
                  'roll, never uploaded, shared, or collected. You can delete '
                  'them any time.',
                  style: textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            value: _evidencePhotosEnabled,
            onChanged: (value) {
              setState(() => _evidencePhotosEnabled = value);
              widget.onEvidencePhotosEnabledChanged(value);
            },
          ),
          SwitchListTile(
            title: const Text('Delete old photos automatically'),
            subtitle: Text(
              _evidenceAutoDeleteEnabled
                  ? 'Keeps only the newest ${widget.evidenceKeepLimit}, '
                      'trimming older ones as new photos are saved.'
                  : 'Off — every photo is kept until you delete it yourself.',
            ),
            // Only meaningful when photos are being saved at all.
            value: _evidenceAutoDeleteEnabled,
            onChanged: _evidencePhotosEnabled
                ? (value) {
                    setState(() => _evidenceAutoDeleteEnabled = value);
                    widget.onEvidenceAutoDeleteEnabledChanged(value);
                  }
                : null,
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Location accuracy',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Your speed decides whether head turns are judged at all — turning '
              'to look around only matters while the car is moving. GPS is the '
              'largest battery draw in the app, so this trades accuracy against '
              'battery.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          RadioGroup<GpsAccuracyMode>(
            groupValue: _gpsAccuracy,
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _gpsAccuracy = value);
              widget.onGpsAccuracyChanged(value);
            },
            child: Column(
              children: [
                for (final option in GpsAccuracyMode.values)
                  RadioListTile<GpsAccuracyMode>(
                    value: option,
                    title: Text(option.label),
                    subtitle: Text(option.description),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Location is only ever used on this phone to work out your speed. '
              'It is never stored, uploaded, or shared.',
              style: textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('About & Privacy'),
            subtitle: const Text(
              'What this app can and cannot do, and what it does with your '
              'data.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
