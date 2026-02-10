import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Phone authentication - sends OTP
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(PhoneAuthCredential credential)
        onVerificationCompleted,
    required void Function(FirebaseAuthException error) onVerificationFailed,
    required void Function(String verificationId) onCodeAutoRetrievalTimeout,
    int? resendToken,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: onVerificationCompleted,
      verificationFailed: onVerificationFailed,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: onCodeAutoRetrievalTimeout,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
    );
  }

  // Verify OTP and sign in
  Future<UserCredential> verifyOTP({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return await _auth.signInWithCredential(credential);
  }

  // Email/Password sign in (enterprise admin)
  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // Get custom claims from the current user's ID token
  Future<Map<String, dynamic>?> getUserClaims() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final idTokenResult = await user.getIdTokenResult(true);
    return idTokenResult.claims;
  }

  // Get user roles from custom claims (multi-role)
  Future<List<String>?> getUserRoles() async {
    final claims = await getUserClaims();
    if (claims?['roles'] != null) {
      return List<String>.from(claims!['roles']);
    }
    // Backward compat: single role claim
    final role = claims?['role'] as String?;
    return role != null ? [role] : null;
  }

  // Get active role from custom claims
  Future<String?> getActiveRole() async {
    final claims = await getUserClaims();
    return claims?['activeRole'] as String? ?? claims?['role'] as String?;
  }

  // Backward compat alias
  Future<String?> getUserRole() async => getActiveRole();

  // Get enterprise ID from custom claims
  Future<String?> getEnterpriseId() async {
    final claims = await getUserClaims();
    return claims?['enterpriseId'] as String?;
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Check if user is signed in
  bool get isSignedIn => _auth.currentUser != null;
}
