import 'package:intergalactic/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:dbus/dbus.dart';

// for testing:
// gdbus call --session --dest chat.intergalactic.app --object-path /chat/intergalactic/app/Shortcuts --method chat.intergalactic.app.Shortcuts.unmute
// gdbus call --session --dest chat.intergalactic.app --object-path /chat/intergalactic/app/Shortcuts --method chat.intergalactic.app.Shortcuts.mute

class SystemWideShortcutsLinux {
  static Future<void> init() async {
    await initDbus();
  }

  static Future<void> initDbus() async {
    var client = DBusClient.session();
    await client.requestName('chat.intergalactic.app');
    await client.registerObject(TestObject());
  }
}

class TestObject extends DBusObject {
  TestObject() : super(DBusObjectPath('/chat/intergalactic/app/Shortcuts'));

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'chat.intergalactic.app.shortcuts' && name == 'Version') {
      return DBusGetPropertyResponse(DBusString('1.0'));
    } else {
      return DBusMethodErrorResponse.unknownProperty();
    }
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    print("Handling dbus message call!");
    print(methodCall.toString());
    if (methodCall.interface != "chat.intergalactic.app.Shortcuts") {
      return DBusMethodErrorResponse.unknownInterface();
    }

    var shortcut = SystemWideShortcuts.registeredShortcuts[methodCall.name];

    if (shortcut != null) {
      shortcut.callback();
    }

    return DBusMethodSuccessResponse();
  }
}
