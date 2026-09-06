# Driver Attune

Driver Attune is a Flutter prototype that watches for distracted and drowsy
driving. It uses the phone's front camera, its accelerometer, and its GPS speed.

Camera images, detection results, location, sensor readings and saved records all
stay on the device, and there's no account required. The Google ML Kit SDK is
the one exception: it sends limited technical diagnostics and usage metrics back
to Google, which [`docs/privacy-policy.md`](docs/privacy-policy.md) covers in
detail.

Tested on a physical iPhone. Android is implemented, but it has seen far less
road time.

## Support website

The App Store support and privacy pages live under [`docs/`](docs/) and are
served from this repository by GitHub Pages:

- `https://ch1v4lry.github.io/Driver-Focus/support/`
- `https://ch1v4lry.github.io/Driver-Focus/privacy/`

## What it detects

| State | How it is decided |
| --- | --- |
| **Attentive** | Facing the calibrated road pose with eyes open. |
| **Glancing away** | Head off the road pose, but only briefly. Not a distraction yet. |
| **Looking away** | A glance held past the chosen time limit. Alerts. |
| **Eyes closed** | Both eyes read shut for longer than a blink. |
| **Drowsy** | Sustained eye closure (PERCLOS), or a held head-drop while the eyes are already drooping. |
| **Yawning** | A sustained wide-open mouth. Experimental. |
| **Using phone** | The app left the foreground while Driving mode was active and movement had been detected. |
| **Face not visible** | No face in frame. |

Two ideas carry most of the weight.

**Calibration.** Press *Calibrate* while looking at the road, and every head pose
after that is measured as a deviation from the one you captured. The mount can
sit off-centre or tilted without affecting the result. Calibration also pins the
eye-closed threshold to your own resting eye openness, and the mouth-open ratio
to your resting mouth.

**Duration.** Learning where each driver's mirrors sit would be a lot of
machinery for very little payoff, so the app tolerates any look away for a fixed
stretch and only counts it as a distraction past that. Mirror checks are quick.
So are shoulder checks and glances at the instruments. Hold your eyes anywhere
longer than the limit and it's eyes-off-road, whichever direction they're
pointed.

Yaw only counts while the car moves, since looking around at a red light is not
a distraction. GPS speed makes that call, because vibration on its own can't
separate an idling engine from a rolling one, and the accelerometer takes over
when location isn't available. Pitch and roll are judged either way, which
catches a head tilted down toward a lap.

Eye closure is checked before head pose. A drowsy driver's head droops forward or
lolls sideways, so checking pose first would classify that as looking away and
never examine the eyes, losing the exact posture that signals sleep.

## Settings

- **How soon to warn** - Safest (1.5s), Lenient (2.5s, default) or Lax (3.5s)
  before a look away counts as a distraction.
- **Yawn detection** - experimental; inconsistent across faces.
- **Loud drowsiness alarm** - on by default; plays over silent mode.
- **Driving record** - on by default; session summaries with confirmed moving
  time, reliable camera coverage, estimated attentive time and warning counts,
  plus individual records on the Records tab, and seven-day trends and all-time
  totals on the Summaries tab. The 100 newest drive summaries are retained.
- **Save drowsiness photos** - opt-in; saves one photo per drowsiness event so
  the driver can see what was caught, with an optional auto-delete.
- **Automatic Driving mode** - on by default; uses low-power activity recognition
  to enable Driving mode after the phone detects travel by car. The manual switch
  always overrides it.
- **Location accuracy** - Precise, Balanced (default), Battery saver, or Off.
  GPS runs only while Driving mode is on and the app is in the foreground. It is
  the largest battery draw in the app, and Off falls back to the accelerometer.

Camera processing stops the moment the app leaves the foreground. GPS and
vehicle-activity monitoring stop with it. If the vehicle looked like it was
moving at that point, the app logs the gap until you return as possible phone
use, and keeps it out of confirmed movement and reliable observation.

Everything recorded lives in the app's own storage. Photos aren't stored in the
camera roll, and nothing is uploaded.

## Mount quality

A persistent bar warns you when the setup is working against the detector: no
face in frame, eyes unreadable behind sunglasses, a shaky mount, poor lighting,
a face too small or drifting toward the frame edge.

Sunglasses are inferred from an eye-open reading that barely moves. Waiting to
catch a blink doesn't work, because frames are sampled far more slowly than a
blink lasts, so most blinks fall between samples entirely. Real eyes still wander
a little from one frame to the next, but sunglasses read almost perfectly steady.

## Running it

```bash
flutter pub get
```

```bash
flutter run --release -d <device-id>
```

Use `--release` on a physical iPhone. Debug builds need a local-network
connection back to the Mac, and they won't launch from the home screen on modern
iOS.

Motion-gated detection doesn't fire until the car moves, so testing it at a desk
needs a flag:

```bash
flutter run --release --dart-define=DRIVER_ATTUNE_SIMULATE_MOVING=true
```

It treats the vehicle as moving for the current run. Off by default, and it must
never reach an App Store build.

The app asks for camera (`NSCameraUsageDescription`), motion
(`NSMotionUsageDescription`) and location while in use
(`NSLocationWhenInUseUsageDescription`). Location only reads your speed. If you deny
it, the accelerometer takes over.

More setup notes:

- [Windows setup](docs/windows-setup.md)
- [iOS testing](docs/ios-testing.md)

## Tests

```bash
flutter test
```

Detection logic sits outside the widgets on purpose, so testing it needs no
camera. The analyzer, the trackers, the driving record, the motion detector and
the evidence store are all plain Dart.

## Project shape

```text
lib/
  main.dart
  app.dart
  features/
    alerts/                 alarm sound, alert interface
    distraction_detection/  per-frame classification, ML Kit, PERCLOS, yawn
    drive_session/          the live driving screen and its controller
    driving_record/         distracted vs. attentive time, persisted
    evidence/               drowsiness photos: capture, storage, gallery
    home/                   tab shell (Drive / Records / Summaries)
    motion/                 is the vehicle actually moving
    mount_quality/          phone-mount and environment warnings
    records/                individual drive records and drowsiness photos
    settings/               settings screen
    summaries/              Summaries tab
```

## Packages

`camera`, `google_mlkit_face_detection`, `geolocator`, `sensors_plus`,
`audioplayers`, `shared_preferences`, `path_provider`, `image`.

## Limits

A few constraints are built into the approach rather than being bugs.

- **The accelerometer cannot replace GPS.** It only stands in when location is
  denied, switched off, or lost. An idling car at a stop shakes about as much as
  a moving one, so the two states overlap, and the fallback holds its
  previous decision whenever a reading lands in between. A *Simulate moving*
  toggle on the drive screen forces the gate on for desk testing, and the camera
  overlay reports which signal made the call.
- **The shaky-mount threshold sits well above ordinary road vibration.** A mount
  already loose at the start of a drive has to be caught too, so the threshold
  can't adapt to how much the ride is currently shaking.
- **Yaw sign and camera geometry are verified against iPhone.** Other camera
  orientations would need checking before the pose maths can be trusted there.
- **ML Kit drives everything.** Where its face detection struggles, in heavy
  glare or near-profile head angles, the app tightens its thresholds rather than
  guessing, which trades some sensitivity for fewer false alarms.
