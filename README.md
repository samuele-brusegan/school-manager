# School Manager

An offline-first Flutter app to organise the school day: timetable, agenda, grades, attendance and the ClasseViva school register — all on-device. Android is the primary platform; iOS and web are supported.

## Features

- **Home** – at-a-glance dashboard: the next school day, upcoming tests and personal tasks for the week ahead.
- **Timetable** – weekly grid with shared bell schedules (period times are defined once and apply to every day; each weekday only overrides the *number* of periods), colour-coded subjects, and lessons that compress vertically to fit the screen before falling back to scrolling.
- **Agenda** – day / week / month views with swipe navigation, homework and personal tasks, and manual test tagging that overrides keyword detection.
- **Grades** – animated average gauge, per-period and per-subject dashboards, grade distribution charts and a chronological trend view.
- **Register ("Altro")** – presences (absences, delays and early exits with an annual-hours counter against the 25% admission limit), disciplinary notes, noticeboard, didactic materials, documents, textbooks and statistics.
- **ClasseViva integration** – secure credential storage, saved-session detection (login is blocked until logout), timetable import, per-section refresh and an automatic sync timer (configurable, 5 minutes by default). Noticeboard circulars open in-app with read/unread styling, attachment counters, first-page PDF previews and a built-in viewer that never writes files to disk.
- **Settings** – multi-page, searchable settings hub: theme, weekend visibility, schedule, subjects, rooms and teachers (with contact metadata: email, phone, birthday, notes), grade targets, backup/restore (JSON), and a hidden debug page unlocked by tapping the app version 7 times.
- **Offline-first** – every ClasseViva response is cached in SQLite; the app is fully usable without connectivity.

## Status

MVP in active development. The ClasseViva protocol is reverse-engineered, unofficial and may change; some sections depend on the permissions of the linked profile. A cloud backend and account sync are out of scope. On the web, a stateless HTTP proxy is used to bypass CORS.

## Architecture

Strict MVC: views render state and forward user intents to controllers; controllers coordinate use cases; the model defines entities, rules and repository contracts. SQLite, secure storage and REST adapters implement the model's interfaces. See [docs/architecture/overview.md](docs/architecture/overview.md).

## Getting started

With a stable Flutter SDK installed:

```sh
cd app
flutter pub get
flutter run
```

Builds:

```sh
flutter build apk --release        # Android APK
flutter build appbundle --release  # Play Store bundle
flutter build ipa --release        # iOS (requires macOS + Xcode)
flutter build web --release        # Web
```

### Web / local development

The browser cannot call the ClasseViva API directly (CORS), so a loopback-only development proxy is provided:

```sh
cd app
dart run tool/classviva_proxy.dart   # terminal 1
flutter run -d chrome                # terminal 2
```

The proxy accepts `localhost`/`127.0.0.1` origins only and logs method, status and a redacted path — never headers, bodies or credentials. In production, either set `CLASSVIVA_API_BASE_URL` to the HTTPS URL of a same-origin proxy, or keep the default `/classeviva/rest/` path and configure the web server's reverse proxy accordingly. Serve the app over HTTPS (or `localhost`) so the secure credential store is available. Browser data is persisted via IndexedDB.

## Privacy

No external analytics or tracking: all data stays on the device. The privacy policy for store listings is in [docs/privacy-policy.md](docs/privacy-policy.md).

## Verification

```sh
cd app
flutter analyze
flutter test --coverage
```

## Possible future work

- **On-device AI timetable import**: recognising the schedule grid from a photo or screenshot with a model running locally on the phone. Under evaluation; not planned for the MVP.
