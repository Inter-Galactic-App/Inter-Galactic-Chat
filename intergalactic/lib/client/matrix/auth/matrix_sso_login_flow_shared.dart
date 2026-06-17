import 'package:intergalactic/client/auth.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/custom_uri.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:universal_html/html.dart' as html;

class MatrixSSOLoginFlow implements SsoLoginFlow {
  @override
  String? id;
  String? brand;

  @override
  ImageProvider<Object>? icon;

  @override
  String name;

  MatrixSSOLoginFlow({this.id, required this.name, this.icon, this.brand});

  factory MatrixSSOLoginFlow.fromJson(
          MatrixClient client, Map<String, dynamic> json) =>
      MatrixSSOLoginFlow(
        id: json['id'],
        name: json['name'],
        icon: json['icon'] != null
            ? getLoginFlowImage(
                Uri.parse(json['icon']),
                client,
              )
            : null,
        brand: json['brand'],
      );

  static NetworkImage getLoginFlowImage(Uri mxc, MatrixClient client) {
    final path =
        '_matrix/media/v3/thumbnail/${Uri.encodeComponent(mxc.authority)}/${Uri.encodeComponent(mxc.pathSegments.first)}';

    final server = client.getMatrixClient().baseUri!;
    final request =
        server.replace(path: path, query: "width=96&height=96&method=crop");
    return NetworkImage(request.toString());
  }

  @override
  Future<LoginResult> submit(Client client) async {
    if (client is! MatrixClient) {
      return LoginResultError(
          "Attemted to login with the wrong type of client");
    }

    try {
      final mx = client.getMatrixClient();

      var redirectUrl = SsoLoginUri().toString();

      if (PlatformUtils.isWeb) {
        redirectUrl = Uri.parse(html.window.location.href)
            .resolve("auth.html")
            .toString();
      }

      var callbackScheme = Uri.parse(redirectUrl).scheme;

      if (PlatformUtils.isLinux || PlatformUtils.isWindows) {
        redirectUrl = "http://localhost:3001/login";
        callbackScheme = "http://localhost:3001";
      }

      final url = mx.homeserver!.replace(
        path:
            '/_matrix/client/v3/login/sso/redirect${id == null ? '' : '/$id'}',
        queryParameters: {'redirectUrl': redirectUrl},
      );

      final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: callbackScheme,
        options: FlutterWebAuth2Options(
          useWebview: false,
        ),
      );

      final token = Uri.parse(result).queryParameters['loginToken'];
      if (token?.isEmpty ?? false) {
        return LoginResultFailed();
      }

      final login = await mx.login(
        matrix.LoginType.mLoginToken,
        token: token,
        deviceId: client.resolveStoredDeviceIdForCurrentHomeserver(),
        initialDeviceDisplayName: BuildConfig.matrixDeviceDisplayName,
      );

      if (login.accessToken.isNotEmpty) {
        return LoginResultSuccess();
      } else {
        return LoginResultFailed();
      }
    } catch (e, t) {
      Log.onError(e, t);
      if (e is PlatformException && e.code == "CANCELED") {
        return LoginResultCancelled();
      }
      return LoginResultError(e.toString());
    }
  }
}
