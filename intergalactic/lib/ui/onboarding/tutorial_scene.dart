import 'package:flutter/material.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/onboarding/tutorial_focus_overlay.dart';

enum TutorialDemoSettingsSurface {
  appAppearance,
  appActivity,
  appVoiceAndVideo,
  appSoundboard,
  appNotifications,
  appDesktopCompanion,
  appEmoticons,
  accountSecurity,
  helpSafety,
  helpReportBug,
  helpFaq,
  helpTutorial,
  roomEmoticons,
  roomAppearance,
  spaceSoundboard,
  themeEditor,
}

enum TutorialDemoOverlay {
  spaceRail,
  roomList,
  photoThreadPanel,
  composer,
  mediaMenuCycle,
  effectsMenu,
  snowEffect,
  membersNicknames,
  emoticonHeart,
  emoticonPacks,
  callMemberControls,
  callPopout,
  soundboardPopup,
  companionAnimation,
  companionActiveNotification,
  companionNeutral,
  activityCard,
  accountPopup,
  securityVerify,
  securityDecryption,
  securitySessions,
  encryptionPadlock,
  faqAnswer,
  tutorialReplay,
}

enum TutorialCardPlacement {
  topCenter,
  topLeft,
  topRight,
  centerLeft,
  centerRight,
  bottomLeft,
  bottomRight,
}

enum TutorialDemoSidePanel {
  defaultView,
  thread,
}

class TutorialSceneSpec {
  const TutorialSceneSpec({
    this.roomId = DemoClient.demoLoungeRoomId,
    this.initialSpaceId = DemoClient.demoSpaceId,
    this.settingsSurface,
    this.overlay,
    this.sidePanel,
    this.sidePanelThreadId,
    this.focus,
    this.cardPlacement = TutorialCardPlacement.bottomRight,
    this.hideTutorialCard = false,
    this.autoAdvanceAfter,
  });

  final String roomId;
  final String? initialSpaceId;
  final TutorialDemoSettingsSurface? settingsSurface;
  final TutorialDemoOverlay? overlay;
  final TutorialDemoSidePanel? sidePanel;
  final String? sidePanelThreadId;
  final TutorialFocusSpec? focus;
  final TutorialCardPlacement cardPlacement;
  final bool hideTutorialCard;
  final Duration? autoAdvanceAfter;
}

const TutorialSceneSpec defaultTutorialScene = TutorialSceneSpec();

TutorialSceneSpec tutorialSceneForStep(String id) =>
    tutorialSceneSpecs[id] ?? defaultTutorialScene;

const TutorialFocusSpec _spaceRailFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 70,
  height: 560,
  anchorId: TutorialAnchorIds.spaceRail,
  anchorPadding: EdgeInsets.all(4),
  left: 0,
  top: 4,
  bottom: 64,
  radius: 20,
  arrowDirection: TutorialArrowDirection.left,
);

const TutorialFocusSpec _roomListFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 250,
  height: 560,
  anchorId: TutorialAnchorIds.roomList,
  anchorPadding: EdgeInsets.all(4),
  left: 70,
  top: 4,
  bottom: 64,
  arrowDirection: TutorialArrowDirection.left,
);

const TutorialFocusSpec _composerFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 720,
  height: 62,
  anchorId: TutorialAnchorIds.composer,
  anchorPadding: EdgeInsets.fromLTRB(4, 4, 4, 8),
  left: 332,
  right: 18,
  bottom: 12,
  radius: 18,
  arrowDirection: TutorialArrowDirection.down,
);

const TutorialFocusSpec _composerPopupFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 430,
  height: 352,
  anchorId: TutorialAnchorIds.composerPopup,
  anchorPadding: EdgeInsets.all(4),
  left: 334,
  bottom: 82,
  arrowDirection: TutorialArrowDirection.down,
);

const TutorialFocusSpec _effectsMenuFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 292,
  height: 260,
  anchorId: TutorialAnchorIds.effectsMenu,
  anchorPadding: EdgeInsets.all(4),
  right: 220,
  bottom: 82,
  arrowDirection: TutorialArrowDirection.down,
);

const TutorialFocusSpec _timelineEffectFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 720,
  height: 420,
  anchorId: TutorialAnchorIds.timeline,
  anchorPadding: EdgeInsets.all(4),
  left: 332,
  right: 18,
  top: 70,
  bottom: 86,
  arrowDirection: TutorialArrowDirection.right,
);

const TutorialFocusSpec _roomSidePanelFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 320,
  height: 620,
  anchorId: TutorialAnchorIds.roomSidePanel,
  anchorPadding: EdgeInsets.fromLTRB(4, 4, 0, 4),
  right: 0,
  top: 62,
  bottom: 0,
  arrowDirection: TutorialArrowDirection.right,
);

const TutorialFocusSpec _homeRailFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 62,
  height: 62,
  left: 4,
  top: 8,
  radius: 31,
  arrowDirection: TutorialArrowDirection.left,
);

const TutorialFocusSpec _emoticonHeartFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 86,
  height: 86,
  anchorId: TutorialAnchorIds.emoticonHeart,
  anchorPadding: EdgeInsets.all(6),
  right: 118,
  top: 168,
  radius: 18,
  arrowDirection: TutorialArrowDirection.right,
);

const TutorialFocusSpec _activityCardFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 326,
  height: 78,
  anchorId: TutorialAnchorIds.activityCard,
  anchorPadding: EdgeInsets.all(6),
  left: 8,
  bottom: 72,
  arrowDirection: TutorialArrowDirection.down,
);

const TutorialFocusSpec _accountPopupFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 376,
  height: 530,
  anchorId: TutorialAnchorIds.accountPopup,
  anchorPadding: EdgeInsets.all(6),
  left: 2,
  bottom: 68,
  arrowDirection: TutorialArrowDirection.down,
);

const TutorialFocusSpec _soundboardPopupFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 344,
  height: 420,
  anchorId: TutorialAnchorIds.soundboardPopup,
  anchorPadding: EdgeInsets.all(6),
  left: 74,
  bottom: 88,
  arrowDirection: TutorialArrowDirection.down,
);

const TutorialFocusSpec _companionFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 568,
  height: 548,
  anchorId: TutorialAnchorIds.companionPreview,
  anchorPadding: EdgeInsets.all(14),
  arrowDirection: TutorialArrowDirection.up,
);

const TutorialFocusSpec _callPopoutButtonFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 64,
  height: 64,
  anchorId: TutorialAnchorIds.callPopoutButton,
  anchorPadding: EdgeInsets.all(8),
  bottom: 152,
  radius: 18,
  arrowDirection: TutorialArrowDirection.right,
);

const TutorialFocusSpec _securityVerifyFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 260,
  height: 82,
  anchorId: TutorialAnchorIds.securityVerify,
  anchorPadding: EdgeInsets.all(6),
  right: 98,
  top: 168,
  arrowDirection: TutorialArrowDirection.right,
);

const TutorialFocusSpec _securityDecryptionFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 300,
  height: 82,
  anchorId: TutorialAnchorIds.securityDecryption,
  anchorPadding: EdgeInsets.all(6),
  right: 98,
  top: 266,
  arrowDirection: TutorialArrowDirection.right,
);

const TutorialFocusSpec _securitySessionsFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 520,
  height: 166,
  anchorId: TutorialAnchorIds.securitySessions,
  anchorPadding: EdgeInsets.all(6),
  right: 72,
  top: 348,
  arrowDirection: TutorialArrowDirection.right,
);

const TutorialFocusSpec _encryptedRoomPadlockFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 56,
  height: 56,
  anchorId: TutorialAnchorIds.encryptedRoomPadlock,
  anchorPadding: EdgeInsets.all(8),
  right: 314,
  top: 78,
  radius: 16,
  arrowDirection: TutorialArrowDirection.right,
);

const TutorialFocusSpec _tutorialReplayButtonFocus = TutorialFocusSpec(
  alignment: Alignment.center,
  width: 190,
  height: 56,
  anchorId: TutorialAnchorIds.tutorialReplayButton,
  anchorPadding: EdgeInsets.all(6),
  left: 890,
  top: 440,
  radius: 16,
  arrowDirection: TutorialArrowDirection.right,
);

const Map<String, TutorialSceneSpec> tutorialSceneSpecs = {
  'welcome-1': TutorialSceneSpec(
    cardPlacement: TutorialCardPlacement.topCenter,
  ),
  'spaces-1': TutorialSceneSpec(
    overlay: TutorialDemoOverlay.spaceRail,
    focus: _spaceRailFocus,
    cardPlacement: TutorialCardPlacement.topCenter,
  ),
  'spaces-2': TutorialSceneSpec(
    overlay: TutorialDemoOverlay.spaceRail,
    focus: _spaceRailFocus,
    cardPlacement: TutorialCardPlacement.topCenter,
  ),
  'rooms-1': TutorialSceneSpec(
    overlay: TutorialDemoOverlay.roomList,
    focus: _roomListFocus,
    cardPlacement: TutorialCardPlacement.topCenter,
  ),
  'rooms-chat': TutorialSceneSpec(
    roomId: DemoClient.demoLoungeRoomId,
    cardPlacement: TutorialCardPlacement.topRight,
  ),
  'rooms-forum': TutorialSceneSpec(
    roomId: DemoClient.demoForumRoomId,
    cardPlacement: TutorialCardPlacement.topRight,
  ),
  'rooms-photo': TutorialSceneSpec(
    roomId: DemoClient.demoPhotoAlbumRoomId,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'rooms-calendar': TutorialSceneSpec(
    roomId: DemoClient.demoCalendarRoomId,
    cardPlacement: TutorialCardPlacement.topRight,
  ),
  'rooms-voice': TutorialSceneSpec(
    roomId: DemoClient.demoVoiceRoomId,
    cardPlacement: TutorialCardPlacement.topRight,
  ),
  'rooms-dms': TutorialSceneSpec(
    initialSpaceId: null,
    roomId: DemoClient.demoMiraDmRoomId,
    overlay: TutorialDemoOverlay.spaceRail,
    focus: _homeRailFocus,
    cardPlacement: TutorialCardPlacement.topCenter,
  ),
  'messaging-1': TutorialSceneSpec(
    overlay: TutorialDemoOverlay.composer,
    focus: _composerFocus,
    cardPlacement: TutorialCardPlacement.topCenter,
  ),
  'messaging-menus': TutorialSceneSpec(
    overlay: TutorialDemoOverlay.mediaMenuCycle,
    focus: _composerPopupFocus,
    cardPlacement: TutorialCardPlacement.topCenter,
  ),
  'messaging-effects-intro': TutorialSceneSpec(
    overlay: TutorialDemoOverlay.effectsMenu,
    focus: _effectsMenuFocus,
    cardPlacement: TutorialCardPlacement.topRight,
  ),
  'messaging-effects-demo': TutorialSceneSpec(
    overlay: TutorialDemoOverlay.snowEffect,
    focus: _timelineEffectFocus,
    cardPlacement: TutorialCardPlacement.topRight,
  ),
  'messaging-nicknames': TutorialSceneSpec(
    overlay: TutorialDemoOverlay.membersNicknames,
    sidePanel: TutorialDemoSidePanel.defaultView,
    focus: _roomSidePanelFocus,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'emoticons-room': TutorialSceneSpec(
    roomId: DemoClient.demoLoungeRoomId,
    settingsSurface: TutorialDemoSettingsSurface.roomEmoticons,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'emoticons-heart': TutorialSceneSpec(
    roomId: DemoClient.demoLoungeRoomId,
    settingsSurface: TutorialDemoSettingsSurface.roomEmoticons,
    focus: _emoticonHeartFocus,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'emoticons-app': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.appEmoticons,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'calls-settings': TutorialSceneSpec(
    roomId: DemoClient.demoVoiceRoomId,
    settingsSurface: TutorialDemoSettingsSurface.appVoiceAndVideo,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'calls-controls': TutorialSceneSpec(
    roomId: DemoClient.demoVoiceRoomId,
    overlay: TutorialDemoOverlay.callMemberControls,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'calls-popout': TutorialSceneSpec(
    roomId: DemoClient.demoVoiceRoomId,
    overlay: TutorialDemoOverlay.callPopout,
    focus: _callPopoutButtonFocus,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'soundboard-popup': TutorialSceneSpec(
    roomId: DemoClient.demoVoiceRoomId,
    overlay: TutorialDemoOverlay.soundboardPopup,
    focus: _soundboardPopupFocus,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'soundboard-space': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.spaceSoundboard,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'soundboard-app': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.appSoundboard,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'notifications-settings': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.appNotifications,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'notifications-overrides': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.appNotifications,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'desktop-companion-settings': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.appDesktopCompanion,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'desktop-companion-animation': TutorialSceneSpec(
    overlay: TutorialDemoOverlay.companionAnimation,
    focus: _companionFocus,
    cardPlacement: TutorialCardPlacement.bottomLeft,
  ),
  'desktop-companion-active': TutorialSceneSpec(
    overlay: TutorialDemoOverlay.companionActiveNotification,
    focus: _companionFocus,
    cardPlacement: TutorialCardPlacement.bottomLeft,
  ),
  'desktop-companion-neutral': TutorialSceneSpec(
    overlay: TutorialDemoOverlay.companionNeutral,
    focus: _companionFocus,
    cardPlacement: TutorialCardPlacement.bottomLeft,
  ),
  'customization-appearance': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.appAppearance,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'customization-room': TutorialSceneSpec(
    roomId: DemoClient.demoLoungeRoomId,
    settingsSurface: TutorialDemoSettingsSurface.roomAppearance,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'customization-theme-editor': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.themeEditor,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'activity-settings': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.appActivity,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'activity-card': TutorialSceneSpec(
    focus: _activityCardFocus,
    cardPlacement: TutorialCardPlacement.topRight,
  ),
  'account-quick-access': TutorialSceneSpec(
    overlay: TutorialDemoOverlay.accountPopup,
    focus: _accountPopupFocus,
    cardPlacement: TutorialCardPlacement.topRight,
  ),
  'privacy-default': TutorialSceneSpec(
    roomId: DemoClient.demoEncryptedRoomId,
    cardPlacement: TutorialCardPlacement.topRight,
  ),
  'privacy-security-settings': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.accountSecurity,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'privacy-verify': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.accountSecurity,
    focus: _securityVerifyFocus,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'privacy-decryption': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.accountSecurity,
    focus: _securityDecryptionFocus,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'privacy-sessions': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.accountSecurity,
    focus: _securitySessionsFocus,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'privacy-padlock': TutorialSceneSpec(
    roomId: DemoClient.demoEncryptedRoomId,
    sidePanel: TutorialDemoSidePanel.defaultView,
    focus: _encryptedRoomPadlockFocus,
    cardPlacement: TutorialCardPlacement.bottomLeft,
  ),
  'help-safety': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.helpSafety,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'help-report-bug': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.helpReportBug,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'help-faq': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.helpFaq,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
  'help-tutorial': TutorialSceneSpec(
    settingsSurface: TutorialDemoSettingsSurface.helpTutorial,
    overlay: TutorialDemoOverlay.tutorialReplay,
    focus: _tutorialReplayButtonFocus,
    cardPlacement: TutorialCardPlacement.topLeft,
  ),
};
