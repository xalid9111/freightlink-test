/// Maps 1:1 onto public.ai_matches — persisted output of the Phase 11
/// Edge Function (see supabase/functions/ai-match).
class AiMatchModel {
  final String id;
  final String cargoId;
  final String carrierId;
  final String? truckId;
  final double matchScore; // 0..100
  final double? distanceToPickup;
  final double? estimatedDistance;
  final int? estimatedDurationMinutes;
  final double? estimatedEarnings;
  final List<String> matchingReasons;

  const AiMatchModel({
    required this.id,
    required this.cargoId,
    required this.carrierId,
    this.truckId,
    required this.matchScore,
    this.distanceToPickup,
    this.estimatedDistance,
    this.estimatedDurationMinutes,
    this.estimatedEarnings,
    this.matchingReasons = const [],
  });

  factory AiMatchModel.fromJson(Map<String, dynamic> j) => AiMatchModel(
        id: j['id'] as String,
        cargoId: j['cargo_id'] as String,
        carrierId: j['carrier_id'] as String,
        truckId: j['truck_id'] as String?,
        matchScore: (j['match_score'] as num).toDouble(),
        distanceToPickup: (j['distance_to_pickup'] as num?)?.toDouble(),
        estimatedDistance: (j['estimated_distance'] as num?)?.toDouble(),
        estimatedDurationMinutes: j['estimated_duration'] as int?,
        estimatedEarnings: (j['estimated_earnings'] as num?)?.toDouble(),
        matchingReasons: (j['matching_reasons'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}
