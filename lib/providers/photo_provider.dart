import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import '../models/photo_model.dart';
import '../repositories/photo_repository.dart';

class PhotoProvider extends ChangeNotifier {
  final PhotoRepository _photoRepo = PhotoRepository();

  List<PhotoModel> _photos = [];
  Map<String, List<PhotoModel>> _photosByDate = {};
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _photosSubscription;

  List<PhotoModel> get photos => _photos;
  Map<String, List<PhotoModel>> get photosByDate => _photosByDate;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Load photos for the current employee
  Future<void> loadPhotos(String employeeId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _photos = await _photoRepo.getPhotosByEmployee(employeeId);
      _groupPhotosByDate();
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  // Stream photos for live updates
  void streamPhotos(String employeeId) {
    debugPrint('[PhotoProvider] streamPhotos called for employeeId=$employeeId');
    if (employeeId.isEmpty) {
      debugPrint('[PhotoProvider] ERROR: employeeId is empty, skipping stream');
      return;
    }
    _photosSubscription?.cancel();
    _photosSubscription = _photoRepo
        .streamPhotosByEmployee(employeeId)
        .listen(
      (photos) {
        debugPrint('[PhotoProvider] stream received ${photos.length} photos');
        _photos = photos;
        _groupPhotosByDate();
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[PhotoProvider] stream error: $e');
        // Fallback to one-time fetch
        loadPhotos(employeeId);
      },
    );
  }

  // Stream photos for enterprise (admin)
  void streamPhotosForEnterprise(String enterpriseId) {
    _photosSubscription?.cancel();
    _isLoading = true;
    notifyListeners();
    _photosSubscription = _photoRepo
        .streamPhotosByEnterprise(enterpriseId)
        .listen(
      (photos) {
        _photos = photos;
        _groupPhotosByDate();
        _isLoading = false;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[PhotoProvider] streamPhotosForEnterprise error: $e');
        // Fallback to one-time fetch if stream fails (e.g. missing index)
        _isLoading = false;
        notifyListeners();
        getPhotosByEnterprise(enterpriseId);
      },
    );
  }

  // One-time fetch photos for enterprise (fallback)
  Future<void> getPhotosByEnterprise(String enterpriseId) async {
    _isLoading = true;
    notifyListeners();
    try {
      _photos = await _photoRepo.getPhotosByEnterprise(enterpriseId);
      _groupPhotosByDate();
    } catch (e) {
      _error = e.toString();
      debugPrint('[PhotoProvider] getPhotosByEnterprise error: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  // Upload a new photo
  Future<PhotoModel?> uploadPhoto({
    required File imageFile,
    required String enterpriseId,
    required String employeeId,
    required String sessionId,
    required String location,
    required double latitude,
    required double longitude,
  }) async {
    debugPrint('[PhotoProvider] uploadPhoto: enterprise=$enterpriseId, employee=$employeeId, session=$sessionId');
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final geotagData = {
        'date': DateFormat('dd MMM yyyy').format(now),
        'time': DateFormat('HH:mm:ss a').format(now),
        'coordinates':
            'Lat: ${latitude.toStringAsFixed(4)} N | Long: ${longitude.toStringAsFixed(4)} E',
      };

      final photo = await _photoRepo.uploadPhoto(
        imageFile: imageFile,
        enterpriseId: enterpriseId,
        employeeId: employeeId,
        sessionId: sessionId,
        location: location,
        latitude: latitude,
        longitude: longitude,
        geotagData: geotagData,
      );

      debugPrint('[PhotoProvider] upload SUCCESS: id=${photo.id}, url=${photo.imageUrl}');
      _photos.insert(0, photo);
      _groupPhotosByDate();
      _isLoading = false;
      notifyListeners();
      return photo;
    } catch (e) {
      debugPrint('[PhotoProvider] upload FAILED: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  // Delete a photo
  Future<bool> deletePhoto(String photoId) async {
    try {
      await _photoRepo.deletePhoto(photoId);
      _photos.removeWhere((p) => p.id == photoId);
      _groupPhotosByDate();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Search photos by location
  List<PhotoModel> searchPhotos(String query) {
    if (query.isEmpty) return _photos;
    final lowerQuery = query.toLowerCase();
    return _photos
        .where((p) => p.location.toLowerCase().contains(lowerQuery))
        .toList();
  }

  void _groupPhotosByDate() {
    _photosByDate = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final photo in _photos) {
      final photoDate =
          DateTime(photo.timestamp.year, photo.timestamp.month, photo.timestamp.day);

      String dateKey;
      if (photoDate == today) {
        dateKey = 'Today';
      } else if (photoDate == yesterday) {
        dateKey = 'Yesterday';
      } else {
        dateKey = DateFormat('dd MMM yyyy').format(photo.timestamp);
      }

      _photosByDate.putIfAbsent(dateKey, () => []).add(photo);
    }
  }

  int get todayCount {
    final today = DateTime.now();
    return _photos
        .where((p) =>
            p.timestamp.year == today.year &&
            p.timestamp.month == today.month &&
            p.timestamp.day == today.day)
        .length;
  }

  @override
  void dispose() {
    _photosSubscription?.cancel();
    super.dispose();
  }
}
