import '../communities/community_models.dart';

/// A seat in a match: a starting place, or a place in the reserve queue.
enum RegistrationStatus { confirmed, reserve }

/// Why a match could not be read, when the reason is who the reader is.
///
/// A match belongs to a community and only its members may read it, so a
/// non-member's read comes back with nothing at all — the same nothing a
/// mistyped id produces. This is the answer to which of the two happened, and
/// it carries no match data: whether the id names a match, which community it
/// belongs to, how that community is joined, and whether the reader is in it.
///
/// The community's name and its join policy are not a disclosure — migration
/// `0033` already publishes every active community to signed-out visitors. What
/// stays behind the policy is the match itself, and nothing here reveals any of
/// it.
class MatchAccessContext {
  const MatchAccessContext({
    required this.matchExists,
    required this.isMember,
    this.communityId,
    this.communityName,
    this.joinPolicy,
  });

  /// Whether the id names a match at all. False makes every other field null or
  /// false: there is no community to name.
  final bool matchExists;

  /// Whether the reader belongs to the match's community.
  final bool isMember;

  final String? communityId;
  final String? communityName;

  /// How the community is joined, so the join flow can ask for a code without a
  /// round trip that is certain to be refused.
  final JoinPolicy? joinPolicy;

  /// The one case this type exists for: the match is there, and the reader is
  /// not in the community that holds it.
  bool get membershipRequired =>
      matchExists && !isMember && communityId != null;
}

/// A seat in a match: a registered community player, or a Professional Guest.
///
/// A Professional Guest is **match-scoped**. They have no account, no
/// membership and no profile, which is why [userId] and [position] are null for
/// one and why nothing here reaches for a profile they do not have. The two
/// identities are exclusive — exactly one of [userId] and [professionalGuestId]
/// is set, which is the same rule the database states as a CHECK constraint.
///
/// Their name is carried in [fullName] unadorned. The approved presentation —
/// "محترف (الاسم)" — is a localized sentence, selected at render time, so that
/// the two never disagree and the label is right in either language.
class MatchRegistration {
  const MatchRegistration({
    required this.registrationId,
    required this.fullName,
    required this.status,
    required this.registrationOrder,
    this.userId,
    this.professionalGuestId,
    this.position,
    this.adminOrder,
    this.avatarUrl,
  }) : assert(
          (userId == null) != (professionalGuestId == null),
          'A seat belongs to a registered user or to a Professional Guest, '
          'never to both and never to neither.',
        );

  /// The seat itself, which is what an administrative roster operation names.
  ///
  /// Deliberately not [participantId]: an arrangement is over seats, and a seat
  /// is one row whichever kind of participant holds it. Naming a user or a
  /// guest instead would make every operation carry which of the two it meant,
  /// and the whole point of the single participant order is that it does not
  /// have to.
  final String registrationId;

  /// Null when this seat belongs to a Professional Guest.
  final String? userId;

  /// Null when this seat belongs to a registered user.
  final String? professionalGuestId;

  /// The participant's own name, without the Professional Guest wording.
  final String fullName;

  /// The profile's primary position. Null for a guest, who has no profile —
  /// not "unknown", but "there is none to read".
  final String? position;

  /// Where this player's picture is, when they have set one.
  ///
  /// Always null for a Professional Guest, and that is a rule rather than a
  /// coincidence: a guest has no account, so there is no picture of theirs to
  /// show and no other player's that may stand in for it.
  final String? avatarUrl;

  final RegistrationStatus status;
  final int registrationOrder;

  /// This seat's place in the owner/admin arrangement, or null while the match
  /// is still in its default registration order.
  ///
  /// Read for one purpose only: telling the reader that a match *has* been
  /// arranged. It is never a sort key here — the list arrives in the
  /// authoritative order the server computed, and re-deriving that order in the
  /// client would be a second implementation of a rule that has one.
  final int? adminOrder;

  bool get isProfessionalGuest => professionalGuestId != null;

  /// Whichever identity this seat carries. Safe as a map key across both kinds,
  /// because a user id and a guest id are both uuids from disjoint tables.
  String get participantId => userId ?? professionalGuestId!;
}

/// Match lifecycle: open -> full (registration closed) -> back to open when a
/// slot frees. Completed is automatic once the scheduled end time passes.
enum MatchStatus { open, full, completed }

/// Which ordering decides who starts and who waits.
///
/// [registration] is the default and is derived: community players before
/// Professional Guests, each in arrival order. [manual] means an owner or admin
/// has arranged the roster, and the arrangement they stored is authoritative
/// from then on.
///
/// The move from [registration] to [manual] is one-way for the life of the
/// match — an administrator who later arranges the list back into arrival order
/// has arranged it, not reset it. The database refuses the reverse outright, so
/// nothing here has to decide whether a match "looks default" again.
enum RosterOrderMode { registration, manual }

/// A football match scheduled inside a community.
class Match {
  const Match({
    required this.id,
    required this.communityId,
    required this.createdBy,
    required this.location,
    required this.startAt,
    required this.endAt,
    required this.startingPlayers,
    required this.maxRegistration,
    required this.status,
    this.title,
    this.description,
    this.communityName,
    this.rosterOrderMode = RosterOrderMode.registration,
    this.isHistorical = false,
  });

  final String id;
  final String communityId;
  final String createdBy;
  final String location;
  final DateTime startAt;
  final DateTime endAt;

  /// The first [startingPlayers] registrations are starting players; the rest
  /// are reserve, up to [maxRegistration] where registration closes.
  final int startingPlayers;
  final int maxRegistration;
  final MatchStatus status;
  final String? title;
  final String? description;

  /// Present only when the query joins the community (e.g. Home screen).
  final String? communityName;

  /// Whether an owner or admin has arranged this match's roster. Shown to the
  /// organizer so an arrangement is a visible state and not a silent one; it
  /// governs no behaviour here, because the ordering it selects is applied
  /// server-side.
  final RosterOrderMode rosterOrderMode;

  /// Whether this match is the record of a fixture that had already been played
  /// when it was created (migration `0054`).
  ///
  /// It is the only kind of match whose times may be in the past, and it never
  /// takes a registration — `register_player_in_match` refuses one outright, so
  /// this governs no permission here. What it governs is what the reader is
  /// told: a match nobody could have joined should say so rather than look like
  /// an ordinary fixture whose roster stayed empty.
  final bool isHistorical;

  /// What to show as the match's headline: the title if set, else location.
  String get displayName =>
      (title != null && title!.isNotEmpty) ? title! : location;

  /// Completion is time-driven, so it is derived here as well as stored: a
  /// match whose end time has passed is completed even if the stored row has
  /// not been touched since.
  MatchStatus get effectiveStatus =>
      endAt.isAfter(DateTime.now()) ? status : MatchStatus.completed;

  bool get isCompleted => effectiveStatus == MatchStatus.completed;

  /// From the scheduled start until the end the match is locked: no
  /// registrations, withdrawals or organizer roster changes.
  bool get isLocked => !isCompleted && !startAt.isAfter(DateTime.now());

  /// True while players can still register or withdraw.
  bool get isOpenForChanges => !isCompleted && !isLocked;
}
