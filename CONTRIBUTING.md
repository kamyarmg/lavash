# Contributing to Lavash

Thanks for your interest in contributing! This guide explains how to set up the project, coding conventions, and how to submit changes.

## Development setup
- Requirements: Flutter 3.24+, Dart 3.9+
- Fetch packages:
  ```sh
  flutter pub get
  ```
- Run locally:
  ```sh
  flutter run -d chrome    # Web
  flutter run -d android   # Android
  ```
- Run checks:
  ```sh
  flutter analyze
  flutter test
  ```

## Branching & commits
- Create feature branches from `dev`: `feature/my-change`
- Keep commits focused and descriptive. Reference issues when applicable (e.g., `Fix: puzzle shuffle parity (#123)`).

## Coding style
- Follow Dart/Flutter best practices and existing patterns in `lib/`.
- Prefer small, focused widgets and clear naming.
- Write doc comments for non-obvious logic.
- Keep public behavior covered by tests where practical.

## Tests
- Add tests under `test/` for puzzle logic, utils, and UI where meaningful.
- Ensure `flutter test` passes.

## Submitting a PR
- Ensure `flutter analyze` and `flutter test` are green.
- Fill out the PR template: summary, screenshots (if UI), test plan.
- Be open to review comments and iterate.

## Releasing
- Update `CHANGELOG.md` and bump version in `pubspec.yaml` when preparing releases.

## Code of Conduct
- See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). By participating, you agree to abide by it.