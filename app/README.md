# School Manager Flutter app

L'app Android/iOS è organizzata in model, controller e view; i plugin nativi sono isolati negli adapter del model. L'architettura completa è documentata in `../docs/architecture/`.

```sh
flutter pub get
flutter analyze
flutter test --coverage
flutter run
```

Per generare l'APK Android: `flutter build apk --release`. Per iOS serve macOS con Xcode.

