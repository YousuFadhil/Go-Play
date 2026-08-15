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
    required this.fullName,
    required this.status,
    required this.registrationOrder,
    this.userId,
    this.professionalGuestId,
    this.position,
  }) : assert(
          (userId == null) != (professionalGuestId == null),
          'A seat belongs to a registered user or to a Professional Guest, '
          'never to both and never to neither.',
        );

  /// Null when this seat belongs to a Professional Guest.
  final String? userId;

  /// Null when this seat belongs to a registered user.
  final String? professionalGuestId;

  /// The participant's own name, without the Professional Guest wording.
  final String fullName;

  /// The profile's primary position. Null for a guest, who has no profile —
  /// not "unknown", but "there is none to read".
  final String? position;

  final RegistrationStatus status;
  final int registrationOrder;

  bool get isProfessionalGuest => professionalGuestId != null;

  /// Whichever identity this seat carries. Safe as a map key across both kinds,
  /// because a user id and a guest id are both uuids from disjoint tables.
  String get participantId => userId ?? professionalGuestId!;
}

/// Match lifecycle: open -> full (registration closed) -> back to open when a
/// slot frees. Completed is automatic once the scheduled end time passes.
enum MatchStatus { open, full, completed }

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
