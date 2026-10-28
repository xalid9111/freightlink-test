// İş Mərkəzi PR 2 (owner, 28.10.2026): applications ("Müraciət et") and
// job offers ("İş təklif et"), their statuses and the job notices. The
// rules are the server's (0069: job_application_send /
// job_application_set_status — hired only when BOTH sides confirm); this
// file only decides what to show. Unit-tested in
// test/job_applications_test.dart.

/// What a user can do with an application now.
enum JobAppAction { talk, accept, reject, withdraw, close }

class JobApplication {
  final String id;
  final String vacancyId;
  final String seekerId;
  final String employerId;

  /// 'seeker' = the driver applied; 'employer' = the employer offered.
  final String initiatedBy;

  /// sent · seen · talking · accepted · rejected · closed
  final String status;
  final bool seekerOk, employerOk;
  final String? message;
  final DateTime? updatedAt;

  const JobApplication({
    required this.id,
    required this.vacancyId,
    required this.seekerId,
    required this.employerId,
    required this.initiatedBy,
    required this.status,
    this.seekerOk = false,
    this.employerOk = false,
    this.message,
    this.updatedAt,
  });

  factory JobApplication.fromJson(Map<String, dynamic> j) => JobApplication(
        id: '${j['id']}',
        vacancyId: '${j['vacancy_id']}',
        seekerId: '${j['seeker_id']}',
        employerId: '${j['employer_id']}',
        initiatedBy: j['initiated_by'] == 'employer' ? 'employer' : 'seeker',
        status: '${j['status'] ?? 'sent'}',
        seekerOk: j['seeker_ok'] == true,
        employerOk: j['employer_ok'] == true,
        message: (j['message'] as String?)?.trim().isEmpty ?? true ? null : (j['message'] as String).trim(),
        updatedAt: j['updated_at'] == null ? null : DateTime.tryParse('${j['updated_at']}'),
      );

  /// My side in it ('seeker' or 'employer').
  String sideOf(String uid) => uid == seekerId ? 'seeker' : 'employer';

  /// The other person.
  String otherOf(String uid) => uid == seekerId ? employerId : seekerId;

  /// It came to me (I did not start it).
  bool incomingFor(String uid) => initiatedBy != sideOf(uid);

  bool get isFinal => status == 'rejected' || status == 'closed';
  bool get isOpen => !isFinal;

  bool confirmedBy(String side) => side == 'seeker' ? seekerOk : employerOk;

  /// The buttons, by the server's rules.
  List<JobAppAction> actionsFor(String uid) {
    if (isFinal) return const [];
    if (status == 'accepted') return const [JobAppAction.close];
    final mine = confirmedBy(sideOf(uid));
    final incoming = incomingFor(uid);
    if (status == 'sent' || status == 'seen') {
      return incoming
          ? const [JobAppAction.talk, JobAppAction.accept, JobAppAction.reject]
          : [if (!mine) JobAppAction.accept, JobAppAction.withdraw];
    }
    // talking
    return [if (!mine) JobAppAction.accept, JobAppAction.reject, JobAppAction.close];
  }

  /// The status sent to the server for an action.
  static String statusFor(JobAppAction a) => switch (a) {
        JobAppAction.talk => 'talking',
        JobAppAction.accept => 'accepted',
        JobAppAction.reject => 'rejected',
        JobAppAction.withdraw => 'closed',
        JobAppAction.close => 'closed',
      };

  /// "I confirmed — waiting for the other side" / "The other side
  /// confirmed — your turn" (only while not hired yet).
  String? waitingNoteFor(String uid) {
    if (status == 'accepted' || isFinal) return null;
    final me = sideOf(uid), other = me == 'seeker' ? 'employer' : 'seeker';
    if (confirmedBy(me) && !confirmedBy(other)) return 'job_app_wait_other';
    if (!confirmedBy(me) && confirmedBy(other)) return 'job_app_wait_me';
    return null;
  }
}

/// The application of one driver to one vacancy (one row per pair).
JobApplication? jobApplicationFor(List<JobApplication> list, {required String vacancyId, required String seekerId}) =>
    list.where((a) => a.vacancyId == vacancyId && a.seekerId == seekerId).firstOrNull;

/// Open ones first, then the newest.
List<JobApplication> sortApplications(List<JobApplication> list) {
  final out = [...list];
  out.sort((a, b) {
    final f = (a.isFinal ? 1 : 0) - (b.isFinal ? 1 : 0);
    if (f != 0) return f;
    final ua = a.updatedAt, ub = b.updatedAt;
    if (ua != null && ub != null) return ub.compareTo(ua);
    return 0;
  });
  return out;
}

/// The job types of the existing notifications table (0069).
const kJobNoticeTypes = ['job_application', 'job_match_vacancy', 'job_match_seeker'];

/// One job notice.
class JobNotice {
  final String id;
  final String type;
  final String title;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? createdAt;
  const JobNotice({required this.id, required this.type, required this.title, this.data = const {}, this.isRead = false, this.createdAt});

  factory JobNotice.fromJson(Map<String, dynamic> j) => JobNotice(
        id: '${j['id']}',
        type: '${j['type']}',
        title: '${j['title'] ?? ''}',
        data: Map<String, dynamic>.from((j['data'] as Map?) ?? const {}),
        isRead: j['is_read'] == true,
        createdAt: j['created_at'] == null ? null : DateTime.tryParse('${j['created_at']}'),
      );

  /// The text key in the user's language (the server stores Azerbaijani).
  String get textKey {
    switch (type) {
      case 'job_match_vacancy':
        return 'job_ntf_match_vacancy';
      case 'job_match_seeker':
        return 'job_ntf_match_seeker';
    }
    return switch (title) {
      'Yeni müraciət' => 'job_ntf_new_app',
      'Yeni iş təklifi' => 'job_ntf_new_offer',
      'İşə qəbul təsdiqləndi' => 'job_ntf_accepted',
      'Müraciət rədd edildi' => 'job_ntf_rejected',
      'Müraciət bağlandı' => 'job_ntf_closed',
      _ => 'job_ntf_update',
    };
  }

  /// Where a tap goes.
  String get route => switch (type) {
        'job_match_vacancy' when data['vacancy_id'] != null => '/jobs/v/${data['vacancy_id']}',
        'job_match_seeker' when data['seeker_id'] != null => '/jobs/d/${data['seeker_id']}',
        _ => '/jobs/applications',
      };
}
