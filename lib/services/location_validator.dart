import 'package:detect_fake_location/detect_fake_location.dart';
import 'package:geolocator/geolocator.dart';

class LocationValidator {
  static final DetectFakeLocation _detectFakeLocation = DetectFakeLocation();
  
  // Cache untuk deteksi teleporting
  static Position? _lastPosition;
  static DateTime? _lastPositionTime;
  
  // Kecepatan maksimal realistis (m/s)
  static const double MAX_REALISTIC_SPEED = 33.3; // ~120 km/h
  
  /// Memeriksa apakah lokasi adalah mock location
  static Future<bool> isLocationMocked(Position position) async {
    // 1. Cek dengan package detect_fake_location
    final isMocked = await _detectFakeLocation.detectFakeLocation();
    if (isMocked) {
      print('Mock location detected via detect_fake_location package');
      return true;
    }
    
    // 2. Cek property isMocked dari Geolocator sebagai fallback
    if (position.isMocked) {
      print('Mock location detected via Geolocator.isMocked property');
      return true;
    }
    
    // 3. Cek pola pergerakan yang tidak realistis sebagai metode tambahan
    if (await _hasUnrealisticMovement(position)) {
      print('Mock location detected via unrealistic movement pattern');
      return true;
    }
    
    return false;
  }
  
  /// Memeriksa pola pergerakan teleporting
  static Future<bool> _hasUnrealisticMovement(Position position) async {
    final now = DateTime.now();
    
    // Inisialisasi referensi jika belum ada
    if (_lastPosition == null || _lastPositionTime == null) {
      _lastPosition = position;
      _lastPositionTime = now;
      return false;
    }
    
    // Hitung jarak dan waktu
    final distance = Geolocator.distanceBetween(
      _lastPosition!.latitude, 
      _lastPosition!.longitude,
      position.latitude, 
      position.longitude
    );
    
    final elapsedTimeSeconds = now.difference(_lastPositionTime!).inMilliseconds / 1000;
    
    // Update referensi
    _lastPosition = position;
    _lastPositionTime = now;
    
    // Cek apakah waktu terlalu singkat
    if (elapsedTimeSeconds < 0.1) return false;
    
    // Hitung kecepatan (m/s)
    final speed = distance / elapsedTimeSeconds;
    
    // Detect teleporting: kecepatan tidak realistis dan jarak signifikan
    if (speed > MAX_REALISTIC_SPEED && distance > 100) {
      print('Unrealistic movement: $speed m/s over $distance meters in $elapsedTimeSeconds seconds');
      return true;
    }
    
    return false;
  }
}