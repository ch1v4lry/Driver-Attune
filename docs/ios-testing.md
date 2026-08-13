# iOS Testing

iOS testing should happen with a physical iPhone.

## Mac Checklist

1. Install Flutter.
2. Install Xcode.
3. Open Xcode once and accept required setup prompts.
4. Install CocoaPods if Flutter plugins require it.
5. Connect the iPhone by USB.
6. Trust the Mac from the iPhone prompt.
7. Enable Developer Mode on the iPhone.
8. From the repository root, run:

```bash
flutter doctor
flutter pub get
flutter create . --platforms=ios
flutter run
```
