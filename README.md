# BabyLink app

Native Android companion for the self-hosted [BabyLink](https://github.com/mkampl/babylink)
baby monitor. Set up a device over Bluetooth, then listen — no cloud, no accounts.
Try the web app first at <https://babylink.itvoodoo.at>.

## Features

- Listen to every baby in a room at once (ESP32-S3 over PCM, phones/browsers over WebRTC).
- Auto-listen (opens on sound, mutes on quiet), listen-in and mute, per-baby.
- Local cry / disconnect alerts and an audible connection-lost alarm — works backgrounded.
- Per-baby sleep timeline and activity log.
- Battery readout for the baby device and this phone.
- Turn this phone into a baby unit (mic streaming).
- BLE setup wizard for BabyLink ESP32-S3 hardware.

## Install

Grab the APK from the [latest release](https://github.com/mkampl/babylink-app/releases/latest),
or build it yourself:

```sh
flutter pub get
flutter build apk --release
```

Point it at your own server in Settings (defaults to the <https://babylink.itvoodoo.at> demo).

## License

BSD-3-Clause — see `LICENSE`. Third-party packages: `THIRD_PARTY.md`.

The server/firmware live in the [babylink](https://github.com/mkampl/babylink) repo.
