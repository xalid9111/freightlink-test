/// Maps 1:1 onto public.ratings.
class RatingModel {
  final String id;
  final String shipmentId;
  final String reviewerId;
  final String reviewedUserId;
  final int rating; // 1..5
  final String? comment;

  const RatingModel({
    required this.id,
    required this.shipmentId,
    required this.reviewerId,
    required this.reviewedUserId,
    required this.rating,
    this.comment,
  });

  factory RatingModel.fromJson(Map<String, dynamic> j) => RatingModel(
        id: j['id'] as String,
        shipmentId: j['shipment_id'] as String,
        reviewerId: j['reviewer_id'] as String,
        reviewedUserId: j['reviewed_user_id'] as String,
        rating: j['rating'] as int,
        comment: j['comment'] as String?,
      );

  Map<String, dynamic> toInsertJson() => {
        'shipment_id': shipmentId,
        'reviewer_id': reviewerId,
        'reviewed_user_id': reviewedUserId,
        'rating': rating,
        'comment': comment,
      };
}
