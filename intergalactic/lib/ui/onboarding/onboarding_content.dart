import 'package:flutter/material.dart';
import 'package:intergalactic/ui/onboarding/onboarding_step.dart';

const List<OnboardingStep> initialOnboardingSteps = [
  OnboardingStep(
    id: "welcome",
    title: "Welcome to Inter Galactic",
    body:
        "Welcome to Inter Galactic. This quick tour shows the main places you'll use every day.",
    icon: Icons.auto_awesome_outlined,
  ),
  OnboardingStep(
    id: "navigation",
    title: "Spaces and Servers",
    body:
        "Spaces group rooms together. Use the side rail to move between communities, favorites, and account areas.",
    icon: Icons.account_tree_outlined,
  ),
  OnboardingStep(
    id: "rooms",
    title: "Rooms and Direct Messages",
    body:
        "Rooms can be chats, forums, photo albums, calendars, or voice rooms. Direct messages live alongside rooms for one-to-one conversations.",
    icon: Icons.forum_outlined,
  ),
  OnboardingStep(
    id: "messaging",
    title: "Messages, Media, GIFs, and Reactions",
    body:
        "Send text, media, GIFs, stickers, and reactions from the composer. You can manage your own emoji and sticker packs from account or room emoji settings when permissions allow it.",
    icon: Icons.add_reaction_outlined,
  ),
  OnboardingStep(
    id: "calls",
    title: "Calls and Screen Sharing",
    body:
        "Voice/video rooms support calls and screen sharing. Screen-share behavior and call devices live in Voice and Video settings.",
    icon: Icons.video_call_outlined,
  ),
  OnboardingStep(
    id: "notifications",
    title: "Notifications",
    body:
        "Notification behavior can be tuned globally, per room, and per platform. Delivery still depends on your device and Matrix server setup.",
    icon: Icons.notifications_active_outlined,
  ),
  OnboardingStep(
    id: "privacy",
    title: "Privacy and Encryption",
    body:
        "Inter Galactic is a Matrix client. Messages may be end-to-end encrypted depending on room settings. Losing keys or devices can affect encrypted history recovery. Homeserver and account controls belong to the selected Matrix server.",
    icon: Icons.enhanced_encryption_outlined,
  ),
  OnboardingStep(
    id: "activity",
    title: "Activity and Presence",
    body:
        "Presence and activity features can show local media, Spotify, games, or basic status only when you enable them.",
    icon: Icons.sensors_outlined,
  ),
  OnboardingStep(
    id: "appearance",
    title: "Customization Settings",
    body:
        "Customize themes, bubbles, backgrounds, notification sounds, and room-level appearance from Settings.",
    icon: Icons.palette_outlined,
  ),
  OnboardingStep(
    id: "support",
    title: "Support",
    body:
        "You can replay this tutorial later from Settings > Help > Tutorial. For app support, use the Help & Safety page and the current Inter Galactic contact listed there.",
    icon: Icons.support_agent_outlined,
    primaryActionLabel: "Finish",
  ),
];
