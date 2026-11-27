import 'package:intergalactic/client/auth.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/global_config.dart';
import 'package:intergalactic/utils/app_icon/app_icon_utils.dart';
import 'package:intergalactic/ui/atoms/shader/constellation_background.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/app_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/about/settings_category_about.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/circle_button.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class LoginPageView extends StatefulWidget {
  const LoginPageView({
    super.key,
    this.canNavigateBack = false,
    this.progress,
    this.flows,
    this.contextNotice,
    this.mobileAccountCreationNotice,
    required this.isLoggingIn,
    this.homeserverChecked,
    this.doSsoLogin,
    this.doPasswordLogin,
    this.doRegisterAccount,
    this.doDemoLogin,
    this.showForgotPassword,
    this.registrationTokenRequired = false,
    this.registrationTokenMessage,
    this.loadingServerInfo = false,
    this.isServerValid = false,
    this.hasSsoSupport = false,
    this.hasPasswordSupport = false,
    this.updateHomeserver,
  });
  final bool canNavigateBack;
  final bool isLoggingIn;
  final bool? homeserverChecked;
  final double? progress;
  final List<LoginFlow>? flows;
  final String? contextNotice;

  /// Guidance shown on mobile, where account creation is gated. Native mobile
  /// builds cannot open the browser to register (an account on an independent
  /// homeserver cannot be reliably deleted, which Apple's guidelines require),
  /// so this tells users where to create an account instead. Null on platforms
  /// where registration happens in-app.
  final String? mobileAccountCreationNotice;

  /// Default copy for [mobileAccountCreationNotice]. Kept here as the single
  /// source of truth so the gating in login_page_shared and the widget test
  /// reference the same text.
  static String get defaultMobileAccountCreationNotice => Intl.message(
    'Account creation is not available in the mobile app. To make a new '
    'account, go to chat.ourgalaxy.space in your browser or use the Inter '
    'Galactic desktop app, then come back and sign in here.',
    name: 'defaultMobileAccountCreationNotice',
    desc:
        'Notice on the mobile login screen telling the user that accounts must '
        'be created on the web or in the desktop app, since mobile builds gate '
        'registration',
  );

  final bool loadingServerInfo;
  final bool isServerValid;
  final bool hasSsoSupport;
  final bool hasPasswordSupport;
  final bool registrationTokenRequired;
  final String? registrationTokenMessage;
  final Future<void> Function(SsoLoginFlow flow)? doSsoLogin;
  final Future<void> Function(
    PasswordLoginFlow flow,
    String username,
    String password,
  )?
  doPasswordLogin;

  /// Called when the user submits a registration form.
  /// Args: username, password, registrationToken (empty until requested).
  final Future<void> Function(
    String username,
    String password,
    String registrationToken,
  )?
  doRegisterAccount;
  final Future<void> Function()? doDemoLogin;
  final Future<void> Function(String homeserver)? showForgotPassword;

  final Function(String)? updateHomeserver;

  @override
  State<LoginPageView> createState() => _LoginPageViewState();
}

class _LoginPageViewState extends State<LoginPageView> {
  final TextEditingController _homeserverTextField = TextEditingController(
    text: GlobalConfig.defaultHomeserver,
  );
  final TextEditingController _usernameTextField = TextEditingController();
  final TextEditingController _passwordTextField = TextEditingController();
  bool _showPassword = false;

  // ── Registration mode ─────────────────────────────────────────────────────
  bool _registerMode = false;
  final TextEditingController _regUsernameController = TextEditingController();
  final TextEditingController _regPasswordController = TextEditingController();
  final TextEditingController _regConfirmController = TextEditingController();
  final TextEditingController _regTokenController = TextEditingController();

  String get promptHomeserver => Intl.message(
    "Homeserver",
    name: "promptHomeserver",
    desc: "Placeholder text for homeserver field on login form",
  );

  String get promptUsername => Intl.message(
    "Username",
    name: "promptUsername",
    desc: "Placeholder text for username field on login form",
  );

  String get promptPassword => Intl.message(
    "Password",
    name: "promptPassword",
    desc: "Placeholder text for password field on login form",
  );

  String get promptShowPassword => Intl.message(
    "Show password",
    name: "promptShowPassword",
    desc: "Tooltip for revealing the login password text",
  );

  String get promptHidePassword => Intl.message(
    "Hide password",
    name: "promptHidePassword",
    desc: "Tooltip for hiding the login password text",
  );

  String get promptSubmitLogin => Intl.message(
    "Login",
    name: "promptSubmitLogin",
    desc: "Prompt to submit the username and password, and attempt to login",
  );

  @override
  void initState() {
    if (_homeserverTextField.text != "") {
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        _onHomeserverTextUpdated();
      });
    }
    super.initState();
  }

  @override
  void dispose() {
    _homeserverTextField.dispose();
    _usernameTextField.dispose();
    _passwordTextField.dispose();
    _regUsernameController.dispose();
    _regPasswordController.dispose();
    _regConfirmController.dispose();
    _regTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useOverlayAbout = _useOverlayAbout(context);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          _background(context),
          SafeArea(
            child: Stack(
              children: [
                Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Material(
                    color: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Stack(
                        children: [
                          loginField(context, useOverlayAbout: useOverlayAbout),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.canNavigateBack)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: CircleButton(
                      radius: 15,
                      minimumSize: 40,
                      icon: Icons.close_rounded,
                      semanticLabel: promptCloseSignIn,
                      tooltip: promptCloseSignIn,
                      // Top-right of the page; `up` would run off the top edge.
                      tooltipDirection: AxisDirection.down,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                0,
                12,
                widget.canNavigateBack ? 60 : 12,
                0,
              ),
              child: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  height: 30,
                  width: 30,
                  child: tiamat.IconButton(
                    icon: Icons.settings,
                    onPressed: () => SettingsNavigation.show(
                      context,
                      const AppSettingsPage(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (useOverlayAbout)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  0,
                  0,
                  0,
                  MediaQuery.of(context).padding.bottom,
                ),
                child: SettingsCategoryAbout.info(context),
              ),
            ),
        ],
      ),
    );
  }

  bool _useOverlayAbout(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width >= 700 &&
        mediaQuery.size.height >= 780 &&
        mediaQuery.viewInsets.bottom == 0;
  }

  Widget _background(BuildContext context) {
    if (!BuildConfig.WEB) {
      return const ConstellationBackground();
    }

    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(scheme.surface, scheme.primaryContainer, 0.28)!,
            Color.lerp(scheme.surface, scheme.secondaryContainer, 0.18)!,
            scheme.surface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -140,
            left: -120,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.secondary.withValues(alpha: 0.06),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget loginField(BuildContext context, {required bool useOverlayAbout}) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding =
        mediaQuery.padding.bottom +
        mediaQuery.viewInsets.bottom +
        (useOverlayAbout ? 96 : 24);

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final minHeight = (constraints.maxHeight - bottomPadding - 24)
                .clamp(0.0, double.infinity);

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(0, 24, 0, bottomPadding),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 50,
                            color: Theme.of(context).shadowColor.withAlpha(50),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: Stack(
                          children: [
                            IgnorePointer(
                              ignoring: widget.isLoggingIn,
                              child: AnimatedOpacity(
                                opacity: widget.isLoggingIn ? 0.5 : 1.0,
                                duration: Durations.short2,
                                child: loginInputs(
                                  context,
                                  useOverlayAbout: useOverlayAbout,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (widget.isLoggingIn)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget loginInputs(BuildContext context, {required bool useOverlayAbout}) {
    var ssoFlows = widget.flows?.whereType<SsoLoginFlow>().toList();
    SsoLoginFlow? defaultSso;
    if (ssoFlows != null) {
      defaultSso = ssoFlows.where((e) => e.id == null).firstOrNull;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              appIcon(context),
              const SizedBox(height: 12),
              appName(),
              const SizedBox(height: 4),
              Text(
                BuildConfig.buildFingerprintDisplay,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        homeserverEntry(),
        const SizedBox(height: 16),
        if (widget.contextNotice?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: tiamat.Text.labelLow(widget.contextNotice!),
          ),
        if (widget.mobileAccountCreationNotice?.isNotEmpty == true)
          AccountCreationNoticeCard(
            message: widget.mobileAccountCreationNotice!,
          ),
        if (widget.doDemoLogin != null) ...[
          SizedBox(
            width: double.infinity,
            height: 50,
            child: tiamat.Button.secondary(
              text: 'Continue in Offline Demo',
              onTap: widget.isLoggingIn ? null : widget.doDemoLogin,
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: tiamat.Text.labelLow(
              'Offline demo mode uses local sample data and does not connect to a homeserver.',
              softwrap: true,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 88, height: 10, child: tiamat.Seperator()),
              tiamat.Text.labelLow(CommonStrings.labelOr),
              const SizedBox(width: 88, height: 10, child: tiamat.Seperator()),
            ],
          ),
          const SizedBox(height: 16),
        ],
        // ── Mode toggle ─────────────────────────────────────────────────────
        if (widget.doRegisterAccount != null && widget.isServerValid)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => setState(() => _registerMode = false),
                  child: Text(
                    'Sign In',
                    style: TextStyle(
                      fontWeight: _registerMode
                          ? FontWeight.normal
                          : FontWeight.bold,
                      decoration: _registerMode
                          ? null
                          : TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                TextButton(
                  onPressed: () => setState(() => _registerMode = true),
                  child: Text(
                    'Create Account',
                    style: TextStyle(
                      fontWeight: _registerMode
                          ? FontWeight.bold
                          : FontWeight.normal,
                      decoration: _registerMode
                          ? TextDecoration.underline
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // ── Register form ────────────────────────────────────────────────────
        if (_registerMode && widget.doRegisterAccount != null) ...[
          registerInputs(context),
        ] else ...[
          // ── Login form ───────────────────────────────────────────────────
          if (widget.hasPasswordSupport) usenamePasswordLoginInputs(),
          if (widget.hasSsoSupport)
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.hasPasswordSupport)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 100,
                            height: 10,
                            child: tiamat.Seperator(),
                          ),
                          tiamat.Text.labelLow(CommonStrings.labelOr),
                          const SizedBox(
                            width: 100,
                            height: 10,
                            child: tiamat.Seperator(),
                          ),
                        ],
                      ),
                    ),
                  if (defaultSso != null)
                    tiamat.Button.secondary(
                      text: "Login with " + defaultSso.name,
                      onTap: () => {widget.doSsoLogin?.call(defaultSso!)},
                    ),
                  if (ssoFlows != null)
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 10,
                          children: ssoFlows
                              .whereType<SsoLoginFlow>()
                              .where((e) => e != defaultSso)
                              .map(
                                (e) => ElevatedButton.icon(
                                  icon: SizedBox(
                                    width: e.icon == null ? 0 : 32,
                                    height: 48,
                                    child: e.icon != null
                                        ? Image(image: e.icon!)
                                        : null,
                                  ),
                                  label: Text("Continue with ${e.name}"),
                                  onPressed: () => widget.doSsoLogin?.call(e),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
        SizedBox(
          height: 15,
          child: Center(
            child: SizedBox(
              height: 5,
              child: widget.progress == null
                  ? null
                  : LinearProgressIndicator(value: widget.progress),
            ),
          ),
        ),
        if (!useOverlayAbout) ...[
          const SizedBox(height: 16),
          _buildInlineAbout(context),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildInlineAbout(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    if (!compact) {
      return SettingsCategoryAbout.info(context);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tiamat.Text.labelLow(BuildConfig.buildFingerprintDisplay),
        const SizedBox(height: 8),
        tiamat.Button.secondary(
          text: 'About This Fork',
          onTap: () {
            AdaptiveDialog.show(
              context,
              title: 'About Inter Galactic',
              scrollable: true,
              builder: (_) => SettingsCategoryAbout.info(context),
            );
          },
        ),
      ],
    );
  }

  String get promptCloseSignIn => Intl.message(
    "Close sign in",
    name: "promptCloseSignIn",
    desc: "Tooltip and accessibility label for closing the sign-in page",
  );

  /// Registration form shown when [_registerMode] is true.
  Widget registerInputs(BuildContext context) {
    final allFilled =
        _regUsernameController.text.trim().isNotEmpty &&
        _regPasswordController.text.isNotEmpty &&
        _regPasswordController.text == _regConfirmController.text &&
        (!widget.registrationTokenRequired ||
            _regTokenController.text.trim().isNotEmpty);

    final passwordMismatch =
        _regConfirmController.text.isNotEmpty &&
        _regPasswordController.text != _regConfirmController.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Username
        TextField(
          autocorrect: false,
          controller: _regUsernameController,
          readOnly: widget.isLoggingIn,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[ ]'))],
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Username',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        // Password
        TextField(
          autocorrect: false,
          controller: _regPasswordController,
          obscureText: true,
          readOnly: widget.isLoggingIn,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Password',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        // Confirm password
        TextField(
          autocorrect: false,
          controller: _regConfirmController,
          obscureText: true,
          readOnly: widget.isLoggingIn,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Confirm Password',
            errorText: passwordMismatch ? 'Passwords do not match' : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (widget.registrationTokenRequired) ...[
          tiamat.Text.labelLow(
            widget.registrationTokenMessage ??
                'This server requires an invite code to create an account.',
          ),
          const SizedBox(height: 8),
          TextField(
            autocorrect: false,
            enableSuggestions: false,
            controller: _regTokenController,
            readOnly: widget.isLoggingIn,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Invite Code',
              helperText:
                  'Enter the code from the server administrator, then try again.',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
        ],
        // Submit
        SizedBox(
          width: double.infinity,
          height: 50,
          child: tiamat.Button(
            text: widget.registrationTokenRequired
                ? 'Submit Invite Code'
                : 'Create Account',
            onTap: allFilled
                ? () => widget.doRegisterAccount?.call(
                    _regUsernameController.text.trim(),
                    _regPasswordController.text,
                    _regTokenController.text.trim(),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Column usenamePasswordLoginInputs() {
    return Column(
      children: [
        usernameEntry(),
        const SizedBox(height: 16),
        passwordEntry(),
        const SizedBox(height: 16),
        loginButton(),
        if (widget.showForgotPassword != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.isLoggingIn
                  ? null
                  : () => widget.showForgotPassword?.call(
                      _homeserverTextField.text,
                    ),
              child: const Text('Forgot password?'),
            ),
          ),
        ],
      ],
    );
  }

  Text appName() {
    return const Text(
      BuildConfig.app,
      style: TextStyle(fontFamily: 'Jellee', fontSize: 30),
    );
  }

  SizedBox loginButton() {
    var flow = widget.flows?.whereType<PasswordLoginFlow>().firstOrNull;

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: tiamat.Button(
        text: promptSubmitLogin,
        onTap: flow != null
            ? () => widget.doPasswordLogin?.call(
                flow,
                _usernameTextField.text,
                _passwordTextField.text,
              )
            : null,
      ),
    );
  }

  TextField passwordEntry() {
    final passwordVisibilityLabel = _showPassword
        ? promptHidePassword
        : promptShowPassword;

    return TextField(
      autocorrect: false,
      enableSuggestions: false,
      controller: _passwordTextField,
      obscureText: !_showPassword,
      readOnly: widget.isLoggingIn,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: promptPassword,
        suffixIcon: IconButton(
          tooltip: passwordVisibilityLabel,
          icon: Icon(
            _showPassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          onPressed: () {
            setState(() {
              _showPassword = !_showPassword;
            });
          },
        ),
      ),
    );
  }

  TextField usernameEntry() {
    return TextField(
      autocorrect: false,
      controller: _usernameTextField,
      readOnly: widget.isLoggingIn,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp("[ ]"))],
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: promptUsername,
      ),
    );
  }

  Widget homeserverEntry() {
    return TextField(
      autocorrect: false,
      controller: _homeserverTextField,
      readOnly: widget.isLoggingIn,
      onChanged: widget.updateHomeserver,
      keyboardType: TextInputType.url,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp("[ ]"))],
      decoration: InputDecoration(
        prefixText: 'https://',
        border: const OutlineInputBorder(),
        labelText: promptHomeserver,
        suffix: homeserverEntrySuffix(),
      ),
    );
  }

  Widget homeserverEntrySuffix() {
    if (widget.loadingServerInfo) {
      return const SizedBox(
        width: 15,
        height: 15,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Icon(
      widget.isServerValid ? Icons.check : Icons.close,
      size: 15,
      color: widget.isServerValid ? Colors.greenAccent : Colors.redAccent,
    );
  }

  SizedBox appIcon(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Image.asset(
        AppIconAssets.lightRounded,
        filterQuality: FilterQuality.high,
      ),
    );
  }

  void _onHomeserverTextUpdated() {
    if (widget.updateHomeserver != null) {
      widget.updateHomeserver?.call(_homeserverTextField.text);
    }
  }
}

/// Informational card shown on the mobile login screen explaining where to
/// create an account, since registration is gated there.
///
/// Deliberately renders the message as plain, selectable text with no tappable
/// link: native mobile must not open the browser to register — an account on an
/// independent homeserver cannot be reliably deleted, which Apple's guidelines
/// require — so users are told where to go and can copy the address by hand.
class AccountCreationNoticeCard extends StatelessWidget {
  const AccountCreationNoticeCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
