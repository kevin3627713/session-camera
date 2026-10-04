# Flutter IPA CI Calculator Demo

This is a minimal Flutter calculator app used to prove that a project can be built into an iOS `.ipa` by GitHub Actions without using a local Mac.

The app intentionally has only one feature: add, subtract, multiply, and divide two numbers.

## Run Locally

```bash
flutter pub get
flutter test
flutter run
```

## Build an Unsigned IPA in GitHub Actions

Copy this demo to the root of a GitHub repository, keep `.github/workflows/release-ios-unsigned.yml`, and push either:

- a tag, such as `v0.1.0`
- the `test` branch
- a manual `workflow_dispatch` run

The unsigned IPA will be uploaded as the `ios_unsigned_ipa` artifact.
