import 'package:intergalactic/config/preferences/preference.dart';

class IntPreference extends Preference<int> {
  IntPreference(super.key, {required super.defaultValue})
      : super(
          getter: () => Preference.preferences?.getInt(key),
          setter: (v) async {
            await Preference.preferences?.setInt(key, v);
          },
        );
}
