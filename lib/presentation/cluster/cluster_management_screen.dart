// import 'package:flutter/material.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:livetrackingapp/domain/entities/user.dart';
// import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
// import 'package:livetrackingapp/presentation/cluster/edit_cluster.dart';
// import 'package:livetrackingapp/presentation/cluster/officer_management_screen.dart';
// import 'package:livetrackingapp/presentation/component/utils.dart';
// import 'package:lottie/lottie.dart' as lottie;

// class ClusterManagementScreen extends StatefulWidget {
//   const ClusterManagementScreen({super.key});

//   @override
//   State<ClusterManagementScreen> createState() =>
//       _ClusterManagementScreenState();
// }

// class _ClusterManagementScreenState extends State<ClusterManagementScreen> {
//   @override
//   void initState() {
//     super.initState();
//     // Load all clusters when screen initializes
//     context.read<AdminBloc>().add(LoadClusters());
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Manajemen Tatar'),
//         backgroundColor: kbpBlue900,
//         foregroundColor: neutralWhite,
//         elevation: 0,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.add),
//             onPressed: () {
//               Navigator.push(
//                 context,
//                 MaterialPageRoute(
//                   builder: (context) => const EditClusterScreen(),
//                 ),
//               );
//             },
//           ),
//         ],
//       ),
//       body: BlocBuilder<AdminBloc, AdminState>(
//         builder: (context, state) {
//           if (state is ClustersLoading) {
//             return Center(
//               child: lottie.Lottie.asset(
//                 'assets/lottie/maps_loading.json',
//                 width: 200,
//                 height: 100,
//                 fit: BoxFit.cover,
//               ),
//             );
//           } else if (state is ClustersLoaded) {
//             final clusters = state.clusters;

//             if (clusters.isEmpty) {
//               return Center(
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     const Icon(Icons.location_off, size: 64, color: neutral400),
//                     16.height,
//                     const Text(
//                       'Belum ada cluster yang tersedia',
//                       style: TextStyle(fontSize: 18, color: neutral600),
//                     ),
//                     24.height,
//                     ElevatedButton.icon(
//                       icon: const Icon(Icons.add),
//                       label: const Text('Tambah Tatar Baru'),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: kbpBlue900,
//                         foregroundColor: neutralWhite,
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 20,
//                           vertical: 12,
//                         ),
//                       ),
//                       onPressed: () {
//                         Navigator.push(
//                           context,
//                           MaterialPageRoute(
//                             builder: (context) => const EditClusterScreen(),
//                           ),
//                         );
//                       },
//                     ),
//                   ],
//                 ),
//               );
//             }

//             return ListView.builder(
//               itemCount: clusters.length,
//               padding: const EdgeInsets.all(16),
//               itemBuilder: (context, index) {
//                 final cluster = clusters[index];
//                 return _buildClusterCard(context, cluster);
//               },
//             );
//           } else if (state is ClustersError) {
//             return Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   const Icon(Icons.error_outline, size: 64, color: dangerR300),
//                   16.height,
//                   Text(
//                     'Error: ${state.message}',
//                     style: const TextStyle(fontSize: 16, color: neutral600),
//                     textAlign: TextAlign.center,
//                   ),
//                   24.height,
//                   ElevatedButton(
//                     child: const Text('Coba Lagi'),
//                     onPressed: () {
//                       context.read<AdminBloc>().add(const LoadClusters());
//                     },
//                   ),
//                 ],
//               ),
//             );
//           }

//           return Center(
//             child: lottie.Lottie.asset(
//               'assets/lottie/maps_loading.json',
//               width: 200,
//               height: 100,
//               fit: BoxFit.cover,
//             ),
//           );
//         },
//       ),
//       floatingActionButton: FloatingActionButton(
//         backgroundColor: kbpBlue900,
//         child: const Icon(Icons.add, color: neutralWhite),
//         onPressed: () {
//           Navigator.push(
//             context,
//             MaterialPageRoute(
//               builder: (context) => const EditClusterScreen(),
//             ),
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildClusterCard(BuildContext context, User cluster) {
//     final officersCount = cluster.officers?.length ?? 0;
//     final pointsCount = cluster.clusterCoordinates?.length ?? 0;

//     return Card(
//       margin: const EdgeInsets.only(bottom: 16),
//       elevation: 2,
//       shape: RoundedRectangleBorder(
//         borderRadius: BorderRadius.circular(12),
//         side: const BorderSide(color: neutral300, width: 1),
//       ),
//       child: InkWell(
//         onTap: () {
//           Navigator.push(
//             context,
//             MaterialPageRoute(
//               builder: (context) => EditClusterScreen(existingCluster: cluster),
//             ),
//           );
//         },
//         borderRadius: BorderRadius.circular(12),
//         child: Padding(
//           padding: const EdgeInsets.all(16),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Expanded(
//                     child: Text(
//                       cluster.name,
//                       style: boldTextStyle(size: 18),
//                       overflow: TextOverflow.ellipsis,
//                     ),
//                   ),
//                   Container(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 8,
//                       vertical: 4,
//                     ),
//                     decoration: BoxDecoration(
//                       color: cluster.isPatrol ? successG100 : kbpBlue100,
//                       borderRadius: BorderRadius.circular(20),
//                       border: Border.all(
//                         color: cluster.isPatrol ? successG300 : kbpBlue300,
//                       ),
//                     ),
//                     child: Text(
//                       cluster.isPatrol ? 'Patrol' : 'Command Center',
//                       style: const TextStyle(
//                         fontSize: 12,
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//               8.height,
//               Text(
//                 cluster.email,
//                 style: const TextStyle(color: neutral600),
//               ),
//               16.height,
//               Row(
//                 children: [
//                   _infoChip(Icons.person, '$officersCount Petugas'),
//                   12.width,
//                   _infoChip(Icons.location_on, '$pointsCount Titik'),
//                 ],
//               ),
//               16.height,
//               Row(
//                 children: [
//                   Expanded(
//                     child: OutlinedButton.icon(
//                       icon: const Icon(Icons.person),
//                       label: const Text('Kelola Petugas'),
//                       style: OutlinedButton.styleFrom(
//                         foregroundColor: kbpBlue900,
//                         side: const BorderSide(color: kbpBlue900),
//                       ),
//                       onPressed: () {
//                         Navigator.push(
//                           context,
//                           MaterialPageRoute(
//                             builder: (context) => OfficerManagementScreen(
//                               clusterId: cluster.id,
//                               clusterName: cluster.name,
//                             ),
//                           ),
//                         );
//                       },
//                     ),
//                   ),
//                   12.width,
//                   Expanded(
//                     child: OutlinedButton.icon(
//                       icon: const Icon(Icons.edit_location_alt),
//                       label: const Text('Edit Area'),
//                       style: OutlinedButton.styleFrom(
//                         foregroundColor: kbpBlue900,
//                         side: const BorderSide(color: kbpBlue900),
//                       ),
//                       onPressed: () {
//                         Navigator.push(
//                           context,
//                           MaterialPageRoute(
//                             builder: (context) => EditClusterScreen(
//                               existingCluster: cluster,
//                               initialTab: 1, // Tab untuk edit area
//                             ),
//                           ),
//                         );
//                       },
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _infoChip(IconData icon, String label) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//       decoration: BoxDecoration(
//         color: neutral300,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: neutral300),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Icon(icon, size: 16, color: neutral600),
//           4.width,
//           Text(
//             label,
//             style: const TextStyle(
//               fontSize: 13,
//               fontWeight: FontWeight.w500,
//               color: neutral700,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
