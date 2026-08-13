import 'package:flutter/material.dart';

/// Safety disclaimer and privacy summary, reachable from Settings.
///
/// App Review requires the privacy policy to be readable inside the app, not
/// only linked from the store listing, so the substance lives here rather than
/// behind a link that could break.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  /// The full text is shown below too, so a broken link cannot leave the app
  /// without a policy.
  static const String privacyPolicyUrl =
      'https://ch1v4lry.github.io/Driver-Focus/privacy/';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
          child: Text(
            text,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

    Widget para(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(text, style: textTheme.bodyMedium),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('About & Privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Card(
            color: colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'This is an aid, not a safety device',
                        style: textTheme.titleSmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Driver Focus cannot detect every instance of drowsiness or '
                    'distraction, and it is not a substitute for being rested '
                    'and attentive. Never rely on it to keep you awake. If you '
                    'feel tired, stop and rest.\n\n'
                    'Set the phone up before you drive, and do not interact '
                    'with it while the vehicle is moving.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          heading('Privacy'),
          para(
            'Driver Focus has no account, advertising, tracking, or '
            'developer-operated server. Camera images, face-detection results, '
            'location, motion readings, driving records, and drowsiness photos '
            'are processed or stored only on this phone. Google’s ML Kit sends '
            'limited technical diagnostics and usage metrics as described '
            'below.',
          ),
          heading('What the app uses'),
          para(
            'Camera — watches your face to work out where you are looking and '
            'whether your eyes are closing. Frames are analysed in memory and '
            'then discarded. They are not recorded or uploaded, apart from the '
            'optional drowsiness photos described below.',
          ),
          para(
            'Motion sensors — used to tell whether the phone is shaking on a '
            'loose mount, and, when location is unavailable, to guess whether '
            'the vehicle is moving. While automatic Driving mode is enabled '
            '(on by default), the phone also reports whether it believes it is '
            'traveling in a vehicle. Not stored.',
          ),
          para(
            'Location — only your speed is used, to tell whether the car is '
            'actually moving, so the app only warns about looking away while '
            'you are driving. Location runs only while Driving mode is on and '
            'the app is in the foreground. Your position is never stored and '
            'never transmitted. You can lower the accuracy or turn location '
            'off entirely in Settings.',
          ),
          heading('What is stored on this phone'),
          para(
            'Driving record — a local summary of each recorded drive, '
            'including its start time, confirmed moving and reliable '
            'observation time, estimated attentive and looking-away time, '
            'warning counts, possible phone-use time, and excluded low-quality '
            'time. All-time totals and seven-day trends are also kept. No '
            'images or locations are included. The 100 newest drive summaries '
            'are retained; saving another removes the oldest without changing '
            'the separate all-time totals. Erase the complete record any time '
            'from the Summaries tab.',
          ),
          para(
            'If you leave the app while Driving mode is active and the vehicle '
            'appeared to be moving, the interval until you return is saved as '
            'possible phone-use time. Camera, location, and activity monitoring '
            'stop in the background, so that interval is not treated as '
            'confirmed movement or reliable observation.',
          ),
          para(
            'Drowsiness photos — if you opt in, a still image is saved at the '
            'moment drowsiness is detected. These go to the app’s '
            'own private storage, not your camera roll, so other apps and the '
            'system photo picker cannot see them. They are never uploaded, and '
            'you can view or delete them from the Records tab.',
          ),
          para(
            'Driving records are enabled by default. Drowsiness photos are '
            'opt-in. Both can be controlled independently in Settings and are '
            'removed completely when you delete the app.',
          ),
          heading('What the app never does'),
          para(
            '• Upload camera images, face-detection results, location, motion '
            'readings, driving records, or drowsiness photos\n'
            '• Send your app data to a server operated by the developer\n'
            '• Sell data, show advertising, or track you across apps\n'
            '• Ask for an account or any personal details',
          ),
          heading('Third-party components'),
          para(
            'Face detection uses Google’s ML Kit. Camera images and detection '
            'results are processed on this device and are not sent to Google. '
            'The ML Kit iOS SDK does send Google limited device and app '
            'information, a per-installation identifier, API-use events, '
            'performance metrics, and errors for diagnostics and usage '
            'analytics. It may also contact Google for SDK updates and '
            'hardware-compatibility information.',
          ),
          heading('Your control'),
          para(
            'Camera, Location, and Motion & Fitness permissions can be '
            'withdrawn at any time in the iOS Settings app. Withdrawing camera '
            'access stops detection; withdrawing location makes the app fall '
            'back to motion sensing; and withdrawing Motion & Fitness access '
            'disables automatic Driving mode and may limit motion-based '
            'detection. Deleting the app removes everything it has stored. The '
            'Driver Focus developer does not receive or keep server-side user '
            'data to request or delete. Google’s handling of ML Kit diagnostics '
            'and usage metrics is governed by Google’s privacy policy.',
          ),
          const SizedBox(height: 16),
          SelectableText(
            'Full policy: $privacyPolicyUrl',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
