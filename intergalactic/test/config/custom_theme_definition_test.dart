import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/custom_theme_definition.dart';

void main() {
  test('custom theme copy names preserve unique edited names', () {
    expect(uniqueCustomThemeCopyName('Variant', ['Original']), 'Variant');
  });

  test('custom theme copy names disambiguate existing names', () {
    expect(
      uniqueCustomThemeCopyName('Original', ['Original']),
      'Original Copy',
    );
    expect(
      uniqueCustomThemeCopyName('Original', [
        'Original',
        'Original Copy',
        'Original Copy 2',
      ]),
      'Original Copy 3',
    );
  });

  test('custom theme copy names normalize blank and case-only collisions', () {
    expect(uniqueCustomThemeCopyName('  ', ['Theme']), 'Theme Copy');
    expect(
      uniqueCustomThemeCopyName('original', ['Original']),
      'original Copy',
    );
  });
}
