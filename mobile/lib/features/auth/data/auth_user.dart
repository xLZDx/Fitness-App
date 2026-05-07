/// A user identity surfaced by an [AuthRepository].
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.displayName,
    this.email,
    this.photoUrl,
    this.provider = AuthProvider.anonymous,
  });

  final String uid;
  final String displayName;
  final String? email;
  final String? photoUrl;
  final AuthProvider provider;

  AuthUser copyWith({
    String? displayName,
    String? email,
    String? photoUrl,
  }) =>
      AuthUser(
        uid: uid,
        displayName: displayName ?? this.displayName,
        email: email ?? this.email,
        photoUrl: photoUrl ?? this.photoUrl,
        provider: provider,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          other.uid == uid &&
          other.displayName == displayName &&
          other.email == email &&
          other.photoUrl == photoUrl &&
          other.provider == provider;

  @override
  int get hashCode => Object.hash(uid, displayName, email, photoUrl, provider);
}

enum AuthProvider { anonymous, google, email }
