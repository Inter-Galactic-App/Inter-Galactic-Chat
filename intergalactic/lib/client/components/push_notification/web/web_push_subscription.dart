class WebPushSubscriptionData {
  const WebPushSubscriptionData({
    required this.endpoint,
    required this.authKey,
    required this.p256dhKey,
  });

  final String endpoint;
  final String authKey;
  final String p256dhKey;

  factory WebPushSubscriptionData.fromJson(Map<String, dynamic> json) {
    final keys = Map<String, dynamic>.from(
      json["keys"] as Map<String, dynamic>? ?? const {},
    );

    return WebPushSubscriptionData(
      endpoint: json["endpoint"] as String,
      authKey: (keys["auth"] ?? json["auth"]) as String,
      p256dhKey: (keys["p256dh"] ?? json["p256dh"]) as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "endpoint": endpoint,
      "keys": {
        "auth": authKey,
        "p256dh": p256dhKey,
      },
    };
  }

  Map<String, dynamic> toRegistrationData() {
    return {
      "type": "webpush",
      "subscription": toJson(),
    };
  }
}