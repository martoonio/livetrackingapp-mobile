class MapData {
  static const List<Map<String, dynamic>> routeMarkers = [
    {
      'halte': 'Gerbang Utama',
      'geoCode': [-6.933205, 107.768413],
      'nextHalteEstimate': 120
    },
    {
      'halte': 'Labtek 1B',
      'geoCode': [-6.929396, 107.768557],
      'nextHalteEstimate': 60
    },
    {
      'halte': 'GKU 2',
      'geoCode': [-6.929788, 107.769033],
      'nextHalteEstimate': 60
    },
    {
      'halte': 'GKU 1A',
      'geoCode': [-6.929079, 107.769818],
      'nextHalteEstimate': 60
    },
    {
      'halte': 'Rektorat',
      'geoCode': [-6.927963, 107.770518],
      'nextHalteEstimate': 60
    },
    {
      'halte': 'Koica',
      'geoCode': [-6.927467, 107.770047],
      'nextHalteEstimate': 60
    },
    {
      'halte': 'GSG',
      'geoCode': [-6.926586, 107.769261],
      'nextHalteEstimate': 120
    },
    {
      'halte': 'GKU 1B',
      'geoCode': [-6.929019, 107.770110],
      'nextHalteEstimate': 60
    },
    {
      'halte': 'Parkiran Kehutanan',
      'geoCode': [-6.931548, 107.770884],
      'nextHalteEstimate': 120
    }
  ];

  static const List<List<double>> route = [
    [-6.933629, 107.768350],
    [-6.932798, 107.768344],
    [-6.932136, 107.768637],
    [-6.931763, 107.768779],
    [-6.931441, 107.768794],
    [-6.929420, 107.768277],
    [-6.929284, 107.768520],
    [-6.929365, 107.768625],
    [-6.929457, 107.768620],
    [-6.929606, 107.768343],
    [-6.930347, 107.768536],
    [-6.928266, 107.770839],
    [-6.925931, 107.768654],
    [-6.925508, 107.769094],
    [-6.927201, 107.770700],
    [-6.927606, 107.770259],
    [-6.928266, 107.770869],
    [-6.929038, 107.770054],
    [-6.929842, 107.770312],
    [-6.930405, 107.770477],
    [-6.931596, 107.770825],
    [-6.932023, 107.770862],
    [-6.932260, 107.770825],
    [-6.932451, 107.770642],
    [-6.932620, 107.770232],
    [-6.932678, 107.769916],
    [-6.932591, 107.769699],
    [-6.931975, 107.769131],
    [-6.931928, 107.768897],
    [-6.932184, 107.768622],
    [-6.932732, 107.768369],
    [-6.933629, 107.768350]
  ];

  // Helper method to get center point of the route
  static List<double> get routeCenter {
    double sumLat = 0;
    double sumLng = 0;
    
    for (var point in route) {
      sumLat += point[0];
      sumLng += point[1];
    }
    
    return [sumLat / route.length, sumLng / route.length];
  }
}