import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log_redactor.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FatalErrorPage extends StatelessWidget {
  const FatalErrorPage(this.error, this.trace, {super.key});
  final Object error;
  final StackTrace trace;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Material(
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Text("Something went wrong!"),
                Text(error.toString()),
                const Text(
                    "Sorry, there was a fatal error and ${BuildConfig.app} was unable to start. Copy the redacted details and include them in Help > Report a Bug after restarting, or send them to Inter Galactic support."),
                const Text(
                    "The copied details are redacted, but review them before sending."),
                ElevatedButton(
                    onPressed: onCopyButtonPressed,
                    child: const Text("Copy to clipboard")),
                Text(trace.toString())
              ],
            ),
          ),
        ),
      ),
    );
  }

  void onCopyButtonPressed() async {
    var data = await getErrorData();
    Clipboard.setData(ClipboardData(text: data));
  }

  Future<String> getErrorData() async {
    var deviceInfo = await DeviceInfoPlugin().deviceInfo;
    return LogRedactor.redactForBugReport("""
Fatal Error Occurred!
$error

<details open>
<summary>Device Information</summary>
<br>

**Device**
App: ${BuildConfig.app} (fork of ${BuildConfig.originalApp} by ${BuildConfig.originalCreator})
Platform: `${BuildConfig.PLATFORM}`
Version: `${BuildConfig.VERSION_TAG}`
Git Hash: `${BuildConfig.GIT_HASH}`
Detail: `${BuildConfig.buildDetailDisplay}`


**System Info**
${deviceInfo.data["name"] is String ? "Name: `${deviceInfo.data["name"]}`" : ""}
${deviceInfo.data["version"] is String ? "Version: `${deviceInfo.data["version"]}`" : ""}
${deviceInfo.data["product"] is String ? "Product: `${deviceInfo.data["product"]}`" : ""}
</details>

<details open>
<summary>Stack Trace</summary>
<br>

```
${trace.toString()}
```

</details>
""");
  }
}
