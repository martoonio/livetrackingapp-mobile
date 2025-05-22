import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/cluster/cluster_detail_screen.dart';
import 'package:livetrackingapp/presentation/cluster/create_cluster_screen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:lottie/lottie.dart';

class ManageClustersScreen extends StatefulWidget {
  const ManageClustersScreen({Key? key}) : super(key: key);

  @override
  State<ManageClustersScreen> createState() => _ManageClustersScreenState();
}

class _ManageClustersScreenState extends State<ManageClustersScreen> {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    context.read<AdminBloc>().add(const LoadAllClusters());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Tatar'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: BlocBuilder<AdminBloc, AdminState>(
              builder: (context, state) {
                if (state is AdminLoading) {
                  return Center(
                    child: LottieBuilder.asset(
                      'assets/lottie/maps_loading.json',
                      width: 200,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  );
                } else if (state is ClustersLoaded) {
                  return _buildClustersList(state.clusters);
                } else if (state is AdminError) {
                  return Center(
                    child: Text(
                      'Error: ${state.message}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                return Center(
                  child: LottieBuilder.asset(
                    'assets/lottie/maps_loading.json',
                    width: 200,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kbpBlue900,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateClusterScreen(),
            ),
          ).then((_) {
            // Reload clusters after returning
            context.read<AdminBloc>().add(LoadAllClusters());
          });
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Cari cluster...',
          prefixIcon: const Icon(Icons.search, color: kbpBlue900),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: kbpBlue900),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                    context.read<AdminBloc>().add(LoadAllClusters());
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kbpBlue700),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kbpBlue700),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kbpBlue900, width: 2),
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
          if (_searchQuery.isEmpty) {
            context.read<AdminBloc>().add(LoadAllClusters());
          } else {
            context.read<AdminBloc>().add(SearchClustersEvent(_searchQuery));
          }
        },
      ),
    );
  }

  Widget _buildClustersList(List<User> clusters) {
    if (clusters.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada cluster ditemukan',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: clusters.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final cluster = clusters[index];
        final officerCount = cluster.officers?.length ?? 0;

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kbpBlue300, width: 1),
          ),
          elevation: 2,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ClusterDetailScreen(clusterId: cluster.id),
                ),
              ).then((_) {
                // Reload clusters after returning
                context.read<AdminBloc>().add(LoadAllClusters());
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          cluster.name,
                          style: boldTextStyle(size: 18),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: kbpBlue100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$officerCount petugas',
                          style: const TextStyle(
                            color: kbpBlue900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.email_outlined,
                          size: 16, color: neutral600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          cluster.email,
                          style: const TextStyle(color: neutral600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 16, color: neutral600),
                      const SizedBox(width: 4),
                      Text(
                        '${cluster.clusterCoordinates?.length ?? 0} titik koordinat',
                        style: const TextStyle(color: neutral600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ClusterDetailScreen(
                                clusterId: cluster.id,
                                initialTab: 1, // Officers tab
                              ),
                            ),
                          );
                        },
                        child: const Text(
                          'Kelola Petugas',
                          style: TextStyle(color: kbpBlue900),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ClusterDetailScreen(clusterId: cluster.id),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kbpBlue900,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Detail'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
