String toFaDigits(dynamic input) {
  // Replaces ASCII digits 0-9 with Persian numerals.
  // Useful for showing numbers in RTL/Farsi UI without changing the underlying value.
  final persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  return input.toString().replaceAllMapped(
    RegExp(r'\d'),
    (m) => persian[int.parse(m[0]!)],
  );
}
