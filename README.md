# بازی لواش

## CI: Android APK on push

This repo builds an Android release APK automatically on every push to `main` using GitHub Actions.

- Workflow file: `.github/workflows/android-apk.yml`
- Artifact name: `app-release-apk`
- APK path inside the artifact: `build/app/outputs/flutter-apk/app-release.apk`

You can also trigger it manually from the Actions tab via "Run workflow".

بازی لواش یک [پازل کشویی](https://fa.wikipedia.org/wiki/%D9%BE%D8%A7%D8%B2%D9%84_%DA%A9%D8%B4%D9%88%DB%8C%DB%8C) است که کاربران باید بتوانند با جابجایی قطعات، تصویر نهایی را کامل کنند. 