import 'package:flutter/material.dart';
import 'package:intergalactic/client/favorite_rooms.dart';

/// Runs a favourite membership or ordering write and tells the user when it
/// fails.
///
/// Favourites are server state now, so a write can fail. The one thing this
/// must not do is stay quiet: before the move to `m.favourite` tags a write
/// always "succeeded" locally, and silently keeping that behaviour would show
/// a removed favourite as gone while the server still had it.
Future<bool> runFavoriteWrite(
  BuildContext context,
  Future<FavoriteWriteResult> write,
) async {
  final result = await write;
  if (result == FavoriteWriteResult.applied) {
    return true;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't update Favorites. Check your connection and try again.",
        ),
      ),
    );
  }
  return false;
}
