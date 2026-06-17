import 'package:receive_intent/receive_intent.dart';

Future<dynamic> getInitialAppIntent() {
  return ReceiveIntent.getInitialIntent();
}

Stream<dynamic> get appReceivedIntentStream {
  return ReceiveIntent.receivedIntentStream;
}
