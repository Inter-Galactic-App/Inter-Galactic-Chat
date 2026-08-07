import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/molecules/user_panel.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/public_release_links.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/report_bug_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:intergalactic/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class HelpSafetyPage extends StatefulWidget {
  const HelpSafetyPage({super.key});

  @override
  State<HelpSafetyPage> createState() => _HelpSafetyPageState();
}

class _HelpSafetyPageState extends State<HelpSafetyPage> {
  final TextEditingController _roomIdController = TextEditingController();
  final TextEditingController _eventIdController = TextEditingController();
  final TextEditingController _reportUserIdController = TextEditingController();
  final TextEditingController _blockUserIdController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  Client? _selectedClient;
  Room? _selectedRoom;
  List<String> _ignoredUserIds = [];
  bool _blockAfterUserReport = true;
  bool _reportingEvent = false;
  bool _reportingRoom = false;
  bool _reportingUser = false;
  bool _updatingBlock = false;

  @override
  void initState() {
    super.initState();

    final initialClient = SettingsAccountController.resolvePreferredClient(
      clientManager,
    );
    if (initialClient != null) {
      _selectedClient = initialClient;
      _ignoredUserIds = _ignoredUsersFor(initialClient);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = clientManager;
    if (manager == null) {
      return;
    }

    final scopedClient = SettingsAccountScope.selectedClientOf(
      context,
      manager,
    );
    if (!identical(scopedClient, _selectedClient)) {
      _selectedClient = scopedClient;
      _selectedRoom = null;
      _ignoredUserIds =
          scopedClient == null ? <String>[] : _ignoredUsersFor(scopedClient);
    }
  }

  @override
  void dispose() {
    _roomIdController.dispose();
    _eventIdController.dispose();
    _reportUserIdController.dispose();
    _blockUserIdController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  List<Client> get _clients => clientManager?.clients.toList() ?? <Client>[];

  Client? get _currentClient {
    var clients = _clients;
    if (clients.isEmpty) {
      return null;
    }

    var selectedClient = _selectedClient;
    if (selectedClient == null || !clients.contains(selectedClient)) {
      return SettingsAccountController.resolvePreferredClient(clientManager);
    }

    return selectedClient;
  }

  MatrixClient? get _currentMatrixClient {
    var client = _currentClient;
    if (client is MatrixClient) {
      return client;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Help & Safety",
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Reports are sent through the Matrix homeserver for the selected account. Inter Galactic does not operate most Matrix homeservers, so the receiving server decides how reports are reviewed and enforced.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 16),
              _buildAccountSection(context),
              const SizedBox(height: 16),
              _buildReportSection(context),
              const SizedBox(height: 16),
              _buildBlockSection(context),
              const SizedBox(height: 16),
              _buildAppBugSection(context),
              const SizedBox(height: 16),
              _buildFeedbackSection(context),
              const SizedBox(height: 16),
              const _HelpSection(
                title: "Inter Galactic contact",
                children: [
                  tiamat.Text.body(
                    "For app support, use intergalactic@ourgalaxy.space. Emergency requests and illegal-content reports should also go to the relevant homeserver, platform, or legal/emergency pathway.",
                    softwrap: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeedbackSection(BuildContext context) {
    return _HelpSection(
      title: "Feedback and feature requests",
      children: [
        const tiamat.Text.body(
          "Use this for feature requests, usability feedback, or general feedback that does not need a diagnostic app bug report. The website form opens without attaching logs, Matrix identifiers, account identifiers, room names, or local paths.",
          softwrap: true,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: tiamat.Button.secondary(
            text: "Send Feedback",
            onTap: () => LinkUtils.open(
              PublicReleaseLinks.feedback.uri,
              context: context,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppBugSection(BuildContext context) {
    return _HelpSection(
      title: "Report app bug",
      children: [
        const tiamat.Text.body(
          "Use this for app crashes, broken UI, notification problems, media bugs, or anything that needs Inter Galactic diagnostics instead of a homeserver moderation report.",
          softwrap: true,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: tiamat.Button.secondary(
            text: "Report a Bug",
            onTap: () => showReportBugDialog(context),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    var clients = _clients;

    if (clients.isEmpty) {
      return const _HelpSection(
        title: "Matrix account",
        children: [
          tiamat.Text.body(
            "Sign in to a Matrix account to use Matrix-native report and block controls.",
            softwrap: true,
          ),
        ],
      );
    }

    var client = _currentClient!;

    return _HelpSection(
      title: "Matrix account",
      children: [
        UserPanelView(
          displayName: client.self?.displayName ?? client.identifier,
          detail: client.self?.identifier ?? client.identifier,
          avatar: client.self?.avatar,
        ),
        const SizedBox(height: 8),
        const tiamat.Text.labelLow(
          "Reports are sent from the account selected in the Settings header.",
          softwrap: true,
        ),
      ],
    );
  }

  Widget _buildReportSection(BuildContext context) {
    var rooms = _roomsForCurrentClient();
    var selectedRoom = _selectedRoomFor(rooms);

    return _HelpSection(
      title: "Report content",
      children: [
        const tiamat.Text.body(
          "Use a room ID and optional event ID when you have them. Message reports require that the selected account is joined to the room. Room and user reports may still be accepted by homeservers even when the account is not joined to the same room.",
          softwrap: true,
        ),
        const SizedBox(height: 12),
        if (rooms.isNotEmpty && selectedRoom != null) ...[
          const tiamat.Text.labelLow("Fill from a current room"),
          const SizedBox(height: 8),
          tiamat.DropdownSelector<Room>(
            items: rooms,
            value: selectedRoom,
            itemHeight: 56,
            onItemSelected: (room) {
              if (room == null) {
                return;
              }

              setState(() {
                _selectedRoom = room;
                _roomIdController.text = room.identifier;
              });
            },
            itemBuilder: (room) {
              return Row(
                children: [
                  Icon(room.icon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        tiamat.Text.labelEmphasised(
                          room.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                        tiamat.Text.labelLow(
                          room.identifier,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        tiamat.TextInput(
          label: "Room ID",
          placeholder: "!room:example.org",
          controller: _roomIdController,
        ),
        const SizedBox(height: 10),
        tiamat.TextInput(
          label: "Event ID",
          placeholder: r"$event:example.org",
          controller: _eventIdController,
        ),
        const SizedBox(height: 10),
        tiamat.TextInput(
          label: "User ID",
          placeholder: "@user:example.org",
          controller: _reportUserIdController,
        ),
        const SizedBox(height: 10),
        tiamat.TextInput(
          label: "Reason",
          placeholder: "Describe the abuse or policy issue.",
          controller: _reasonController,
          minLines: 3,
          maxLines: 5,
          maxLength: 1000,
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _blockAfterUserReport,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const tiamat.Text.label("Block user after user report"),
          subtitle: const tiamat.Text.labelLow(
            "This updates your Matrix ignored-user list.",
            softwrap: true,
          ),
          onChanged: (value) {
            setState(() {
              _blockAfterUserReport = value ?? false;
            });
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            tiamat.Button(
              text: "Report Message",
              isLoading: _reportingEvent,
              onTap: _reportEvent,
            ),
            tiamat.Button.secondary(
              text: "Report Room",
              isLoading: _reportingRoom,
              onTap: _reportRoom,
            ),
            tiamat.Button.secondary(
              text: "Report User",
              isLoading: _reportingUser,
              onTap: _reportUser,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBlockSection(BuildContext context) {
    return _HelpSection(
      title: "Block users",
      children: [
        const tiamat.Text.body(
          "Blocking writes to your Matrix ignored-user list. Homeservers should stop sending new messages and invites from ignored users, but old messages already synced to this device or delivered through federation may remain visible.",
          softwrap: true,
        ),
        const SizedBox(height: 12),
        tiamat.TextInput(
          label: "User ID",
          placeholder: "@user:example.org",
          controller: _blockUserIdController,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _DeepRedButton(
              text: "Block User",
              isLoading: _updatingBlock,
              onTap: () => _setUserBlocked(true),
            ),
            tiamat.Button.secondary(
              text: "Unblock User",
              isLoading: _updatingBlock,
              onTap: () => _setUserBlocked(false),
            ),
          ],
        ),
        if (_ignoredUserIds.isNotEmpty) ...[
          const SizedBox(height: 16),
          const tiamat.Text.labelLow("Blocked users"),
          const SizedBox(height: 8),
          ..._ignoredUserIds.map(
            (userId) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: tiamat.Text.label(
                      userId,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  tiamat.Button.secondary(
                    text: "Unblock",
                    onTap: _updatingBlock
                        ? null
                        : () {
                            _blockUserIdController.text = userId;
                            _setUserBlocked(false);
                          },
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Room> _roomsForCurrentClient() {
    var client = _currentClient;
    if (client == null) {
      return <Room>[];
    }

    var rooms = client.rooms.toList();
    rooms.sort((a, b) => a.displayName.compareTo(b.displayName));
    return rooms;
  }

  Room? _selectedRoomFor(List<Room> rooms) {
    if (rooms.isEmpty) {
      return null;
    }

    var selectedRoom = _selectedRoom;
    if (selectedRoom != null && rooms.contains(selectedRoom)) {
      return selectedRoom;
    }

    return rooms.first;
  }

  List<String> _ignoredUsersFor(Client client) {
    if (client is! MatrixClient) {
      return <String>[];
    }

    var ignored = client.matrixClient.matrixIgnoredUserIds().toList();
    ignored.sort();
    return ignored;
  }

  String get _roomId => _roomIdController.text.trim();

  String get _eventId => _eventIdController.text.trim();

  String get _reportUserId => _reportUserIdController.text.trim();

  String get _blockUserId => _blockUserIdController.text.trim();

  String get _reason => _reasonController.text.trim();

  Future<void> _reportEvent() async {
    var client = _currentMatrixClient;
    if (client == null) {
      _showError("Sign in to a Matrix account before reporting content.");
      return;
    }

    if (_roomId.isEmpty || _eventId.isEmpty) {
      _showError("Enter both a room ID and event ID to report a message.");
      return;
    }

    setState(() {
      _reportingEvent = true;
    });

    try {
      await client.matrixClient
          .submitMatrixEventReport(_roomId, _eventId, reason: _reason);
      _showSuccess("Message report sent to the selected homeserver.");
    } catch (exception) {
      _showError("Message report failed: $exception");
    } finally {
      if (mounted) {
        setState(() {
          _reportingEvent = false;
        });
      }
    }
  }

  Future<void> _reportRoom() async {
    var client = _currentMatrixClient;
    if (client == null) {
      _showError("Sign in to a Matrix account before reporting a room.");
      return;
    }

    if (_roomId.isEmpty) {
      _showError("Enter a room ID to report a room.");
      return;
    }

    setState(() {
      _reportingRoom = true;
    });

    try {
      await client.matrixClient.submitMatrixRoomReport(
        _roomId,
        reason: _reason,
      );
      _showSuccess("Room report sent to the selected homeserver.");
    } catch (exception) {
      _showError("Room report failed: $exception");
    } finally {
      if (mounted) {
        setState(() {
          _reportingRoom = false;
        });
      }
    }
  }

  Future<void> _reportUser() async {
    var client = _currentMatrixClient;
    if (client == null) {
      _showError("Sign in to a Matrix account before reporting a user.");
      return;
    }

    if (_reportUserId.isEmpty) {
      _showError("Enter a Matrix user ID to report.");
      return;
    }

    setState(() {
      _reportingUser = true;
    });

    try {
      await client.matrixClient.submitMatrixUserReport(
        _reportUserId,
        reason: _reason,
      );

      if (_blockAfterUserReport) {
        await client.matrixClient.setMatrixUserIgnored(_reportUserId, true);
        _setIgnoredUserLocally(_reportUserId, true);
        _showSuccess("User report sent and user blocked.");
      } else {
        _showSuccess("User report sent to the selected homeserver.");
      }
    } catch (exception) {
      _showError("User report failed: $exception");
    } finally {
      if (mounted) {
        setState(() {
          _reportingUser = false;
        });
      }
    }
  }

  Future<void> _setUserBlocked(bool blocked) async {
    var client = _currentMatrixClient;
    if (client == null) {
      _showError("Sign in to a Matrix account before updating blocks.");
      return;
    }

    if (_blockUserId.isEmpty) {
      _showError("Enter a Matrix user ID to block or unblock.");
      return;
    }

    setState(() {
      _updatingBlock = true;
    });

    try {
      await client.matrixClient.setMatrixUserIgnored(_blockUserId, blocked);
      _setIgnoredUserLocally(_blockUserId, blocked);
      _showSuccess(blocked ? "User blocked." : "User unblocked.");
    } catch (exception) {
      _showError("Block update failed: $exception");
    } finally {
      if (mounted) {
        setState(() {
          _updatingBlock = false;
        });
      }
    }
  }

  void _setIgnoredUserLocally(String userId, bool ignored) {
    if (!mounted) {
      return;
    }

    setState(() {
      var users = _ignoredUserIds.toSet();
      if (ignored) {
        users.add(userId);
      } else {
        users.remove(userId);
      }
      _ignoredUserIds = users.toList()..sort();
    });
  }

  void _showSuccess(String message) {
    _showSnackBar(message);
  }

  void _showError(String message) {
    _showSnackBar(message);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: tiamat.Text.label(message, softwrap: true),
      ),
    );
  }
}

class HelpPoliciesPage extends StatelessWidget {
  const HelpPoliciesPage({super.key});

  static const List<_PolicyDocument> _documents = [
    _PolicyDocument(
      title: "Privacy Policy",
      link: PublicReleaseLinks.privacy,
      body:
          "Inter Galactic is a Matrix client. Messages, media, room membership, account details, and account deletion are primarily controlled by the homeserver selected by the user. End-to-end encrypted messages are designed so Inter Galactic and homeserver operators cannot read message contents, but metadata, push notification routing, backups, bridges, URL previews, GIF search, diagnostics, and third-party integrations can involve separate services.",
    ),
    _PolicyDocument(
      title: "Terms / EULA",
      link: PublicReleaseLinks.terms,
      body:
          "Users are responsible for how they use the app and for following the rules of their selected homeserver and any third-party services. Inter Galactic does not guarantee homeserver availability or moderation outcomes. Inter Galactic is distributed as an AGPL fork with source availability obligations for released binaries.",
    ),
    _PolicyDocument(
      title: "Community Guidelines",
      link: PublicReleaseLinks.communityGuidelines,
      body:
          "Do not harass, threaten, spam, impersonate, distribute illegal content, or share non-consensual sexual content. Moderation is handled by the selected Matrix homeserver, room administrators, and any bridged services, subject to their policies and technical limits.",
    ),
    _PolicyDocument(
      title: "Report Abuse",
      link: PublicReleaseLinks.reportAbuse,
      body:
          "Use Help & Safety to send Matrix-native message, room, or user reports to the selected homeserver. Reports may include the room ID, event ID, user ID, reason text, and the reporting account. Inter Galactic may not receive or review those reports unless it operates the selected homeserver.",
    ),
    _PolicyDocument(
      title: "Account Deletion",
      link: PublicReleaseLinks.accountDeletion,
      body:
          "Deleting the app does not delete a Matrix account. Account deletion is controlled by the selected homeserver. Account Management includes a per-account deletion handoff that can open the selected homeserver when a launchable URL is available and explains these limits. Messages and media already delivered to other users, other homeservers, backups, bridges, or room history may not be fully removable.",
    ),
    _PolicyDocument(
      title: "Support",
      link: PublicReleaseLinks.support,
      body:
          "Inter Galactic contact: intergalactic@ourgalaxy.space. Use the selected homeserver's support or abuse pathway for account, moderation, safety, and data deletion requests tied to that homeserver.",
    ),
    _PolicyDocument(
      title: "Source Offer",
      link: PublicReleaseLinks.source,
      body:
          "Released Inter Galactic builds are distributed with source availability and fork attribution. Use the source page for release source, license, and upstream Commet information.",
    ),
    _PolicyDocument(
      title: "Third-Party Notices",
      link: PublicReleaseLinks.thirdPartyNotices,
      body:
          "The third-party notice bundle records shipped dependency, native binary, asset, and fork-attribution notices for Inter Galactic release builds.",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const tiamat.Text.largeTitle("Policies"),
              const SizedBox(height: 8),
              const tiamat.Text.body(
                "These summaries describe the app's public-release policy posture. The selected Matrix homeserver remains responsible for homeserver accounts, stored Matrix data, and homeserver moderation decisions unless Inter Galactic also operates that homeserver.",
                softwrap: true,
              ),
              const SizedBox(height: 16),
              ..._documents.map(
                (document) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _HelpSection(
                    title: document.title,
                    children: [
                      tiamat.Text.body(document.body, softwrap: true),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: tiamat.Button.secondary(
                          text: "Open ${document.link.title}",
                          onTap: () => LinkUtils.open(
                            document.link.uri,
                            context: context,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _DeepRedButton extends StatelessWidget {
  const _DeepRedButton({
    required this.text,
    required this.onTap,
    this.isLoading = false,
  });

  final String text;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final tokens = AccessibilityScope.tokensOf(context);
    final buttonStyle =
        Theme.of(context).elevatedButtonTheme.style ?? const ButtonStyle();
    final foreground = tokens.onDanger;

    return ElevatedButton(
      style: buttonStyle.copyWith(
        backgroundColor: WidgetStatePropertyAll(tokens.danger),
        foregroundColor: WidgetStatePropertyAll(foreground),
      ),
      onPressed: isLoading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: isLoading
            ? SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Text(
                text,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0,
                    ),
              ),
      ),
    );
  }
}

class _PolicyDocument {
  const _PolicyDocument({
    required this.title,
    required this.link,
    required this.body,
  });

  final String title;
  final PublicReleaseLink link;
  final String body;
}
