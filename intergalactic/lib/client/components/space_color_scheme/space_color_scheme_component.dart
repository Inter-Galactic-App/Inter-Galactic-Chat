import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:flutter/material.dart';

abstract class SpaceColorSchemeComponent<R extends Client, T extends Space>
    implements SpaceComponent<R, T> {
  ColorScheme get scheme;
}
