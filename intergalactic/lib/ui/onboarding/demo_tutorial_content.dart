import 'package:flutter/material.dart';
import 'package:intergalactic/ui/onboarding/onboarding_step.dart';

const List<OnboardingStep> demoTutorialSteps = [
  OnboardingStep(
    id: 'welcome-1',
    title: 'Welcome to Inter Galactic',
    body:
        'Welcome to Inter Galactic. This quick tour shows the main places you will use every day. You can use the arrow keys to move between steps.',
    icon: Icons.auto_awesome_outlined,
    targetAnchorId: 'app.shell',
  ),
  OnboardingStep(
    id: 'spaces-1',
    title: 'Spaces and Servers',
    body: 'Spaces group rooms together.',
    icon: Icons.account_tree_outlined,
    targetAnchorId: 'space.rail',
  ),
  OnboardingStep(
    id: 'spaces-2',
    title: 'Spaces and Servers',
    body:
        'Use the side rail to move between communities, favorites, and account areas.',
    icon: Icons.view_sidebar_outlined,
    targetAnchorId: 'space.rail',
  ),
  OnboardingStep(
    id: 'rooms-1',
    title: 'Rooms',
    body: 'Rooms are where the conversation happens.',
    icon: Icons.forum_outlined,
    targetAnchorId: 'room.list',
  ),
  OnboardingStep(
    id: 'rooms-chat',
    title: 'Rooms',
    body: 'Rooms can be chats.',
    icon: Icons.chat_bubble_outline,
    targetAnchorId: 'room.chat',
  ),
  OnboardingStep(
    id: 'rooms-forum',
    title: 'Forums',
    body: 'Forums keep slower discussions organized with topics and tags.',
    icon: Icons.dynamic_feed_outlined,
    targetAnchorId: 'room.forum',
  ),
  OnboardingStep(
    id: 'rooms-photo',
    title: 'Photo Albums',
    body:
        'Photo albums collect individual photos and photo stacks, with comments attached to the photo or stack root.',
    icon: Icons.photo_library_outlined,
    targetAnchorId: 'room.photoAlbum',
  ),
  OnboardingStep(
    id: 'rooms-calendar',
    title: 'Calendars',
    body: 'Calendars give a room or group a shared place for events.',
    icon: Icons.calendar_month_outlined,
    targetAnchorId: 'room.calendar',
  ),
  OnboardingStep(
    id: 'rooms-voice',
    title: 'Voice Chat',
    body: 'Voice rooms show who is connected and provide call controls.',
    icon: Icons.headset_mic_outlined,
    targetAnchorId: 'room.voice',
  ),
  OnboardingStep(
    id: 'rooms-dms',
    title: 'Direct Messages',
    body:
        'Direct Messages live alongside rooms for one-to-one conversations. These are found in the home tab.',
    icon: Icons.person_outline,
    targetAnchorId: 'home.directMessages',
  ),
  OnboardingStep(
    id: 'messaging-1',
    title: 'Messages, Media, GIFs, and Reactions',
    body: 'Use the composer to send text, media, GIFs, and reactions.',
    icon: Icons.add_reaction_outlined,
    targetAnchorId: 'composer',
  ),
  OnboardingStep(
    id: 'messaging-menus',
    title: 'Messages, Media, GIFs, and Reactions',
    body:
        'Attachment, GIF, sticker, and emoticon pickers live close to the composer so they do not hide the whole chat.',
    icon: Icons.add_box_outlined,
    targetAnchorId: 'composer.menus',
  ),
  OnboardingStep(
    id: 'messaging-effects-intro',
    title: 'Message Effects',
    body: 'You can even send messages with effects.',
    icon: Icons.auto_awesome,
    targetAnchorId: 'composer.effects',
  ),
  OnboardingStep(
    id: 'messaging-effects-demo',
    title: 'Message Effects',
    body:
        'Effects can make a single message feel playful without changing the room.',
    icon: Icons.ac_unit_outlined,
    targetAnchorId: 'timeline.effect',
  ),
  OnboardingStep(
    id: 'messaging-nicknames',
    title: 'Nicknames',
    body:
        'Nicknames can be set per room for yourself or other members depending on permissions.',
    icon: Icons.badge_outlined,
    targetAnchorId: 'members.nicknames',
  ),
  OnboardingStep(
    id: 'emoticons-room',
    title: 'Emoticons',
    body:
        'You can manage your own emoticons and sticker packs from account, space, or room emoticon settings when permissions allow it.',
    icon: Icons.emoji_emotions_outlined,
    targetAnchorId: 'settings.roomEmoticons',
  ),
  OnboardingStep(
    id: 'emoticons-heart',
    title: 'Emoticons',
    body:
        'When adding a pack to a room, click the heart to enable it globally and let other users have access to it as well.',
    icon: Icons.favorite_border,
    targetAnchorId: 'settings.emoticonHeart',
  ),
  OnboardingStep(
    id: 'emoticons-app',
    title: 'Emoticons',
    body: 'All packs available to you can be found in your Emoticons settings.',
    icon: Icons.emoji_symbols_outlined,
    targetAnchorId: 'settings.appEmoticons',
  ),
  OnboardingStep(
    id: 'calls-settings',
    title: 'Calls and Screen Sharing',
    body:
        'Voice Chat rooms support calls and screen sharing. Screen-share behavior and call devices live in Voice and Video settings.',
    icon: Icons.video_call_outlined,
    targetAnchorId: 'settings.voiceVideo',
  ),
  OnboardingStep(
    id: 'calls-controls',
    title: 'Calls and Screen Sharing',
    body:
        'Call and stream buttons stay visible here so you can see popout, fullscreen, screen-share, and member volume controls. Right-click a stream for the full menu.',
    icon: Icons.volume_up_outlined,
    targetAnchorId: 'call.memberControls',
  ),
  OnboardingStep(
    id: 'calls-popout',
    title: 'Calls and Screen Sharing',
    body:
        'You can even pop out the call window and enable a transparent overlay that pins above applications.',
    icon: Icons.open_in_new_outlined,
    targetAnchorId: 'call.popout',
  ),
  OnboardingStep(
    id: 'soundboard-popup',
    title: 'Soundboard',
    body: 'You can play sounds to a soundboard while in calls or add your own.',
    icon: Icons.graphic_eq,
    targetAnchorId: 'call.soundboard',
  ),
  OnboardingStep(
    id: 'soundboard-space',
    title: 'Soundboard',
    body:
        'Sounds can be managed in space settings and can be set as a join sound to automatically play when joining a call.',
    icon: Icons.library_music_outlined,
    targetAnchorId: 'settings.spaceSoundboard',
  ),
  OnboardingStep(
    id: 'soundboard-app',
    title: 'Soundboard',
    body:
        'Soundboards are space specific, but you can quickly access any soundboards available to you from app settings.',
    icon: Icons.speaker_group_outlined,
    targetAnchorId: 'settings.appSoundboard',
  ),
  OnboardingStep(
    id: 'notifications-settings',
    title: 'Notifications',
    body:
        'Notification behavior can be tuned globally, per space, per room, and per platform.',
    icon: Icons.notifications_active_outlined,
    targetAnchorId: 'settings.notifications',
  ),
  OnboardingStep(
    id: 'notifications-overrides',
    title: 'Notifications',
    body:
        'You can easily manage your space and room overrides in your account level settings.',
    icon: Icons.rule_folder_outlined,
    targetAnchorId: 'settings.notificationOverrides',
  ),
  OnboardingStep(
    id: 'desktop-companion-settings',
    title: 'Desktop Companion',
    body:
        'You can enable a desktop companion to quickly see your notifications when Inter Galactic is minimized.',
    icon: Icons.desktop_windows_outlined,
    targetAnchorId: 'settings.desktopCompanion',
  ),
  OnboardingStep(
    id: 'desktop-companion-animation',
    title: 'Desktop Companion',
    body:
        'The desktop companion shows previews, unread counts, and a compact history of unopened messages.',
    icon: Icons.notifications_outlined,
    targetAnchorId: 'desktopCompanion.animation',
  ),
  OnboardingStep(
    id: 'desktop-companion-active',
    title: 'Desktop Companion',
    body:
        'Clicking a companion message brings you back to the corresponding chat.',
    icon: Icons.near_me_outlined,
    targetAnchorId: 'desktopCompanion.activeNotification',
  ),
  OnboardingStep(
    id: 'desktop-companion-neutral',
    title: 'Desktop Companion',
    body:
        'The desktop companion pins to the top of your windows and does not populate on the taskbar.',
    icon: Icons.vertical_align_top_outlined,
    targetAnchorId: 'desktopCompanion.neutral',
  ),
  OnboardingStep(
    id: 'customization-appearance',
    title: 'Customization Settings',
    body:
        'Customize themes, bubbles, backgrounds, and app icon from the Appearance tab.',
    icon: Icons.palette_outlined,
    targetAnchorId: 'settings.appearance',
  ),
  OnboardingStep(
    id: 'customization-room',
    title: 'Customization Settings',
    body: 'Bubble colors and backgrounds can even be set on a per-room basis.',
    icon: Icons.format_paint_outlined,
    targetAnchorId: 'settings.roomAppearance',
  ),
  OnboardingStep(
    id: 'customization-theme-editor',
    title: 'Theme Workshop',
    body: 'You can even build your own themes with the built-in theme editor.',
    icon: Icons.color_lens_outlined,
    targetAnchorId: 'settings.themeEditor',
  ),
  OnboardingStep(
    id: 'activity-settings',
    title: 'Activity and Presence',
    body:
        'Connect Spotify, Steam, or Apple Music to your accounts to provide unique features.',
    icon: Icons.sensors_outlined,
    targetAnchorId: 'settings.activity',
  ),
  OnboardingStep(
    id: 'activity-card',
    title: 'Activity and Presence',
    body:
        'Enable activity to create a unique card where you can see and control your music and publish updates to your Matrix status.',
    icon: Icons.album_outlined,
    targetAnchorId: 'activity.card',
  ),
  OnboardingStep(
    id: 'account-quick-access',
    title: 'Account Quick Access',
    body: 'Use the user bar to manage your account, status, and activities.',
    icon: Icons.account_circle_outlined,
    targetAnchorId: 'account.popup',
  ),
  OnboardingStep(
    id: 'privacy-default',
    title: 'Privacy and Encryption',
    body:
        'Encryption follows room settings. Keep your keys and devices to recover encrypted history.',
    icon: Icons.enhanced_encryption_outlined,
    targetAnchorId: 'room.encryption',
  ),
  OnboardingStep(
    id: 'privacy-security-settings',
    title: 'Privacy and Encryption',
    body: 'Manage your session in Security settings.',
    icon: Icons.security_outlined,
    targetAnchorId: 'settings.security',
  ),
  OnboardingStep(
    id: 'privacy-verify',
    title: 'Privacy and Encryption',
    body: 'Here you can verify your session.',
    icon: Icons.verified_user_outlined,
    targetAnchorId: 'security.verify',
  ),
  OnboardingStep(
    id: 'privacy-decryption',
    title: 'Privacy and Encryption',
    body: 'You can run decryption for all your joined rooms and spaces.',
    icon: Icons.lock_open_outlined,
    targetAnchorId: 'security.decryption',
  ),
  OnboardingStep(
    id: 'privacy-sessions',
    title: 'Privacy and Encryption',
    body: 'You can also manage your sessions from this area.',
    icon: Icons.devices_outlined,
    targetAnchorId: 'security.sessions',
  ),
  OnboardingStep(
    id: 'privacy-padlock',
    title: 'Privacy and Encryption',
    body:
        'If messages become out of sync in a room, click the padlock to run decryption for that room.',
    icon: Icons.lock_outline,
    targetAnchorId: 'room.decryptPadlock',
  ),
  OnboardingStep(
    id: 'help-safety',
    title: 'Help and Safety',
    body: 'If you need to report or block a user, use the Help and Safety tab.',
    icon: Icons.health_and_safety_outlined,
    targetAnchorId: 'settings.helpSafety',
  ),
  OnboardingStep(
    id: 'help-report-bug',
    title: 'Report a Bug',
    body:
        'To report a bug, fill out the provided form. This sends redacted logs straight from the app.',
    icon: Icons.bug_report_outlined,
    targetAnchorId: 'settings.reportBug',
  ),
  OnboardingStep(
    id: 'help-faq',
    title: 'FAQ',
    body: 'If you have questions, check the FAQ.',
    icon: Icons.question_answer_outlined,
    targetAnchorId: 'settings.faq',
  ),
  OnboardingStep(
    id: 'help-tutorial',
    title: 'Replay Tutorial',
    body: 'Or replay this tutorial any time from Settings > Help > Tutorial.',
    icon: Icons.school_outlined,
    primaryActionLabel: 'Finish',
    targetAnchorId: 'settings.tutorialReplay',
  ),
];
