import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/bulk_import_view.dart';

void main() {
  test('bulk import shortcodes avoid existing suffix collisions', () {
    expect(
      resolveBulkImportShortcodes(['ship', 'ship', 'ship_1', 'ship', 'ship_2']),
      ['ship', 'ship_3', 'ship_1', 'ship_4', 'ship_2'],
    );
  });
}
