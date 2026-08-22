import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';

/// A globally enabled pack resolved against the source space that owns it.
///
/// [pack] and [sounds] are null when the source is no longer readable — the
/// space was left, the pack was deleted or disabled, or the reference simply
/// names something that no longer exists. Callers must treat an unresolved
/// entry as unusable rather than falling back to the reference alone: the
/// source space is the authority for whether these sounds may be played.
class SoundboardGlobalPackEntry {
  const SoundboardGlobalPackEntry({
    required this.reference,
    this.sourceSpaceName,
    this.pack,
    this.sounds = const [],
  });

  final SoundboardGlobalPackReference reference;
  final String? sourceSpaceName;
  final SoundboardPack? pack;
  final List<SoundboardSound> sounds;

  /// True when the source space, pack, and its sounds are all currently
  /// readable, so the entry can be offered for playback.
  bool get isResolved => pack != null;

  /// True when the reference points at something this account can no longer
  /// use. Stale entries stay visible (so the member can see why a pack
  /// disappeared) but are excluded from playback and pruned in the background.
  bool get isStale => !isResolved;
}

/// The account-global soundboard library: the source packs a member has
/// enabled for use beyond the space that owns them (U5).
///
/// This is a client-level component, not a space-level one — the document is
/// account data and its contents span every space the account has joined.
/// It stores references only; sounds are never copied out of their source
/// space, so revoking access in the source revokes it everywhere.
abstract class SoundboardLibraryComponent<T extends Client>
    extends Component<T> {
  SoundboardLibraryComponent(super.client);

  /// Emits whenever the reference document or a resolved source changes.
  Stream<void> get onChanged;

  /// Every reference in the document, resolved against its source space where
  /// that is still possible. Includes stale entries — filter on [
  /// SoundboardGlobalPackEntry.isResolved] for anything playable.
  List<SoundboardGlobalPackEntry> get entries;

  /// The resolved, currently usable entries.
  List<SoundboardGlobalPackEntry> get usableEntries =>
      entries.where((entry) => entry.isResolved).toList(growable: false);

  bool isEnabled(String sourceSpaceId, String packId);

  /// Whether this account can enable [packId] from [sourceSpaceId] — it must
  /// be able to read the source pack today. Enabling something it cannot read
  /// would write a reference that is stale the moment it lands.
  bool canEnable(String sourceSpaceId, String packId);

  Future<void> enablePack(String sourceSpaceId, String packId);

  Future<void> disablePack(String sourceSpaceId, String packId);

  /// Drops references whose source is gone. Best-effort: a failed prune leaves
  /// the document untouched and the entries merely stale, never half-written.
  Future<void> pruneStaleReferences();
}
