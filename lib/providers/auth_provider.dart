import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/permission_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();

  AuthStatus _status = AuthStatus.initial;
  UserModel? _currentUser;
  List<String>? _roles;
  String? _activeRole;
  String? _enterpriseId;
  String? _errorMessage;
  String? _verificationId;
  int? _resendToken;
  String? _pendingOtpPhoneNumber;
  String? _pendingOtpRole;
  String? _pendingOtpName;

  // Pending registration data (set before OTP, consumed in _onAuthStateChanged)
  String? _pendingName;
  String? _pendingPhone;
  String? _pendingRole;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<RemoteMessage>? _forceLogoutSubscription;
  bool _disposed = false;

  AuthStatus get status => _status;
  UserModel? get currentUser => _currentUser;
  List<String>? get roles => _roles;
  String? get activeRole => _activeRole;
  String? get enterpriseId => _enterpriseId;
  String? get errorMessage => _errorMessage;
  String? get verificationId => _verificationId;
  String? get pendingOtpPhoneNumber => _pendingOtpPhoneNumber;
  String? get pendingOtpRole => _pendingOtpRole;
  String? get pendingOtpName => _pendingOtpName;
  bool get hasPendingOtp =>
      _verificationId != null && (_pendingOtpPhoneNumber?.isNotEmpty ?? false);
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isAdmin => _roles?.contains('admin') ?? false;
  bool get isTeamLead => _roles?.contains('team_lead') ?? false;
  bool get isEmployee => _roles?.contains('employee') ?? false;

  // Backward compat: expose role as activeRole
  String? get role => _activeRole;

  /// Expose notification service for deep-link wiring in main.dart
  NotificationService get notificationService => _notificationService;

  AuthProvider() {
    _init();
  }

  void _init() {
    // If Firebase Auth has a persisted user, move to loading state immediately.
    // This prevents a spurious null from authStateChanges() on cold start
    // from bouncing us straight to the login screen.
    if (_authService.currentUser != null) {
      _status = AuthStatus.loading;
    }
    _authSubscription =
        _authService.authStateChanges.listen(_onAuthStateChanged);
    // Lightweight APNs registration for iOS phone auth (no permission dialog).
    // Full notification init is deferred until after auth resolves.
    unawaited(_notificationService.registerForAPNs());
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
      // Guard: Firebase may briefly emit null before restoring a persisted
      // session on cold start. Some OEMs (Motorola) have slow keystore
      // access that can delay token restoration by 1-2 seconds.
      // Retry twice with increasing delays before giving up.
      if (_status == AuthStatus.initial || _status == AuthStatus.loading) {
        debugPrint(
            '[AuthProvider] Null event during $_status — checking for spurious emission');
        for (final delay in [500, 1500]) {
          await Future.delayed(Duration(milliseconds: delay));
          final retryUser = _authService.currentUser;
          if (retryUser != null) {
            debugPrint(
                '[AuthProvider] Spurious null detected after ${delay}ms, retrying with restored user');
            return _onAuthStateChanged(retryUser);
          }
        }
      }

      // Truly signed out — clear all state
      debugPrint('[AuthProvider] User is null, setting unauthenticated');
      _forceLogoutSubscription?.cancel();
      _forceLogoutSubscription = null;
      _currentUser = null;
      _roles = null;
      _activeRole = null;
      _enterpriseId = null;
      _verificationId = null;
      _resendToken = null;
      _pendingOtpPhoneNumber = null;
      _pendingOtpRole = null;
      _pendingOtpName = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    debugPrint('[AuthProvider] _onAuthStateChanged: uid=${firebaseUser.uid}');

    // ── FAST PATH: returning user with valid cached claims ──
    // Uses cached token (no network) + cached Firestore doc for instant auth.
    if (await _tryFastPath(firebaseUser)) return;

    // ── SLOW PATH: new users, legacy claims, or missing data ──
    await _slowPath(firebaseUser);
  }

  /// Fast path for returning users: read cached claims + cached user doc.
  /// Returns true if authenticated successfully (no network needed).
  Future<bool> _tryFastPath(User firebaseUser) async {
    try {
      final cachedClaims = await _authService
          .getUserClaims(forceRefresh: false)
          .timeout(const Duration(seconds: 2));
      if (cachedClaims != null &&
          cachedClaims['roles'] != null &&
          cachedClaims['enterpriseId'] != null) {
        _roles = List<String>.from(cachedClaims['roles']);
        _activeRole = cachedClaims['activeRole'] as String? ?? _roles!.first;
        _enterpriseId = cachedClaims['enterpriseId'] as String;

        // Try loading user doc from cache (instant, no network)
        try {
          final cachedDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(firebaseUser.uid)
              .get(const GetOptions(source: Source.cache));
          if (cachedDoc.exists) {
            _currentUser = UserModel.fromFirestore(cachedDoc);
          }
        } catch (_) {
          // Cache miss is fine — user doc will load in background
        }

        debugPrint('[AuthProvider] FAST PATH: authenticated from cached claims '
            'roles=$_roles, activeRole=$_activeRole, enterpriseId=$_enterpriseId');
        _status = AuthStatus.authenticated;
        notifyListeners();

        // Background: refresh user doc from server, save FCM token, init notifications
        unawaited(_backgroundRefresh(firebaseUser));
        return true;
      }
    } catch (_) {
      // Cached claims not available — fall through to slow path
    }
    return false;
  }

  /// Background tasks after fast-path authentication.
  Future<void> _backgroundRefresh(User firebaseUser) async {
    // Refresh user doc from server
    try {
      final serverDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      if (serverDoc.exists) {
        _currentUser = UserModel.fromFirestore(serverDoc);
        if (!_disposed) notifyListeners();
      }
    } catch (e) {
      debugPrint('[AuthProvider] Background user doc refresh failed: $e');
    }

    // Save FCM token
    try {
      await _notificationService.saveTokenToFirestore(firebaseUser.uid);
    } catch (e) {
      debugPrint('[AuthProvider] Background FCM token save failed: $e');
    }

    // Request shared runtime permissions upfront. Camera stays deferred on iOS.
    try {
      await _permissionService.requestAllPermissions();
    } catch (e) {
      debugPrint('[AuthProvider] Bulk permission request failed: $e');
    }

    // Full notification init (permission request, channels, listeners)
    try {
      await _notificationService.initialize();
    } catch (e) {
      debugPrint('[AuthProvider] Background notification init failed: $e');
    }

    // Listen for force_logout push from another device
    _listenForForceLogout();
  }

  /// Subscribe to FCM foreground messages and sign out if a force_logout
  /// data message is received (another device claimed this account).
  void _listenForForceLogout() {
    _forceLogoutSubscription?.cancel();
    _forceLogoutSubscription =
        _notificationService.onForegroundMessage.listen((message) {
      if (message.data['type'] == 'force_logout') {
        debugPrint(
            '[AuthProvider] Received force_logout push — signing out.');
        _errorMessage =
            'You have been logged out because your account was signed in on another device.';
        _currentUser = null;
        _roles = null;
        _activeRole = null;
        _enterpriseId = null;
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        _authService.signOut();
      }
    });
  }

  /// Slow path: full auth resolution for new users, legacy claims, etc.
  Future<void> _slowPath(User firebaseUser) async {
    bool needsClaimsWait = false;
    bool claimsFoundInToken = false;
    bool claimsMismatchDetected = false;

    // 1. Fetch claims and user doc in PARALLEL
    final claimsFuture = _authService
        .getUserClaims(forceRefresh: true)
        .timeout(const Duration(seconds: 8))
        .catchError((e) {
      debugPrint('[AuthProvider] Failed to fetch custom claims: $e');
      return null;
    });

    final userDocFuture = _fetchUserDoc(firebaseUser.uid);

    final results = await Future.wait([claimsFuture, userDocFuture]);
    final claims = results[0] as Map<String, dynamic>?;
    final userDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>?;

    // Process claims
    if (claims != null) {
      debugPrint(
          '[AuthProvider] Token claims: roles=${claims['roles']}, role=${claims['role']}, activeRole=${claims['activeRole']}, enterpriseId=${claims['enterpriseId']}');
      if (claims['roles'] != null) {
        _roles = List<String>.from(claims['roles']);
        _activeRole = claims['activeRole'] as String? ?? _roles!.first;
        claimsFoundInToken = true;
      } else if (claims['role'] != null) {
        // Legacy single-role claim — populate local state but do NOT mark
        // claimsFoundInToken so that ensureClaims upgrades the token.
        _roles = [claims['role'] as String];
        _activeRole = claims['role'] as String;
      }
      final claimEnterprise = claims['enterpriseId'] as String?;
      if (claimEnterprise != null) _enterpriseId = claimEnterprise;
    }
    debugPrint('[AuthProvider] claimsFoundInToken=$claimsFoundInToken');

    // 2. Process user doc
    if (userDoc != null && userDoc.exists) {
      _currentUser = UserModel.fromFirestore(userDoc);
      _roles ??= _currentUser!.roles;
      _activeRole ??= _currentUser!.activeRole;
      _enterpriseId ??= _currentUser!.enterpriseId;
      debugPrint(
          '[AuthProvider] User doc loaded: roles=$_roles, activeRole=$_activeRole, enterpriseId=$_enterpriseId');

      // If enterprise is placeholder, call resolveUserOnLogin to merge admin-created doc
      if (_enterpriseId == null || _enterpriseId == 'default_enterprise') {
        debugPrint(
            '[AuthProvider] Placeholder enterprise detected, calling resolveUserOnLogin...');
        try {
          await firebaseUser.getIdToken(true);
          final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
              .httpsCallable('resolveUserOnLogin');
          final result = await callable.call();
          final data = result.data as Map<String, dynamic>?;

          if (data != null && data['found'] == true && data['user'] != null) {
            final userData = Map<String, dynamic>.from(data['user']);
            final resolvedEnterprise = userData['enterpriseId'] as String?;
            if (resolvedEnterprise != null &&
                resolvedEnterprise != 'default_enterprise') {
              debugPrint(
                  '[AuthProvider] Enterprise resolved: $resolvedEnterprise');
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
    } else if (userDoc != null) {
      // User doc doesn't exist — try resolveUserOnLogin
      debugPrint(
          '[AuthProvider] No user doc at UID, calling resolveUserOnLogin...');
      try {
        await firebaseUser.getIdToken(true);
        final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
            .httpsCallable('resolveUserOnLogin');
        final result = await callable.call();
        final data = result.data as Map<String, dynamic>?;

        if (data != null && data['found'] == true && data['user'] != null) {
          final userData = Map<String, dynamic>.from(data['user']);
          debugPrint(
              '[AuthProvider] resolveUserOnLogin found user, loading...');

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
            _roles = userData['roles'] != null
                ? List<String>.from(userData['roles'])
                : [userData['role'] ?? 'employee'];
            _activeRole = userData['activeRole'] as String? ??
                userData['role'] as String? ??
                'employee';
            _enterpriseId = userData['enterpriseId'] as String?;
          }
          needsClaimsWait = true;
        } else {
          debugPrint('[AuthProvider] resolveUserOnLogin: new user');
        }
      } catch (e) {
        debugPrint('[AuthProvider] resolveUserOnLogin failed: $e');
      }

      // If new user AND _pendingRegistration exists → create user doc
      final hasPendingRegistrationName =
          (_pendingName?.trim().isNotEmpty ?? false);
      if (_currentUser == null && hasPendingRegistrationName) {
        debugPrint(
            '[AuthProvider] No user doc found, creating from pending registration...');
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
        debugPrint(
            '[AuthProvider] User doc created: roles=$_roles, activeRole=$_activeRole');
        needsClaimsWait = true;
      } else if (_currentUser == null && firebaseUser.email != null) {
        // Enterprise admin (email auth) — auto-create Firestore user doc
        debugPrint(
            '[AuthProvider] Enterprise admin has no user doc, creating...');
        final now = DateTime.now();
        final userModel = UserModel(
          id: firebaseUser.uid,
          name:
              firebaseUser.displayName ?? firebaseUser.email!.split('@').first,
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
        debugPrint(
            '[AuthProvider] Enterprise admin doc created: enterpriseId=$_enterpriseId');
        needsClaimsWait = true;
      } else if (_currentUser == null) {
        debugPrint(
            '[AuthProvider] No resolved user doc and no valid self-registration payload');
        if (_enterpriseId == null) {
          Future.delayed(const Duration(seconds: 2), () {
            if (!_disposed) _retryFetchUserDoc(firebaseUser);
          });
        }
      }
    } else {
      // userDoc fetch failed entirely
      debugPrint('[AuthProvider] Failed to fetch/create user doc');
      Future.delayed(const Duration(seconds: 2), () {
        if (!_disposed) _retryFetchUserDoc(firebaseUser);
      });
    }

    // Clear pending registration data
    _pendingName = null;
    _pendingPhone = null;
    _pendingRole = null;

    // Save FCM token (fire-and-forget — not blocking auth flow)
    unawaited(
      _notificationService
          .saveTokenToFirestore(firebaseUser.uid)
          .catchError((e) {
        debugPrint('[AuthProvider] FCM token save failed: $e');
      }),
    );

    // Detect stale token claims vs Firestore role state
    if (_currentUser != null && claims != null) {
      final tokenRoles = claims['roles'] != null
          ? List<String>.from(claims['roles'])
          : (claims['role'] != null ? [claims['role'] as String] : <String>[]);
      final docRoles = [..._currentUser!.roles];
      tokenRoles.sort();
      docRoles.sort();
      final rolesMatch = tokenRoles.length == docRoles.length &&
          tokenRoles.asMap().entries.every((e) => e.value == docRoles[e.key]);
      final tokenActiveRole =
          claims['activeRole'] as String? ?? claims['role'] as String?;
      final activeRoleMatch = tokenActiveRole == _currentUser!.activeRole;
      final tokenEnterprise = claims['enterpriseId'] as String?;
      final enterpriseMatch = tokenEnterprise == _currentUser!.enterpriseId;

      claimsMismatchDetected =
          !(rolesMatch && activeRoleMatch && enterpriseMatch);
      if (claimsMismatchDetected) {
        debugPrint(
            '[AuthProvider] Claims mismatch detected, scheduling ensureClaims sync.');
      }
    }

    // If claims are missing or stale, call ensureClaims
    if ((!claimsFoundInToken || claimsMismatchDetected) &&
        _currentUser != null) {
      debugPrint(
          '[AuthProvider] Claims missing/stale, calling ensureClaims...');
      try {
        await firebaseUser.getIdToken(true);
        final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
            .httpsCallable('ensureClaims');
        await callable.call();
        debugPrint(
            '[AuthProvider] ensureClaims succeeded, refreshing token...');
      } catch (e) {
        debugPrint('[AuthProvider] ensureClaims failed: $e');
      }
      needsClaimsWait = true;
    }

    // Wait for Cloud Function to set custom claims before navigating.
    // Preserve the role from Firestore doc — claims may have stale data
    // from a previous login if Auth wasn't fully deleted.
    final firestoreRole = _activeRole;
    if (needsClaimsWait) {
      debugPrint(
          '[AuthProvider] Waiting for custom claims from Cloud Function...');
      try {
        await _waitForClaims();
      } catch (e) {
        debugPrint('[AuthProvider] _waitForClaims failed: $e');
      }
      // If Firestore doc had a role and claims overwrote it with a different
      // one, trust the Firestore doc (it was set by resolveUserOnLogin).
      if (firestoreRole != null &&
          _activeRole != firestoreRole &&
          _currentUser != null &&
          _currentUser!.activeRole == firestoreRole) {
        debugPrint(
          '[AuthProvider] Claims returned stale role=$_activeRole, '
          'reverting to Firestore role=$firestoreRole',
        );
        _activeRole = firestoreRole;
        _roles = _currentUser!.roles;
      }
    }

    _status = AuthStatus.authenticated;
    notifyListeners();

    // Request shared runtime permissions upfront, then init notifications.
    unawaited(Future(() async {
      try {
        await _permissionService.requestAllPermissions();
      } catch (e) {
        debugPrint('[AuthProvider] Bulk permission request failed: $e');
      }
      try {
        await _notificationService.initialize();
      } catch (e) {
        debugPrint('[AuthProvider] Notification init failed: $e');
      }
      _listenForForceLogout();
    }));
  }

  /// Fetch user doc with server-first, cache-fallback strategy.
  Future<DocumentSnapshot<Map<String, dynamic>>?> _fetchUserDoc(
      String uid) async {
    try {
      try {
        return await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        debugPrint('[AuthProvider] Server fetch timed out, trying cache...');
        return await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
      }
    } catch (e) {
      debugPrint('[AuthProvider] User doc fetch failed: $e');
      return null;
    }
  }

  // Send OTP to phone number
  // Note: Does NOT change _status to loading to avoid triggering router
  // redirect (via refreshListenable) which would pop the OTP screen.
  Future<void> sendOTP(String phoneNumber) async {
    _errorMessage = null;
    _pendingOtpPhoneNumber = phoneNumber;
    debugPrint('[AuthProvider] sendOTP called for: $phoneNumber');

    try {
      await _authService.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        onCodeSent: (verificationId, resendToken) {
          debugPrint('[AuthProvider] OTP code sent successfully');
          _verificationId = verificationId;
          _resendToken = resendToken;
          notifyListeners();
        },
        onVerificationCompleted: (credential) async {
          debugPrint('[AuthProvider] Auto-verification completed');
          // Auto-verify (Android only)
          await FirebaseAuth.instance.signInWithCredential(credential);
        },
        onVerificationFailed: (error) {
          debugPrint(
              '[AuthProvider] Verification failed: ${error.code} - ${error.message}');
          _errorMessage = error.message ?? 'Verification failed';
          _verificationId = null;
          _resendToken = null;
          _pendingOtpPhoneNumber = null;
          _pendingOtpRole = null;
          _pendingOtpName = null;
          notifyListeners();
        },
        onCodeAutoRetrievalTimeout: (verificationId) {
          debugPrint('[AuthProvider] Auto-retrieval timeout');
          _verificationId = verificationId;
          notifyListeners();
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
      _verificationId = null;
      _resendToken = null;
      _pendingOtpPhoneNumber = null;
      _pendingOtpRole = null;
      _pendingOtpName = null;
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
        if (!_disposed) refreshTokenAndClaims();
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

  /// Poll for custom claims with exponential backoff.
  /// Starts at 500ms, scales 1.5x each attempt. Typically succeeds in 1-2 attempts.
  Future<bool> _waitForClaims({int maxAttempts = 6}) async {
    int delayMs = 500;
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(Duration(milliseconds: delayMs));
      final user = _authService.currentUser;
      if (user == null) return false;
      await user.getIdToken(true);
      final claims = await _authService.getUserClaims();
      if (claims != null) {
        if (claims['roles'] != null && claims['enterpriseId'] != null) {
          _roles = List<String>.from(claims['roles']);
          _activeRole = claims['activeRole'] as String? ?? _roles!.first;
          _enterpriseId = claims['enterpriseId'] as String;
          debugPrint(
              '[AuthProvider] Claims ready (multi-role) after ${i + 1} attempt(s): roles=$_roles, activeRole=$_activeRole');
          return true;
        } else if (claims['role'] != null && claims['enterpriseId'] != null) {
          _roles = [claims['role'] as String];
          _activeRole = claims['role'] as String;
          _enterpriseId = claims['enterpriseId'] as String;
          debugPrint(
              '[AuthProvider] Claims ready (legacy) after ${i + 1} attempt(s): role=$_activeRole');
          return true;
        }
      }
      debugPrint(
          '[AuthProvider] Waiting for claims... attempt ${i + 1}/$maxAttempts (delay: ${delayMs}ms)');
      delayMs = (delayMs * 1.5).round();
    }
    debugPrint(
        '[AuthProvider] Claims not available after $maxAttempts attempts');
    return false;
  }

  // Retry fetching user doc after transient network failure
  Future<void> _retryFetchUserDoc(User firebaseUser) async {
    if (_currentUser != null) return; // Already loaded

    debugPrint('[AuthProvider] Retrying user doc fetch...');
    try {
      // Retry claims
      final claims = await _authService.getUserClaims(forceRefresh: true);
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
        debugPrint(
            '[AuthProvider] Retry succeeded: roles=$_roles, activeRole=$_activeRole');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AuthProvider] Retry also failed: $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    _forceLogoutSubscription?.cancel();
    _forceLogoutSubscription = null;
    final userId = _authService.currentUser?.uid;

    // Clear FCM token from Firestore and delete local FCM registration
    if (userId != null) {
      await Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({'fcmToken': FieldValue.delete()}).catchError((_) {}),
        FirebaseMessaging.instance.deleteToken().catchError((_) {}),
      ]);
    }
    _notificationService.resetForLogout();

    await _authService.signOut();

    _currentUser = null;
    _roles = null;
    _activeRole = null;
    _enterpriseId = null;
    _verificationId = null;
    _resendToken = null;
    _pendingOtpPhoneNumber = null;
    _pendingOtpRole = null;
    _pendingOtpName = null;
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
    } catch (e) {
      debugPrint('[AuthProvider] reauthenticateWithPassword failed: $e');
      return false;
    }
  }

  // Force-refresh the Firebase ID token and re-fetch custom claims.
  // Returns true if roles and enterpriseId are available after refresh.
  Future<bool> refreshTokenAndClaims() async {
    final user = _authService.currentUser;
    if (user == null) return false;

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
      return _roles != null && _enterpriseId != null;
    } catch (e) {
      debugPrint('[AuthProvider] refreshTokenAndClaims failed: $e');
      return false;
    }
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
    } catch (e) {
      debugPrint('[AuthProvider] userDocExists check failed: $e');
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
    } catch (e) {
      debugPrint('[AuthProvider] refreshUser failed: $e');
    }
  }

  void clearError() {
    _errorMessage = null;
  }

  void setPendingOtpRouteData({
    required String phoneNumber,
    required String role,
    String name = '',
  }) {
    _pendingOtpPhoneNumber = phoneNumber;
    _pendingOtpRole = role;
    _pendingOtpName = name;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    _forceLogoutSubscription?.cancel();
    super.dispose();
  }
}
