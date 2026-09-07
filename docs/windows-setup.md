# Windows Setup

Flutter development and the test suite run fine on Windows. Building and running
on an iPhone needs a Mac; see [iOS testing](ios-testing.md) for that.

## Install

1. Install Git for Windows if it is not already installed.
2. Install the Flutter SDK from the official Flutter installation guide.
3. Add Flutter's `bin` directory to your `Path`.
4. Restart PowerShell.
5. Run:

```powershell
flutter doctor
flutter pub get
flutter test
```

## Generate Platform Folders

From the repository root:

```powershell
flutter create . --platforms=android,ios
```

Review the generated files before committing, since the command rewrites
platform configuration.

## Git Safe Directory

If Git reports dubious ownership of the repository folder, run:

```powershell
git config --global --add safe.directory C:/path/to/Driver-Attune
```

Only do this for folders you trust.
