import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class MapboxService {
  static const String _baseUrl = 'api.mapbox.com';
  static const String _endpoint = '/directions/v5/mapbox/driving';

  Future<int> getEstimatedTime(List<double> origin, List<double> destination) async {
    final accessToken = dotenv.env['MAPBOX_TOKEN'];
    
    // Mapbox expects coordinates in longitude,latitude order
    final coordinates = '${origin[1]},${origin[0]};${destination[1]},${destination[0]}';
    
    final uri = Uri.https(_baseUrl, '$_endpoint/$coordinates', {
      'alternatives': 'false',
      'geometries': 'geojson',
      'overview': 'full',
      'access_token': accessToken,
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Duration is returned in seconds, converting to minutes and rounding
        return (data['routes'][0]['duration'] / 60).round();
      }
      throw Exception('Failed to calculate route duration');
    } catch (e) {
      throw Exception('Error calculating route duration: $e');
    }
  }
}