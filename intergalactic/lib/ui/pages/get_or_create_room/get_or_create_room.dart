import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/space_child.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/calendar_views.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/existing_room_picker.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/join_room_view.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/forum_views.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/photo_album_views.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/room_creation_strings.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/room_creator.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/space_views.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/text_chat_views.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/voice_chat_view.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomGetter {
  final String label;
  final String summary;
  final IconData icon;
  final Widget Function(BuildContext context) descriptionBuilder;
  final Widget Function(BuildContext context, {Function(SpaceChild)? onPicked})
      formBuilder;

  final Future<SpaceChild> Function(CreateRoomArgs args)? create;
  final bool hero;

  const RoomGetter({
    required this.label,
    required this.summary,
    required this.icon,
    this.hero = false,
    required this.descriptionBuilder,
    required this.formBuilder,
    this.create,
  });
}

enum _RoomSourceOptions { create, existing, join }

class GetOrCreateRoom extends StatefulWidget {
  const GetOrCreateRoom(
      {super.key, required this.creators, this.existing, this.join});

  final List<RoomGetter> creators;
  final RoomGetter? existing;
  final RoomGetter? join;

  static Future<SpaceChild?> show(
    Client? client,
    BuildContext context, {
    bool joinRoom = true,
    bool pickExisting = true,
    bool showAllRoomTypes = false,
    bool includeSpaceInAllRoomTypes = true,
    bool createSpace = false,
    bool createTextChat = false,
    bool createVoiceChat = false,
    bool createPhotoRoom = false,
    bool createCalendar = false,
    bool createForum = false,
    String? initialRoomAddress,
    Space? currentSpace,
    bool Function(SpaceChild child)? existingRoomsRemoveWhere,
  }) async {
    if (client == null) {
      client = await AdaptiveDialog.pickClient(
        context,
      );
    }

    if (client == null) {
      return null;
    }

    final creators = [
      if (showAllRoomTypes || createTextChat)
        RoomGetter(
          label: RoomCreationStrings.labelRoomTypeTextChat,
          summary: RoomCreationStrings.summaryRoomTypeTextChat,
          icon: Icons.tag,
          descriptionBuilder: (context) => TextChatCreatorDescription(),
          formBuilder: (context, {onPicked}) => RoomCreatorWidget(
            fields: [
              RoomFieldName(),
              RoomFieldTopic(),
              RoomFieldVisibility(client: client!, currentSpace: currentSpace),
              RoomFieldEncryption(
                  canEnableEncryption: true, defaultEnabled: true),
            ],
          ),
          create: (args) async {
            return SpaceChildRoom(await client!.createRoom(args));
          },
        ),
      if ((showAllRoomTypes || createVoiceChat))
        RoomGetter(
          label: RoomCreationStrings.labelRoomTypeVoiceChat,
          summary: RoomCreationStrings.summaryRoomTypeVoiceChat,
          icon: Icons.volume_up,
          descriptionBuilder: (context) => VoiceChatCreatorDescription(),
          formBuilder: (context, {onPicked}) => RoomCreatorWidget(
            fields: [
              RoomFieldName(),
              RoomFieldTopic(),
              RoomFieldVisibility(client: client!, currentSpace: currentSpace),
              RoomFieldEncryption(
                  canEnableEncryption: false, defaultEnabled: false),
              RoomFieldType(RoomType.voipRoom),
            ],
          ),
          create: (args) async {
            return SpaceChildRoom(await client!.createRoom(args));
          },
        ),
      if ((showAllRoomTypes || createPhotoRoom))
        RoomGetter(
          label: RoomCreationStrings.labelRoomTypePhotoAlbum,
          summary: RoomCreationStrings.summaryRoomTypePhotoAlbum,
          icon: Icons.photo,
          descriptionBuilder: (context) => PhotoAlbumCreatorDescription(),
          formBuilder: (context, {onPicked}) => RoomCreatorWidget(
            fields: [
              RoomFieldName(),
              RoomFieldTopic(),
              RoomFieldVisibility(client: client!, currentSpace: currentSpace),
              RoomFieldEncryption(defaultEnabled: true),
              RoomFieldType(RoomType.photoAlbum),
            ],
          ),
          create: (args) async {
            return SpaceChildRoom(await client!.createRoom(args));
          },
        ),
      if ((showAllRoomTypes || createCalendar))
        RoomGetter(
          label: RoomCreationStrings.labelRoomTypeCalendar,
          summary: RoomCreationStrings.summaryRoomTypeCalendar,
          icon: Icons.calendar_month,
          descriptionBuilder: (context) => CalendarCreatorDescription(),
          formBuilder: (context, {onPicked}) => RoomCreatorWidget(
            fields: [
              RoomFieldName(),
              RoomFieldTopic(),
              RoomFieldVisibility(client: client!, currentSpace: currentSpace),
              RoomFieldEncryption(defaultEnabled: true),
              RoomFieldType(RoomType.calendar),
            ],
          ),
          create: (args) async {
            return SpaceChildRoom(await client!.createRoom(args));
          },
        ),
      if ((showAllRoomTypes || createForum))
        RoomGetter(
          label: RoomCreationStrings.labelRoomTypeForum,
          summary: RoomCreationStrings.summaryRoomTypeForum,
          icon: Icons.forum,
          descriptionBuilder: (context) => ForumCreatorDescription(),
          formBuilder: (context, {onPicked}) => RoomCreatorWidget(
            fields: [
              RoomFieldName(),
              RoomFieldTopic(),
              RoomFieldVisibility(client: client!, currentSpace: currentSpace),
              RoomFieldEncryption(defaultEnabled: false),
              RoomFieldType(RoomType.forum),
            ],
          ),
          create: (args) async {
            return SpaceChildRoom(await client!.createRoom(args));
          },
        ),
      if (createSpace || (showAllRoomTypes && includeSpaceInAllRoomTypes))
        RoomGetter(
          label: RoomCreationStrings.labelRoomTypeSpace,
          summary: RoomCreationStrings.summaryRoomTypeSpace,
          icon: Icons.spoke,
          descriptionBuilder: (context) => SpaceCreatorDescription(),
          formBuilder: (context, {onPicked}) => RoomCreatorWidget(
            fields: [
              RoomFieldName(),
              RoomFieldTopic(),
              RoomFieldVisibility(client: client!, currentSpace: currentSpace),
            ],
          ),
          create: (args) async {
            return SpaceChildSpace(await client!.createSpace(args));
          },
        ),
    ];

    final existing = pickExisting
        ? RoomGetter(
            label: RoomCreationStrings.labelPickExistingRoom,
            summary: RoomCreationStrings.summaryPickExistingRoom,
            hero: true,
            icon: Icons.add,
            descriptionBuilder: (_) => Placeholder(),
            formBuilder: (context, {onPicked}) => ExistingRoomPicker(
              client: client!,
              filter: existingRoomsRemoveWhere,
              onPicked: onPicked,
            ),
          )
        : null;

    final join = joinRoom
        ? RoomGetter(
            label: RoomCreationStrings.labelJoinRoom,
            summary: RoomCreationStrings.summaryJoinRoom,
            hero: true,
            icon: Icons.search,
            descriptionBuilder: (_) => Placeholder(),
            formBuilder: (context, {onPicked}) => JoinRoomView(
              client!,
              asSpace: false,
              onPicked: onPicked,
              initialRoomAddress: initialRoomAddress,
            ),
          )
        : null;

    if (Layout.mobile) {
      _RoomSourceOptions? source;
      if (initialRoomAddress != null) {
        source = _RoomSourceOptions.join;
      } else {
        source = await AdaptiveDialog.pickOne(context,
            items: [
              _RoomSourceOptions.create,
              if (existing != null) _RoomSourceOptions.existing,
              if (join != null) _RoomSourceOptions.join,
            ],
            itemBuilder: (context, item, callback) => SizedBox(
                  height: 50,
                  child: switch (item) {
                    _RoomSourceOptions.create => tiamat.TextButton(
                        RoomCreationStrings.labelCreateRoom,
                        icon: Icons.add,
                        onTap: callback,
                      ),
                    _RoomSourceOptions.existing => tiamat.TextButton(
                        RoomCreationStrings.labelPickExistingRoom,
                        icon: Icons.tag,
                        onTap: callback,
                      ),
                    _RoomSourceOptions.join => tiamat.TextButton(
                        RoomCreationStrings.labelJoinRoom,
                        icon: Icons.alternate_email,
                        onTap: callback,
                      ),
                  },
                ));
      }

      if (source == _RoomSourceOptions.create) {
        return AdaptiveDialog.show<SpaceChild>(
          context,
          scrollable: false,
          builder: (context) {
            return GetOrCreateRoom(
              creators: creators,
            );
          },
        );
      }

      if (source == _RoomSourceOptions.join) {
        return AdaptiveDialog.show<SpaceChild>(
          context,
          scrollable: false,
          builder: (context) {
            return join!.formBuilder(context,
                onPicked: (i) => Navigator.of(context).pop(i));
          },
        );
      }

      if (source == _RoomSourceOptions.existing) {
        return AdaptiveDialog.show<SpaceChild>(
          context,
          scrollable: false,
          builder: (context) {
            return SizedBox(
                height: 500,
                child: existing!.formBuilder(context,
                    onPicked: (i) => Navigator.of(context).pop(i)));
          },
        );
      }

      return null;
    }

    return AdaptiveDialog.show<SpaceChild>(
      context,
      scrollable: false,
      builder: (context) {
        return GetOrCreateRoom(
          creators: creators,
          existing: existing,
          join: join,
        );
      },
    );
  }

  @override
  State<GetOrCreateRoom> createState() => _GetOrCreateRoomState();
}

class _GetOrCreateRoomState extends State<GetOrCreateRoom> {
  RoomGetter? selected;
  bool loading = false;

  @override
  void initState() {
    super.initState();

    if (widget.join != null) {
      selected = widget.join;
    } else if (widget.creators.isNotEmpty) {
      selected = widget.creators.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Layout.mobile) {
      return IgnorePointer(
        ignoring: loading,
        child: Opacity(
          opacity: loading ? 0.5 : 1.0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (widget.creators.length == 1) {
                return SizedBox(
                  height: 520,
                  child: buildListViewEntry(
                      widget.creators.first, context, constraints.maxWidth),
                );
              }

              final cardWidth =
                  (constraints.maxWidth - 64).clamp(280.0, 360.0).toDouble();
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 520,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.creators.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => buildListViewEntry(
                      widget.creators[index],
                      context,
                      cardWidth,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return SizedBox(
      width: 840,
      height: 520,
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: loading,
            child: Opacity(
              opacity: loading ? 0.5 : 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  SingleChildScrollView(
                    child: SizedBox(
                      width: 256,
                      child: Column(
                        spacing: 8,
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.existing != null)
                            createEntry(context, widget.existing!),
                          if (widget.join != null)
                            createEntry(context, widget.join!),
                          if (widget.creators.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(2, 6, 0, 2),
                              child: tiamat.Text.labelLow(
                                  RoomCreationStrings.labelCreateRoomSection),
                            ),
                          for (var entry in widget.creators)
                            createEntry(context, entry)
                        ],
                      ),
                    ),
                  ),
                  if (selected != null)
                    Flexible(
                        child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ColorScheme.of(context).surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: ColorScheme.of(context)
                              .outlineVariant
                              .withValues(alpha: 0.28),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _RoomChoiceHeader(entry: selected!),
                            const SizedBox(height: 12),
                            if (!selected!.hero)
                              Expanded(
                                child: _RoomDescriptionFade(
                                  child: SingleChildScrollView(
                                    physics: NeverScrollableScrollPhysics(),
                                    child: selected!.descriptionBuilder(
                                      context,
                                    ),
                                  ),
                                ),
                              ),
                            if (selected!.hero)
                              Expanded(
                                  child: selected!.formBuilder(
                                context,
                                onPicked: onExistingRoomPicked,
                              )),
                            if (!selected!.hero)
                              Align(
                                alignment: AlignmentGeometry.bottomRight,
                                child: tiamat.Button(
                                  text: CommonStrings.promptNext,
                                  onTap: () {
                                    onNextButtonPressed(selected!);
                                  },
                                ),
                              )
                          ],
                        ),
                      ),
                    ))
                ],
              ),
            ),
          ),
          if (loading)
            Center(
              child: _RoomCreationProgress(
                label: RoomCreationStrings.labelCreatingRoomType(
                  selected?.label ?? RoomCreationStrings.labelCreateRoom,
                ),
              ),
            )
        ],
      ),
    );
  }

  Widget buildListViewEntry(
      RoomGetter entry, BuildContext context, double width) {
    final scheme = ColorScheme.of(context);
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.28),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RoomChoiceHeader(entry: entry),
              const SizedBox(height: 12),
              Expanded(
                child: _RoomDescriptionFade(
                  child: SingleChildScrollView(
                    physics: NeverScrollableScrollPhysics(),
                    child: entry.descriptionBuilder(context),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              tiamat.Button(
                text: CommonStrings.promptNext,
                isLoading: entry == selected && loading,
                onTap: () => onNextButtonPressed(entry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget createEntry(BuildContext context, RoomGetter entry) {
    final scheme = ColorScheme.of(context);
    final highlighted = entry == selected;
    return Semantics(
      button: true,
      selected: highlighted,
      label: '${entry.label}. ${entry.summary}',
      child: Material(
        color: highlighted
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            setState(() {
              selected = entry;
            });
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: highlighted
                    ? scheme.primary.withValues(alpha: 0.44)
                    : scheme.outlineVariant.withValues(alpha: 0.22),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    entry.icon,
                    size: 18,
                    color: highlighted ? scheme.primary : scheme.onSurface,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        tiamat.Text.label(entry.label),
                        const SizedBox(height: 2),
                        tiamat.Text.labelLow(
                          entry.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  onNextButtonPressed(RoomGetter entry) async {
    setState(() {
      selected = entry;
      loading = true;
    });

    var args = await AdaptiveDialog.show<CreateRoomArgs>(
      context,
      title: entry.label,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: entry.formBuilder(context),
        );
      },
    );

    setState(() {
      selected = entry;
      loading = true;
    });

    if (args != null) {
      try {
        var result = await entry.create!(args);

        print(result);

        Navigator.of(context).pop(result);
      } catch (e, s) {
        Log.onError(e, s);
        await AdaptiveDialog.show(
          context,
          title: "Error",
          builder: (context) {
            return tiamat.Text.body(e.toString());
          },
        );

        Navigator.of(context).pop();
      }
    } else {
      setState(() {
        loading = false;
      });
    }
  }

  onExistingRoomPicked(SpaceChild result) {
    print("Existing picked: ${result}");
    Navigator.of(context).pop(result);
  }
}

class _RoomChoiceHeader extends StatelessWidget {
  const _RoomChoiceHeader({required this.entry});

  final RoomGetter entry;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.28),
            ),
          ),
          child: Icon(
            entry.icon,
            size: 19,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.label,
                style: TextTheme.of(context).headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              tiamat.Text.labelLow(
                entry.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoomDescriptionFade extends StatelessWidget {
  const _RoomDescriptionFade({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [
            0,
            0.86,
            1,
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}

class _RoomCreationProgress extends StatelessWidget {
  const _RoomCreationProgress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.34),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            tiamat.Text.label(label),
          ],
        ),
      ),
    );
  }
}
