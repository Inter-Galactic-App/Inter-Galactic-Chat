import 'package:flutter/painting.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/room_component.dart';

/// A forum post as modelled from a Matrix thread root event.
class ForumPost {
  /// The Matrix event ID of the thread root message.
  final String eventId;

  /// The post title, stored in `content['ig.forum.title']`.
  final String title;

  /// Short excerpt of the post body (the `body` field of the root event).
  final String excerpt;

  /// Optional media preview for sticker/image-backed forum roots.
  final ImageProvider? previewImage;

  /// Tags applied to this post, from `content['ig.forum.tags']`.
  final List<String> tags;

  /// The sender's Matrix user ID.
  final String senderId;

  /// Display name of the sender, if available.
  final String? senderDisplayName;

  /// Avatar of the sender, if available.
  final ImageProvider? senderAvatar;

  /// Number of replies in this thread.
  final int replyCount;

  /// Timestamp of the thread root event.
  final DateTime timestamp;

  /// Effective event content used when applying tag edits.
  final Map<String, Object?> editableContent;

  ForumPost({
    required this.eventId,
    required this.title,
    required this.excerpt,
    this.previewImage,
    required this.tags,
    required this.senderId,
    this.senderDisplayName,
    this.senderAvatar,
    required this.replyCount,
    required this.timestamp,
    required this.editableContent,
  });

  bool get hasMediaPreview => previewImage != null;
}

abstract class ForumRoomComponent<C extends Client, R extends Room>
    implements RoomComponent<C, R> {
  /// Available tags defined for this forum room.
  List<String> get availableTags;

  /// Stream that emits whenever the post list changes.
  Stream<void> get onPostsChanged;

  /// All known forum posts (thread roots), newest first.
  List<ForumPost> get posts;

  /// Whether the current user can create new posts.
  bool get canPost;

  /// Load the full forum timeline (thread roots). Call once on init.
  Future<void> loadPosts();

  /// Create a new forum post (sends a thread root event).
  Future<void> createPost({
    required String title,
    required String body,
    required List<String> tags,
  });

  /// Whether the current user can edit the tags on [post].
  /// True for the post's own author, or for users with moderation privileges.
  bool canEditTags(ForumPost post);

  /// Edit the tags on [post], replacing them with [newTags].
  /// Sends a Matrix edit event (m.replace relation) targeting [post.eventId].
  Future<void> editPostTags(ForumPost post, List<String> newTags);
}
