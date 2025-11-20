<p align="center">
	<img src="assets/images/lavash_logo.svg" alt="Lavash Logo" width="160" />
</p>

<p align="center">
	<strong>English</strong> | <a href="README.fa.md">فارسی</a>
</p>

<h1 align="center">Lavash — Sliding Puzzle Game</h1>

Lavash is a clean, modern sliding puzzle. It slices an image into a grid with a single empty space. Swap tiles by moving them into the empty cell and reconstruct the original image. Use the built-in gallery or pick your own photo and set new records!


## Features ✨

- Choose images from the built-in gallery or your device
- Multiple puzzle sizes: 3×3 up to 5×5
- Light/Dark mode with Material 3 color theming
- Toggle tile numbers for visual aid
- Auto-save and resume your game anytime
- Bilingual UI (Persian and English)
- Modern UI with the Persian font "Vazirmatn"


## How to Play 🧩

1) Pick an image: use the top slider to pick from built-in images or choose a photo from your gallery.
2) The puzzle starts: the image is split into tiles with one empty cell.
3) Move tiles: tap any tile adjacent to the empty cell to slide it into the empty spot.
4) Goal: restore the original image. Upon winning, your moves and time are displayed.

Tips:
- Tiles in the correct position get a green border.
- Use "Shuffle" to swap a few incorrect tiles and change the layout.
- In "Settings" you can change puzzle size, toggle tile numbers, switch theme, and choose language.


## Run the Project 🚀

Requirements:
- Flutter 3.24+ and Dart 3.9+
- Target platform SDKs (Android/iOS/Web)

Steps:
1) Fetch packages
2) Run on your desired platform

Suggested commands:

```sh
flutter pub get
flutter run -d chrome         # Web
# or
flutter run -d android        # Android (emulator/connected device)
```

Key files:
- App entry point: `lib/main.dart`
- Main screen and game logic: `lib/screens/home_screen.dart`
- Puzzle model and logic (grid, moves, solved-check, valid shuffling): `lib/models/puzzle.dart`
- Localized strings: `lib/core/strings.dart`
- Image utilities: `lib/core/image_utils.dart`, `lib/core/utils.dart`
- UI widgets (puzzle board, action bar, etc.): `lib/widgets/puzzle_widgets.dart`


## Code Structure & Architecture 🏗️

### Overview
Lavash follows a simple layered approach: **Model (pure logic) → State/Controller (screen) → Presentation (widgets)** with some utility helpers. There is no heavy state-management framework; Flutter `State` plus light persistence is enough for this scope.

### Modules
| Area                | Files                                              | Responsibility                                                                                        |
| ------------------- | -------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Model               | `lib/models/puzzle.dart`                           | Sliding puzzle logic: tile positions, moves, solvable shuffle, partial shuffle.                       |
| Core utils          | `lib/core/image_utils.dart`, `lib/core/utils.dart` | Decode images and Persian digit formatting.                                                           |
| Localization        | `lib/core/strings.dart`                            | Lightweight bilingual string getters (fa/en).                                                         |
| Screen / Controller | `lib/screens/home_screen.dart`                     | Orchestrates puzzle board, image selection, slicing, timer, persistence, settings overlay, win state. |
| UI Components       | `lib/widgets/puzzle_widgets.dart`                  | Background, slider, puzzle tiles, action bar, overlays, bottom sheets.                                |

### Data Flow
1. User selects or randomly loads an image.
2. Image decoded → sliced into tile images (`_buildSlices`).
3. PuzzleBoard holds logical positions; UI reads `board.tiles` to position widgets.
4. On tile tap: `board.move()` updates indices; state increments moves, checks solved.
5. Timer ticks each second until solved; both time and moves persisted periodically.

### Persistence
`SharedPreferences` stores:
- Settings (theme, language, dimension, show numbers)
- Last selected image reference (FILE:// / B64:// / asset path)
- Last game snapshot (dimension, tile indices CSV, moves, seconds, solved flag)
- Best records per dimension (fewest moves / fastest time)

### Solvable Shuffle Logic
Shuffling ensures the permutation is solvable by counting inversions (classic 15-puzzle rule):
- Odd dimension: even inversions.
- Even dimension: parity depends on empty row from bottom. This prevents unwinnable boards.

### Image Handling
Images are decoded into `ui.Image` (fast GPU paint). Tiles are drawn either by pre-sliced images or by a painter clipping the original for flexibility. Pre-slicing improves rebuild speed after moves.

### UI/UX Notes
- Material 3 dynamic color with seed palette and dark/light toggling.
- RTL direction when Persian language active.
- Animated scale/tap feedback on tiles and thumbnails.
- Win overlay shows records and encourages replay.
- Action bar uses blurred translucent glass style for modern feel.

### Performance Considerations
- Slicing done once per image/dimension change; tiles reuse `ui.Image` slices.
- Avoids rebuilding heavy image decode on each move; only lightweight position animations.
- Uses `AnimatedPositioned` + small `AnimatedContainer` transitions (cheap on GPU).

## Tech & Dependencies 🛠️

- Flutter (Material 3)
- google_fonts — "Vazirmatn" font
- image_picker — choose photos from gallery/camera
- shared_preferences — persist settings, records, and game state
- path_provider & path — local file paths (store user images)

See `pubspec.yaml` for the full list.


## Tests ✅

Run tests with:

```sh
flutter test
```

Sample tests live in `test/` and cover puzzle logic, image utilities, and strings.


## Contributing 🤝

Contributions are welcome!

1) Open an issue describing your proposal.
2) Fork and create a feature branch: `feature/my-awesome-idea`
3) Submit a PR with a clear description and screenshots/GIFs where helpful.
4) Follow linting rules and add/update tests where possible.


## License 📄

This project is released under the MIT License. See `LICENSE` for details. The Persian translation in `LICENSE` is for convenience; the English text is legally binding.


## Font Acknowledgment
This app uses the [Vazirmatn](https://fonts.google.com/specimen/Vazirmatn) font, created by the late [Saber Rastikerdar](https://fa.wikipedia.org/wiki/%D8%B5%D8%A7%D8%A8%D8%B1_%D8%B1%D8%A7%D8%B3%D8%AA%DB%8C%E2%80%8C%DA%A9%D8%B1%D8%AF%D8%A7%D8%B1%E2%80%8C). We deeply appreciate his invaluable work and legacy.


## Project Meta 📂

Additional repository docs:
- `CONTRIBUTING.md` – setup, branching, PR process.
- `CODE_OF_CONDUCT.md` – community behavior standards.
- `SECURITY.md` – how to report vulnerabilities.
- `CHANGELOG.md` – version history (Keep a Changelog format).
- `docs/BRANDING.md` – logo usage, colors, icon generation.

Automated checks run via GitHub Actions (`.github/workflows/flutter_ci.yml`).


