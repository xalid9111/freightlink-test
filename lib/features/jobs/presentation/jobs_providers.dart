import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_providers.dart';
import '../data/jobs_repository.dart';
import '../domain/job_models.dart';

final jobsRepositoryProvider = Provider<JobsRepository>((ref) => JobsRepository());

/// The catalogues from the server; the 0069 lists until they load.
final jobSpecialtiesProvider = FutureProvider.autoDispose<List<JobCatalogItem>>((ref) async {
  try {
    final l = await ref.watch(jobsRepositoryProvider).specialties();
    return l.isEmpty ? kJobSpecialties : l;
  } catch (_) {
    return kJobSpecialties;
  }
});

final jobSkillsProvider = FutureProvider.autoDispose<List<JobCatalogItem>>((ref) async {
  try {
    final l = await ref.watch(jobsRepositoryProvider).skills();
    return l.isEmpty ? kJobSkills : l;
  } catch (_) {
    return kJobSkills;
  }
});

final myJobProfileProvider = FutureProvider.autoDispose<JobSeeker?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(jobsRepositoryProvider).myProfile();
});

final myVacanciesProvider = FutureProvider.autoDispose<List<JobVacancy>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(jobsRepositoryProvider).myVacancies();
});

final jobSeekersProvider = FutureProvider.autoDispose<List<JobSeeker>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(jobsRepositoryProvider).seekers();
});

final jobVacanciesProvider = FutureProvider.autoDispose<List<JobVacancy>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(jobsRepositoryProvider).vacancies();
});
