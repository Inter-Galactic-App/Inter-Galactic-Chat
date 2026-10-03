import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/call_view/call_view.dart';

void main() {
  test('desktop call tiles stay widescreen and fit changing grids', () {
    for (final count in [1, 2, 3, 6, 12]) {
      for (final size in [
        (width: 925.0, height: 900.0),
        (width: 1200.0, height: 650.0),
        (width: 480.0, height: 360.0),
      ]) {
        final metrics = debugCallGridMetricsForTesting(
          itemCount: count,
          maxWidth: size.width,
          maxHeight: size.height,
        );
        final rows = (count / metrics.columns).ceil();

        expect(metrics.width / metrics.height, closeTo(16 / 9, 0.00001));
        expect(
          metrics.columns * metrics.width + (metrics.columns - 1) * 12,
          lessThanOrEqualTo(size.width + 0.00001),
        );
        expect(
          rows * metrics.height + (rows - 1) * 12,
          lessThanOrEqualTo(size.height + 0.00001),
        );
      }
    }
  });

  test('three desktop tiles use a balanced two-column layout', () {
    final metrics = debugCallGridMetricsForTesting(
      itemCount: 3,
      maxWidth: 925,
      maxHeight: 900,
    );

    expect(metrics.columns, 2);
  });

  test('desktop tiles shrink with the window without changing ratio', () {
    final large = debugCallGridMetricsForTesting(
      itemCount: 3,
      maxWidth: 1200,
      maxHeight: 650,
    );
    final small = debugCallGridMetricsForTesting(
      itemCount: 3,
      maxWidth: 480,
      maxHeight: 360,
    );

    expect(small.width, lessThan(large.width));
    expect(small.height, lessThan(large.height));
    expect(small.width / small.height, closeTo(16 / 9, 0.00001));
  });

  test('mobile camera frames are square and screenshare is widescreen', () {
    expect(
      debugCallTileAspectRatioForTesting(mobile: true, isScreenshare: false),
      1,
    );
    expect(
      debugCallTileAspectRatioForTesting(mobile: true, isScreenshare: true),
      16 / 9,
    );
    expect(
      debugCallTileAspectRatioForTesting(mobile: false, isScreenshare: false),
      16 / 9,
    );
  });
}
