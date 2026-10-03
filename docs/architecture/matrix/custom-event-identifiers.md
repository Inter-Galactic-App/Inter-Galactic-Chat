# Custom Matrix Event Identifiers

For newly introduced Inter Galactic-owned custom event types, use stable,
reverse-DNS-style identifiers under the `chat.intergalactic` namespace. This
identifies the application that owns the new event without implying that it is
part of the Matrix specification. This convention does not rename existing
wire identifiers.

## Convention

- Use `chat.intergalactic.<feature>.<purpose>` for app-private event types.
- Preserve established `chat.commet.*` wire identifiers, including event types
  and namespaced content keys. Do not rename them solely to match this
  convention; deployed rooms and other clients may depend on those exact names.
- Keep the event type stable while its content can be read compatibly.
- Add a `schema_version` field to event content only when readers need to
  distinguish incompatible content shapes. Do not version every event by
  default or encode a content version in the event type.
- For an incompatible contract that must coexist with the old one, define an
  explicit migration and read/write policy before introducing another event
  type.
- A deliberate legacy-identifier migration requires its own compatibility
  plan, including reader support and the write transition; this convention
  alone is not authorization to migrate existing data or wire names.
- Do not invent private identifiers under `org.matrix.mscNNNN`. For actual
  MSC interoperability, use the identifier and transition behavior specified
  by that proposal and the applicable Matrix specification.

The current Space category state event, `chat.intergalactic.space.categories`,
uses one stable event type and has no content schema version. Its content
contract is documented in [Space room categories](space-room-categories.md).

Matrix custom event types should be namespaced using a Java-package-style
convention. Event content remains untrusted input and must be validated by the
consumer; see the [Matrix Client-Server API](https://spec.matrix.org/unstable/client-server-api/#types-of-room-events).
