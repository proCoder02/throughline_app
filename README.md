# Throughline (Flutter client)

Flutter isn't installed on this machine, so only `lib/` + `pubspec.yaml` were generated here — no `android/`/`ios/` platform folders exist yet. To finish setup:

```
flutter create . --platforms=android,ios   # adds platform folders only, won't touch lib/ or pubspec.yaml
flutter pub get
```

Then add permissions (required for the `record` package):
- `android/app/src/main/AndroidManifest.xml`: `<uses-permission android:name="android.permission.RECORD_AUDIO"/>` and `<uses-permission android:name="android.permission.INTERNET"/>`
- `ios/Runner/Info.plist`: `NSMicrophoneUsageDescription`

Point the app at your backend:
```
flutter run --dart-define=API_BASE_URL=http://<your-lan-ip>:5000
```
(Android emulator default is `10.0.2.2:5000`, already baked in as the fallback.)

## Decisions made against the spec (flagging, not silently deviating)

1. **§8 recording: implemented Path B only** (record → `/transcribe` → `/save` → `/analyze`), not the live `/ws/listen` streaming path. Chosen because the spec itself calls B "simpler, robust, far less code," it sidesteps the WebM/Opus codec risk called out in §7, and it matches the request to minimize build effort. Consequence: no live per-utterance transcript view, no in-call speaker-rename prompts, and the chat-thread composer has no mic button (resuming a live session onto an existing conversation is a `/ws/listen`-only capability).
2. `/transcribe`'s success response shape isn't specified in the spec — assumed `{"transcript": "..."}"` in `conversation_service.dart`. Confirm against `app.py` and adjust the one field-access line if it differs.
3. Icons use Flutter's Material icon set rather than recreating the web app's custom inline SVGs, to keep this buildable without asset porting.
4. Friends row subtitle reads "Tap to view mood timeline" instead of the spec's literal "Mood tracked today," since confirming that per friend would mean an extra API call per row.
"# throughline_app" 
