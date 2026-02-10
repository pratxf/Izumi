import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();

  AuthStatus _status = AuthStatus.initial;
  UserModel? _currentUser;
  List<String>? _roles;
  String? _activeRole;
  String? _enterpriseId;
  String? _errorMessage;
  String? _verificationId;
  int? _resendToken;

  // Pending registration data (set before OTP, consumed in _onAuthStateChanged)
  String? _pendingName;
  String? _pendingPhone;
  String? _pendingRole;

  StreamSubscription<User?>? _authSubscription;

  AuthStatus get status => _status;
  UserModel? get currentUser => _currentUser;
  List<String>? get roles => _roles;
  String? get activeRole => _activeRole;
  String? get enterpriseId => _enterpriseId;
  String? get errorMessage => _errorMessage;
  String? get verificationId => _verificationId;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isAdmin => _roles?.contains('admin') ?? false;
  bool get isTeamLead => _roles?.contains('team_lead') ?? false;
  bool get isEmployee => _roles?.contains('employee') ?? false;

  // Backward compat: expose role as activeRole
  String? get role => _activeRole;

  AuthProvider() {
    _init();
  }

  void _init() {
    _authSubscription = _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  /// Store registration data before OTP flow so _onAuthStateChanged
  /// can create the user doc even if the OTP screen gets popped by the router.
  void setPendingRegistration({
    required String name,
    required String phone,
    required String role,
  }) {
    _pendingName = name;
    _pendingPhone = phone;
    _pendingRole = role;
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      _currentUser = null;
      _roles = null;
      _activeRole = null;
      _enterpriseId = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    debugPrint('[AuthProvider] _onAuthStateChanged: uid=${firebaseUser.uid}');
    bool needsClaimsWait = false;

    // 1. Fetch custom claims
    try {
      final claims = await _authService.getUserClaims()
          .timeout(const Duration(seconds: 8));
      if (claims != null) {
        // Read new multi-role claims with fallback to old single role
        if (claims['roles'] != null) {
          _roles = List<String>.from(claims['roles']);
          _activeRole = claims['activeRole'] as String? ?? _roles!.first;
        } else if (claims['role'] != null) {
          _roles = [claims['role'] as String];
          _activeRole = claims['role'] as String;
        }
        final claimEnterprise = claims['enterpriseId'] as String?;
        if (claimEnterprise != null) _enterpriseId = claimEnterprise;
      }
    } catch (e) {
      debugPrint('[AuthProvider] Failed to fetch custom claims: $e');
    }

    // 2. Try to load /users/{uid} from Firestore
    try {
      DocumentSnapshot<Map<String, dynamic>> userDoc;
      try {
        userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(firebaseUser.uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        debugPrint('[AuthProvider] Server fetch timed out, trying cache...');
        userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(firebaseUser.uid)
            .get(const GetOptions(source: Source.cache));
      }

      if (userDoc.exists) {
        _currentUser = UserModel.fromFirestore(userDoc);
        _roles ??= _currentUser!.roles;
        _activeRole ??= _currentUser!.activeRole;
        _enterpriseId ??= _currentUser!.enterpriseId;
        debugPrint('[AuthProvider] User doc loaded: roles=$_roles, activeRole=$_activeRole, enterpriseId=$_enterpriseId');

        // If enterprise is placeholder, call resolveUserOnLogin to merge admin-created doc
        if (_enterpriseId == null || _enterpriseId == 'default_enterprise') {
          debugPrint('[AuthProvider] Placeholder enterprise detected, calling resolveUserOnLogin...');
          try {
            // Force-refresh token so Cloud Function gets a valid auth context
            await firebaseUser.getIdToken(true);
            final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
                .httpsCallable('resolveUserOnLogin');
            final result = await callable.call();
            final data = result.data as Map<String, dynamic>?;

            if (data != null && data['found'] == true && data['user'] != null) {
              final userData = Map<String, dynamic>.from(data['user']);
              final resolvedEnterprise = userData['enterpriseId'] as String?;
              // Only re-load if the function actually resolved a real enterprise
              if (resolvedEnterprise != null && resolvedEnterprise != 'default_enterprise') {
                debugPrint('[AuthProvider] Enterprise resolved: $resolvedEnterprise');
                final newDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(firebaseUser.uid)
                    .get();
                if (newDoc.exists) {
                  _currentUser = UserModel.fromFirestore(newDoc);
                  _roles = _currentUser!.roles;
                  _activeRole = _currentUser!.activeRole;
                  _enterpriseId = _currentUser!.enterpriseId;
                }
                needsClaimsWait = true;
              }
            }
          } catch (e) {
            debugPrint('[AuthProvider] resolveUserOnLogin (merge) failed: $e');
          }
        }
      } else {
        // 3. Call resolveUserOnLogin Cloud Function
        debugPrint('[AuthProvider] No user doc at UID, calling resolveUserOnLogin...');
        try {
          final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
              .httpsCallable('resolveUserOnLogin');
          final result = await callable.call();
          final data = result.data as Map<String, dynamic>?;

          if (data != null && data['found'] == true && data['user'] != null) {
            // User was resolved (migrated from pre-created doc)
            final userData = Map<String, dynamic>.from(data['user']);
            debugPrint('[AuthProvider] resolveUserOnLogin found user, loading...');

            // Re-fetch the doc (now at UID path)
            final newDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(firebaseUser.uid)
                .get();
            if (newDoc.exists) {
              _currentUser = UserModel.fromFirestore(newDoc);
              _roles = _currentUser!.roles;
              _activeRole = _currentUser!.activeRole;
              _enterpriseId = _currentUser!.enterpriseId;
            } else {
              // Fallback: build from returned data
              _roles = userData['roles'] != null
                  ? List<String>.from(userData['roles'])
                  : [userData['role'] ?? 'employee'];
              _activeRole = userData['activeRole'] as String? ?? userData['role'] as String? ?? 'employee';
              _enterpriseId = userData['enterpriseId'] as String?;
            }
            needsClaimsWait = true;
          } else {
            // User is new — no pre-created doc found
            debugPrint('[AuthProvider] resolveUserOnLogin: new user');
          }
        } catch (e) {
          debugPrint('[AuthProvider] resolveUserOnLogin failed: $e');
        }

        // 4. If new user AND _pendingRegistration exists → create user doc
        if (_currentUser == null && _pendingName != null) {
          debugPrint('[AuthProvider] No user doc found, creating from pending registration...');
          final now = DateTime.now();
          final pendingRole = _pendingRole ?? 'employee';
          final userModel = UserModel(
            id: firebaseUser.uid,
            name: _pendingName!,
            phone: _pendingPhone ?? firebaseUser.phoneNumber ?? '',
            roles: [pendingRole],
            activeRole: pendingRole,
            enterpriseId: 'default_enterprise',
            createdAt: now,
            updatedAt: now,
          );

          await FirebaseFirestore.instance
              .collection('users')
              .doc(firebaseUser.uid)
              .set(userModel.toFirestore());

          _currentUser = userModel;
          _roles = userModel.roles;
          _activeRole = userModel.activeRole;
          _enterpriseId = userModel.enterpriseId;
          debugPrint('[AuthProvider] User doc created: roles=$_roles, activeRole=$_activeRole');
          needsClaimsWait = true;
        } else if (_currentUser == null && firebaseUser.email != null) {
          // Enterprise admin (email auth) — auto-create Firestore user doc
          debugPrint('[AuthProvider] Enterprise admin has no user doc, creating...');
          final now = DateTime.now();
          final userModel = UserModel(
            id: firebaseUser.uid,
            name: firebaseUser.displayName ??
                firebaseUser.email!.split('@').first,
            phone: firebaseUser.phoneNumber ?? '',
            email: firebaseUser.email,
            roles: ['admin'],
            activeRole: 'admin',
            enterpriseId: firebaseUser.uid,
            createdAt: now,
            updatedAt: now,
          );

          await FirebaseFirestore.instance
              .collection('users')
              .doc(firebaseUser.uid)
              .set(userModel.toFirestore());

          _currentUser = userModel;
          _roles = ['admin'];
          _activeRole = 'admin';
          _enterpriseId = userModel.enterpriseId;
          debugPrint('[AuthProvider] Enterprise admin doc created: enterpriseId=$_enterpriseId');
          needsClaimsWait = true;
        } else if (_currentUser == null) {
          debugPrint('[AuthProvider] No user doc and no pending registration data');
          if (_enterpriseId == null) {
            Future.delayed(const Duration(seconds: 2), () => _retryFetchUserDoc(firebaseUser));
          }
        }
      }
    } catch (e) {
      debugPrint('[AuthProvider] Failed to fetch/create user doc: $e');
      Future.delayed(const Duration(seconds: 2), () => _retryFetchUserDoc(firebaseUser));
    }

    // Clear pending registration data
    _pendingName = null;
    _pendingPhone = null;
    _pendingRole = null;

    // Save FCM token
    try {
      await _notificationService.saveTokenToFirestore(firebaseUser.uid);
    } catch (_) {}

    // Wait for Cloud Function to set custom claims before navigating
    if (needsClaimsWait) {
      debugPrint('[AuthProvider] Waiting for custom claims from Cloud Function...');
      await _waitForClaims();
    }

    _status = AuthStatus.authenticated;

    notifyListeners();
  }

  // Send OTP to phone number
  // Note: Does NOT change _status to loading to avoid triggering router
  // redirect (via refreshListenable) which would pop the OTP screen.
  Future<void> sendOTP(String phoneNumber) async {
    _errorMessage = null;
    debugPrint('[AuthProvider] sendOTP called for: $phoneNumber');

    try {
      await _authService.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        onCodeSent: (verificationId, resendToken) {
          debugPrint('[AuthProvider] OTP code sent successfully');
          _verificationId = verificationId;
          _resendToken = resendToken;
        },
        onVerificationCompleted: (credential) async {
          debugPrint('[AuthProvider] Auto-verification completed');
          // Auto-verify (Android only)
          await FirebaseAuth.instance.signInWithCredential(credential);
        },
        onVerificationFailed: (error) {
          debugPrint('[AuthProvider] Verification failed: ${error.code} - ${error.message}');
          _errorMessage = error.message ?? 'Verification failed';
          notifyListeners();
        },
        onCodeAutoRetrievalTimeout: (verificationId) {
          debugPrint('[AuthProvider] Auto-retrieval timeout');
          _verificationId = verificationId;
        },
        resendToken: _resendToken,
      );
    } catch (e) {
      debugPrint('[AuthProvider] sendOTP exception: $e');
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // Verify OTP code
  Future<bool> verifyOTP(String smsCode) async {
    if (_verificationId == null) {
      _errorMessage = 'No verification ID. Please request OTP again.';
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }

    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.verifyOTP(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      // Auth state listener will handle the rest
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = e.message ?? 'Invalid OTP';
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  // Register new user after OTP verification
  Future<bool> registerUser({
    required String name,
    required String phone,
    required String role,
    required String enterpriseId,
  }) async {
    final user = _authService.currentUser;
    if (user == null) return false;

    try {
      final now = DateTime.now();
      final userModel = UserModel(
        id: user.uid,
        name: name,
        phone: phone,
        roles: [role],
        activeRole: role,
        enterpriseId: enterpriseId,
        createdAt: now,
        updatedAt: now,
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(userModel.toFirestore());

      _currentUser = userModel;
      _roles = [role];
      _activeRole = role;
      _enterpriseId = enterpriseId;
      notifyListeners();

      // Wait briefly for Cloud Function to set custom claims, then refresh token
      Future.delayed(const Duration(seconds: 3), () {
        refreshTokenAndClaims();
      });

      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Enterprise login (email/password)
  Future<bool> loginEnterprise(String email, String password) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _roles = ['admin']; // Enterprise login is always admin
      _activeRole = 'admin';
      await _authService.signInWithEmailPassword(
        email: email,
        password: password,
      );
      // Auth state listener will handle the rest
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = e.message ?? 'Login failed';
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// Switch active role for multi-role users.
  Future<void> switchRole(String newRole) async {
    if (_roles == null || !_roles!.contains(newRole)) return;
    if (_activeRole == newRole) return;

    _activeRole = newRole;

    // Update Firestore
    final user = _authService.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'activeRole': newRole,
        'role': newRole, // backward compat
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    }

    // Update currentUser model
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(activeRole: newRole);
    }

    notifyListeners();
  }

  /// Poll for custom claims to be set by Cloud Function, with retries.
  /// Returns true if claims became available, false if timed out.
  Future<bool> _waitForClaims({int maxAttempts = 5, int delaySeconds = 2}) async {
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(Duration(seconds: delaySeconds));
      final user = _authService.currentUser;
      if (user == null) return false;
      await user.getIdToken(true);
      final claims = await _authService.getUserClaims();
      // Check for new-style claims first, then old-style
      if (claims != null) {
        if (claims['roles'] != null && claims['enterpriseId'] != null) {
          _roles = List<String>.from(claims['roles']);
          _activeRole = claims['activeRole'] as String? ?? _roles!.first;
          _enterpriseId = claims['enterpriseId'] as String;
          debugPrint('[AuthProvider] Claims ready (multi-role) after ${i + 1} attempt(s): roles=$_roles, activeRole=$_activeRole');
          return true;
        } else if (claims['role'] != null && claims['enterpriseId'] != null) {
          _roles = [claims['role'] as String];
          _activeRole = claims['role'] as String;
          _enterpriseId = claims['enterpriseId'] as String;
          debugPrint('[AuthProvider] Claims ready (legacy) after ${i + 1} attempt(s): role=$_activeRole');
          return true;
        }
      }
      debugPrint('[AuthProvider] Waiting for claims... attempt ${i + 1}/$maxAttempts');
    }
    debugPrint('[AuthProvider] Claims not available after $maxAttempts attempts');
    return false;
  }

  // Retry fetching user doc after transient network failure
  Future<void> _retryFetchUserDoc(User firebaseUser) async {
    if (_currentUser != null) return; // Already loaded

    debugPrint('[AuthProvider] Retrying user doc fetch...');
    try {
      // Retry claims
      final claims = await _authService.getUserClaims();
      if (claims != null) {
        if (claims['roles'] != null) {
          _roles = List<String>.from(claims['roles']);
          _activeRole = claims['activeRole'] as String? ?? _roles!.first;
        } else if (claims['role'] != null) {
          _roles = [claims['role'] as String];
          _activeRole = claims['role'] as String;
        }
        final claimEnterprise = claims['enterpriseId'] as String?;
        if (claimEnterprise != null) _enterpriseId = claimEnterprise;
      }

      // Retry user doc
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .get();

      if (userDoc.exists) {
        _currentUser = UserModel.fromFirestore(userDoc);
        _roles ??= _currentUser!.roles;
        _activeRole ??= _currentUser!.activeRole;
        _enterpriseId ??= _currentUser!.enterpriseId;
        debugPrint('[AuthProvider] Retry succeeded: roles=$_roles, activeRole=$_activeRole');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AuthProvider] Retry also failed: $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _authService.signOut();
    _currentUser = null;
    _roles = null;
    _activeRole = null;
    _enterpriseId = null;
    _verificationId = null;
    _resendToken = null;
    _pendingName = null;
    _pendingPhone = null;
    _pendingRole = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  // Re-authenticate with password (for sensitive operations like export)
  Future<bool> reauthenticateWithPassword(String password) async {
    final user = _authService.currentUser;
    if (user == null || user.email == null) return false;

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Force-refresh the Firebase ID token and re-fetch custom claims
  Future<void> refreshTokenAndClaims() async {
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      // Force refresh the token so new custom claims are picked up
      await user.getIdToken(true);
      final claims = await _authService.getUserClaims();
      if (claims != null) {
        if (claims['roles'] != null) {
          _roles = List<String>.from(claims['roles']);
          _activeRole = claims['activeRole'] as String? ?? _roles!.first;
        } else if (claims['role'] != null) {
          _roles = [claims['role'] as String];
          _activeRole = claims['role'] as String;
        }
        final claimEnterprise = claims['enterpriseId'] as String?;
        if (claimEnterprise != null) _enterpriseId = claimEnterprise;
      }
      notifyListeners();
    } catch (_) {}
  }

  // Check if user document exists in Firestore
  Future<bool> userDocExists() async {
    final user = _authService.currentUser;
    if (user == null) return false;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  // Refresh user data from Firestore
  Future<void> refreshUser() async {
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        _currentUser = UserModel.fromFirestore(userDoc);
        notifyListeners();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
