import 'dart:async';

import 'package:intergalactic/client/auth.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/matrix_password_change_dialog.dart';
import 'package:intergalactic/ui/pages/login/account_recovery_enrollment_prompt.dart';
import 'package:intergalactic/ui/pages/login/forgot_password_dialog.dart';
import 'package:intergalactic/ui/pages/login/post_login_matrix_recovery_dialog.dart';
import 'package:intergalactic/ui/pages/login/login_page_view.dart';
import 'package:intergalactic/utils/debounce.dart';
import 'package:intergalactic/utils/rng.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.onSuccess, this.canNavigateBack = false});
  final bool canNavigateBack;
  final Function(Client loggedInClient)? onSuccess;

  @override
  State<LoginPage> createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  String get messageLoginFailed => Intl.message(
        "Login Failed...",
        name: "messageLoginFailed",
        desc: "Generic text to show that an attempted login has failed",
      );

  String get messageAlreadyLoggedIn => Intl.message(
        "You have already logged in to this account",
        name: "messageAlreadyLoggedIn",
        desc:
            "An error message displayed when the user attempts to add an account which has already been logged in to on this device",
      );

  String get messageInvalidUsernameOrPassword => Intl.message(
      "Invalid username or password",
      name: "messageInvalidUsernameOrPassword",
      desc:
          "An error message displayed when the user attempts to log into an account using the wrong username/password combination");

  String get messageRecoveryNotRestoredTitle => Intl.message(
        'Encrypted history not restored',
        name: 'messageRecoveryNotRestoredTitle',
        desc:
            'Title for the warning shown when login succeeds but encrypted history recovery fails.',
      );

  String get messageRecoveryNotRestoredBody => Intl.message(
        'Login succeeded, but secure history recovery failed. You can retry recovery from settings.',
        name: 'messageRecoveryNotRestoredBody',
        desc:
            'Body for the warning shown when login succeeds but encrypted history recovery fails.',
      );

  StreamSubscription? progressSubscription;
  StreamSubscription? settingsSubscription;
  double? progress;
  List<LoginFlow>? loginFlows;
  Client? loginClient;
  String? _lastPasswordLoginSecret;

  final Debouncer homeserverUpdateDebouncer = Debouncer(
    delay: const Duration(seconds: 1),
  );

  bool loadingServerInfo = false;
  bool isServerValid = false;
  bool isLoggingIn = false;
  bool registrationTokenRequired = false;
  String? registrationTokenSession;
  String? registrationTokenMessage;

  @override
  void initState() {
    var internalId = RandomUtils.getRandomString(20);
    MatrixClient.create(internalId).then((client) {
      loginClient = client;

      progressSubscription = loginClient!.connectionStatusChanged.stream.listen(
        onLoginProgressChanged,
      );
    });
    settingsSubscription = preferences.onSettingChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    progressSubscription?.cancel();
    settingsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LoginPageView(
      canNavigateBack: widget.canNavigateBack,
      progress: progress,
      updateHomeserver: (value) {
        setState(() {
          loginFlows = null;
          isServerValid = false;
          loadingServerInfo = true;
          registrationTokenRequired = false;
          registrationTokenSession = null;
          registrationTokenMessage = null;
        });
        homeserverUpdateDebouncer.run(() => updateHomeserver(value));
      },
      flows: loginFlows,
      doSsoLogin: doSsoLogin,
      doPasswordLogin: doPasswordLogin,
      doRegisterAccount: BuildConfig.MOBILE ? null : doRegisterAccount,
      doDemoLogin:
          preferences.offlineDemoLoginEnabled.value ? doDemoLogin : null,
      showForgotPassword: showForgotPassword,
      registrationTokenRequired: registrationTokenRequired,
      registrationTokenMessage: registrationTokenMessage,
      isLoggingIn: isLoggingIn,
      loadingServerInfo: loadingServerInfo,
      hasSsoSupport: loginFlows?.whereType<SsoLoginFlow>().isNotEmpty == true,
      hasPasswordSupport:
          loginFlows?.whereType<PasswordLoginFlow>().isNotEmpty == true,
      isServerValid: isServerValid,
    );
  }

  Future<void> doLogin(
    Future<LoginResult> Function() login,
  ) async {
    if (loginClient == null) return;
    if (isServerValid == false) {
      return;
    }

    setState(() {
      isLoggingIn = true;
    });

    LoginResult? result;

    try {
      result = await login();
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Login flow threw before returning a LoginResult',
      );
      result = LoginResultFailed();
    }

    if (!(result is LoginResultSuccess) && mounted) {
      setState(() {
        isLoggingIn = false;
      });
    }

    String? message = switch (result) {
      LoginResultSuccess _ => null,
      LoginResultError e => e.errorMessage,
      LoginResultCancelled _ => "Login Cancelled",
      LoginResultAlreadyLoggedIn _ => messageAlreadyLoggedIn,
      LoginResultFailed _ => messageLoginFailed,
      LoginResult() => messageLoginFailed,
    };

    if (message != null) {
      if (mounted) {
        AdaptiveDialog.show(
          context,
          title: "Login failed",
          builder: (_) => tiamat.Text(
            message,
          ),
        );
      }
    }

    if (result is LoginResultSuccess) {
      final resetReady = await _runForcedPasswordResetIfRequired(
        currentPassword: _lastPasswordLoginSecret,
      );
      if (!resetReady) {
        return;
      }

      try {
        await _runPostLoginRecoveryIfNeeded();
      } catch (error, trace) {
        if (MatrixClient.responseRequiresPasswordReset(error)) {
          final resetReady = await _runForcedPasswordResetIfRequired(
            currentPassword: _lastPasswordLoginSecret,
            assumeRequired: true,
          );
          if (!resetReady) {
            return;
          }

          try {
            await _runPostLoginRecoveryIfNeeded();
          } catch (retryError, retryTrace) {
            Log.onError(
              retryError,
              retryTrace,
              content:
                  'Post-login recovery flow failed after forced password reset completed',
            );
            if (mounted) {
              await AdaptiveDialog.show(
                context,
                title: messageRecoveryNotRestoredTitle,
                builder: (_) => tiamat.Text(
                  messageRecoveryNotRestoredBody,
                ),
              );
            }
          }
        } else {
          Log.onError(
            error,
            trace,
            content:
                'Post-login recovery flow failed after the session was already accepted',
          );
          if (mounted) {
            await AdaptiveDialog.show(
              context,
              title: messageRecoveryNotRestoredTitle,
              builder: (_) => tiamat.Text(
                messageRecoveryNotRestoredBody,
              ),
            );
          }
        }
      }
      await _runAccountRecoveryEnrollmentPromptIfNeeded();
      clientManager?.addClient(loginClient!);
      widget.onSuccess?.call(loginClient!);
    }
  }

  Future<void> doSsoLogin(SsoLoginFlow flow) async {
    if (loginClient == null) return;
    _lastPasswordLoginSecret = null;
    await doLogin(() => loginClient!.executeLoginFlow(flow));
  }

  Future<void> doPasswordLogin(
    PasswordLoginFlow flow,
    String username,
    String password,
  ) async {
    if (loginClient == null) return;
    flow.username = username;
    flow.password = password;

    _lastPasswordLoginSecret = password;
    try {
      await doLogin(() => loginClient!.executeLoginFlow(flow));
    } finally {
      _lastPasswordLoginSecret = null;
    }
  }

  Future<void> doRegisterAccount(
    String username,
    String password,
    String registrationToken,
  ) async {
    if (loginClient == null) return;
    if (isServerValid == false) return;

    setState(() => isLoggingIn = true);

    LoginResult? result;
    try {
      result = await loginClient!.registerAccount(
        username: username,
        password: password,
        registrationToken: registrationToken.isEmpty ? null : registrationToken,
        registrationSession: registrationTokenSession,
      );
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Registration flow threw before returning a LoginResult',
      );
      result = LoginResultFailed();
    }

    if (result is! LoginResultSuccess && mounted) {
      setState(() => isLoggingIn = false);
    }

    final tokenRequiredResult = result;
    if (tokenRequiredResult is LoginResultRegistrationTokenRequired) {
      if (mounted) {
        setState(() {
          registrationTokenRequired = true;
          registrationTokenSession = tokenRequiredResult.session;
          registrationTokenMessage = tokenRequiredResult.message;
        });
      }
      return;
    }

    final message = switch (result) {
      LoginResultSuccess _ => null,
      LoginResultError e => e.errorMessage,
      LoginResultAlreadyLoggedIn _ => messageAlreadyLoggedIn,
      LoginResultFailed _ => 'Registration failed.',
      _ => 'Registration failed.',
    };

    if (message != null && mounted) {
      AdaptiveDialog.show(
        context,
        title: 'Registration failed',
        builder: (_) => tiamat.Text(message),
      );
    }

    if (result is LoginResultSuccess) {
      registrationTokenRequired = false;
      registrationTokenSession = null;
      registrationTokenMessage = null;
      await _runAccountRecoveryEnrollmentPromptIfNeeded(force: true);
      clientManager?.addClient(loginClient!);
      widget.onSuccess?.call(loginClient!);
    }
  }

  Future<void> showForgotPassword(String homeserverInput) async {
    if (mounted) {
      await AdaptiveDialog.show<bool>(
        context,
        title: 'Forgot password?',
        scrollable: true,
        builder: (_) => ForgotPasswordDialog(
          homeserverInput: homeserverInput,
        ),
      );
    }
  }

  Future<void> doDemoLogin() async {
    if (isLoggingIn) return;
    setState(() {
      isLoggingIn = true;
    });

    try {
      final demoClient = DemoClient.createOfflineDemo();
      await demoClient.init(false);
      clientManager?.addClient(demoClient);
      widget.onSuccess?.call(demoClient);
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: 'Demo login failed');
      if (mounted) {
        AdaptiveDialog.show(
          context,
          title: messageLoginFailed,
          builder: (_) => tiamat.Text(messageLoginFailed),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoggingIn = false;
        });
      }
    }
  }

  Future<void> _runPostLoginRecoveryIfNeeded() async {
    final client = loginClient;
    if (client is! MatrixClient || !mounted) {
      return;
    }

    await AdaptiveDialog.show<bool>(
      context,
      title: 'Restore encrypted history',
      dismissible: false,
      scrollable: true,
      builder: (_) => PostLoginMatrixRecoveryDialog(
        client: client,
      ),
    );
  }

  Future<void> _runAccountRecoveryEnrollmentPromptIfNeeded({
    bool force = false,
  }) async {
    final client = loginClient;
    if (client is! MatrixClient || !mounted) {
      return;
    }

    if (mounted) {
      setState(() {
        isLoggingIn = false;
      });
    }

    await AccountRecoveryEnrollmentPrompt.maybeShow(
      context,
      client: client,
      force: force,
    );
  }

  Future<bool> _runForcedPasswordResetIfRequired({
    String? currentPassword,
    bool assumeRequired = false,
  }) async {
    final client = loginClient;
    if (client is! MatrixClient || !mounted) {
      return true;
    }

    MatrixPasswordResetStatus status = const MatrixPasswordResetStatus(
      supported: true,
      required: true,
    );

    if (!assumeRequired) {
      try {
        status = await client.getPasswordResetStatus();
      } catch (error, trace) {
        if (MatrixClient.responseRequiresPasswordReset(error)) {
          status = const MatrixPasswordResetStatus(
            supported: true,
            required: true,
          );
        } else {
          Log.onError(
            error,
            trace,
            content:
                'Failed to check Matrix forced password reset status after login',
          );
          if (mounted) {
            await AdaptiveDialog.show(
              context,
              title: 'Password reset check failed',
              dismissible: false,
              builder: (_) => tiamat.Text(
                'Login succeeded, but Inter Galactic could not check whether this account needs a password reset. Please sign in again.',
              ),
            );
          }
          await _signOutAndReplaceLoginClient();
          return false;
        }
      }
    }

    if (!status.required) {
      return true;
    }

    final result = await AdaptiveDialog.show<MatrixPasswordChangeResult>(
      context,
      title: 'Change your password',
      dismissible: false,
      scrollable: true,
      builder: (_) => MatrixPasswordChangeDialog(
        client: client,
        forced: true,
        initialCurrentPassword: currentPassword,
      ),
    );

    if (result == MatrixPasswordChangeResult.changed) {
      return true;
    }

    await _signOutAndReplaceLoginClient();
    return false;
  }

  Future<void> _signOutAndReplaceLoginClient() async {
    final oldClient = loginClient;
    Uri? homeserver;

    if (oldClient is MatrixClient) {
      homeserver = oldClient.getMatrixClient().homeserver ??
          oldClient.getMatrixClient().baseUri;
    }

    loginClient = null;
    await progressSubscription?.cancel();
    progressSubscription = null;

    if (oldClient != null) {
      try {
        await oldClient.logout();
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content: 'Failed to log out Matrix client after password reset abort',
        );
      }

      try {
        await oldClient.close();
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content: 'Failed to close Matrix client after password reset abort',
        );
      }
    }

    late final MatrixClient replacementClient;
    try {
      replacementClient = await MatrixClient.create(
        RandomUtils.getRandomString(20),
      );
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content:
            'Failed to create replacement Matrix client after password reset',
      );
      if (mounted) {
        setState(() {
          progress = null;
          isLoggingIn = false;
          loadingServerInfo = false;
          isServerValid = false;
          loginFlows = null;
        });
        await AdaptiveDialog.show(
          context,
          title: messageLoginFailed,
          builder: (_) => tiamat.Text(messageLoginFailed),
        );
      }
      return;
    }

    if (!mounted) {
      await replacementClient.close();
      return;
    }

    loginClient = replacementClient;
    progressSubscription = loginClient!.connectionStatusChanged.stream.listen(
      onLoginProgressChanged,
    );

    var nextServerValid = false;
    List<LoginFlow>? nextLoginFlows;

    if (homeserver != null) {
      try {
        final serverInfo = await loginClient!.setHomeserver(homeserver);
        nextServerValid = serverInfo.$1;
        nextLoginFlows = serverInfo.$2;
      } catch (error, trace) {
        Log.onError(
          error,
          trace,
          content:
              'Failed to restore homeserver selection after password reset abort',
        );
      }
    }

    if (mounted) {
      setState(() {
        progress = null;
        isLoggingIn = false;
        loadingServerInfo = false;
        isServerValid = nextServerValid;
        loginFlows = nextLoginFlows;
      });
    }
  }

  void onLoginProgressChanged(ClientConnectionStatusUpdate event) {
    if (!mounted) return;
    setState(() {
      progress = event.progress;
    });
  }

  Future<void> updateHomeserver(String input) async {
    if (loginClient == null) return;

    setState(() {
      loginFlows = null;
      loadingServerInfo = true;
      isServerValid = false;
    });

    var uri = Uri.https(input);
    var result = await loginClient!.setHomeserver(uri);

    setState(() {
      loadingServerInfo = false;
      isServerValid = result.$1;
      loginFlows = result.$2;
    });
  }
}
