# Privacy Policy for Driver Focus

**Last updated:** 18 August 2026

## Summary

Driver Focus has no account, advertising, tracking, or developer-operated
server. Camera images, face-detection results, location, motion readings,
driving records, and drowsiness photos are processed or stored only on your
phone as described below.

Driver Focus uses Google's ML Kit for face detection. Although images and
detection results stay on your phone, ML Kit sends Google limited technical
information about the device, app, API use, performance, and errors for
diagnostics and usage analytics. ML Kit may also contact Google for items such
as bug fixes, updated models, and hardware-compatibility information. See
"Third-party components" below for details.

## What the app accesses, and why

**Camera.** Driver Focus watches your face through the front camera to work out
where you are looking and whether your eyes are closing. Camera frames are
analysed on the device, in memory, and then discarded. They are not recorded,
not uploaded, and not saved, except by the one optional feature described
under "Drowsiness photos" below.

**Motion sensors.** The accelerometer is used to tell whether the phone is
shaking (a loose mount) and, when location is unavailable, to guess whether the
vehicle is moving. While automatic Driving mode is enabled (on by default), the
phone's activity recognition service also reports whether it believes the phone
is traveling in a vehicle. These readings are used as they arrive and are not
stored.

**Location.** Your GPS speed is used to decide whether the car is actually
moving, so the app only warns about looking away while you are driving. Only
speed is used. Your position is never stored, never written to a file, and never
transmitted. Location runs only while Driving mode is on and the app is in the
foreground. You can reduce the accuracy or turn location off entirely in the
app's Settings; with it off, the app falls back to the accelerometer.

## Face data

Driver Focus does not identify you, authenticate you, create a faceprint or
biometric template, or compare your face with other faces. To provide real-time
attention and drowsiness reminders, it temporarily processes front-camera
frames and face-detection results such as the face location, contours and
landmarks, head orientation, eye-open probabilities, mouth opening, and image
visibility and quality. This information is used only to estimate conditions
such as looking away, prolonged eye closure, yawning, or an obstructed camera.

Camera frames and face-detection results are held in memory only for the time
needed to analyse the current frame and are then discarded. They are not used
for advertising, profiling, identification, authentication, or model training.
They are not sent to the developer, uploaded, or shared with any third party.
Google's ML Kit performs face detection on the device and does not receive the
camera images or face-detection results. Its separate collection of limited
technical SDK diagnostics and usage metrics is explained under "Third-party
components."

The optional **Save drowsiness photos** setting is off by default. If you turn
it on, Driver Focus stores a still image from a frame in which drowsiness was
detected so that you can review what the app detected. These photos are stored
only in Driver Focus's private application-support directory on your phone,
outside the camera roll and system photo picker, and are excluded from device
backups. They are never uploaded or shared. You can delete one photo or all
photos from the Records tab. Unless you delete them, they remain until you
delete the app. If you turn on **Delete old photos automatically**, the app
keeps the newest 50 photos and removes older photos when a new photo is saved;
turning on this setting does not by itself remove photos already stored.

Driving records contain only aggregate durations and event counts. They do not
contain camera images, face landmarks, face geometry, face-detection results,
faceprints, or biometric identifiers.

## What is stored on your device

Two optional features can be controlled independently in Settings. Driving
records are enabled by default; drowsiness photos are opt-in:

**Driving record.** A local summary of each recorded drive, including its start
time, confirmed moving time, reliable observation time, estimated attentive and
looking-away time, warning counts, possible phone-use time, and time excluded
for visibility or quality problems. All-time attentive and distracted totals
are also kept, and the app derives seven-day consistency and attention trends
from the saved summaries. No images or locations are included. The 100 most
recent drive summaries are retained; when another is saved, the oldest summary
is automatically removed. This does not change the separately stored all-time
totals. You can erase the complete driving record at any time from the
Summaries tab.

If you leave Driver Focus while Driving mode is active and the vehicle appeared
to be moving, the time until you return is saved as possible phone-use time.
The camera, location, and activity monitoring are stopped while the app is in
the background, so this inferred interval is not counted as confirmed movement,
reliable observation, attentive time, or distracted time.

**Drowsiness photos.** If you opt in, the app saves a still image of you at the
moment drowsiness is detected, so you can see what it caught. These are
written to the app's own private storage, not your camera roll, so other apps
and the system photo picker cannot see them. They are never uploaded. You can
view them, delete any of them individually, or delete them all, from the Records
tab. If automatic deletion is enabled, the newest 50 are kept and older photos
are removed as new photos are saved. See "Face data" above for complete storage,
retention, and deletion details.

Both are removed completely when you delete the app.

## What is not done

- Camera images, face-detection results, location, motion readings, driving
  records, and drowsiness photos are not uploaded or shared.
- The developer does not operate a server or receive your app data.
- There is no advertising, cross-app tracking, or sale of data.
- No account is required and no personal information is requested.

## Third-party components

Face detection uses Google's ML Kit. ML Kit processes camera images and
face-detection results entirely on your device and does not send them to Google.
However, the ML Kit iOS SDK sends Google device and application information, a
per-installation identifier, performance metrics, API configuration, feature
events, and error codes for diagnostics and usage analytics. It may also contact
Google to receive bug fixes, updated models, and hardware-accelerator
compatibility information. Google describes this processing in its
[ML Kit Terms & Privacy](https://developers.google.com/ml-kit/terms) and
[Apple App Store data disclosure guide](https://developers.google.com/ml-kit/ios-data-disclosure).

Location and sensor readings come from the operating system's own services and
are not included in the information sent by Driver Focus to Google.

## Your control

Camera, Location, and Motion & Fitness permissions can be withdrawn at any time
in the iOS Settings app. Withdrawing camera access stops detection; withdrawing
location makes the app fall back to motion sensing; and withdrawing Motion &
Fitness access disables automatic Driving mode and may limit motion-based
detection. Deleting the app removes everything it has stored.

The Driver Focus developer does not receive or keep server-side user data to
access, correct, or delete. Google's handling of ML Kit diagnostics and usage
metrics is governed by Google's privacy policy.

## Children

Driver Focus is intended for licensed drivers and is not directed at children.

## Changes

If this policy changes, the updated version will be posted here and the date at
the top will change.

## Contact

Questions about this policy: driverfocus.support@gmail.com
