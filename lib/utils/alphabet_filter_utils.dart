import '../models/user_model.dart';

/// Sort a list of [UserModel] alphabetically by name.
/// When [ascending] is true, sorts A→Z; when false, sorts Z→A.
List<UserModel> sortUsersByName(List<UserModel> users, bool ascending) {
  final sorted = List<UserModel>.of(users);
  sorted.sort((a, b) => ascending
      ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
      : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
  return sorted;
}
