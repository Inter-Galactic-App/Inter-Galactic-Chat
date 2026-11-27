import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_role.dart';

void main() {
  test('MatrixRole equality uses exact power level', () {
    expect(MatrixRole(25), isNot(MatrixRole(0)));
    expect(MatrixRole(25), MatrixRole(25));
    expect(MatrixRole(100), isNot(MatrixRole(50)));
  });
}
