import 'dart:async'; // Diperlukan untuk StreamSubscription jika digunakan, tapi di sini tidak lagi manual
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/domain/entities/survey.dart'; // Pastikan path ini benar
import 'package:livetrackingapp/presentation/auth/bloc/auth_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart'; // Untuk customSnackbar dan text styles
import 'package:livetrackingapp/presentation/survey/survey_bloc.dart';
import 'package:livetrackingapp/presentation/survey/survey_create_screen.dart';
import 'survey_detail_screen.dart'; // Untuk navigasi ke detail survey

class SurveyListScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const SurveyListScreen({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<SurveyListScreen> createState() => _SurveyListScreenState();
}

class _SurveyListScreenState extends State<SurveyListScreen> {
  // Variabel state lokal untuk menyimpan survey yang sedang diproses saat tombol ditekan.
  // Ini penting agar listener BlocConsumer tahu survey mana yang sedang diperiksa.
  Survey? _selectedSurveyForCheck;

  // GlobalKey untuk dialog loading agar bisa diakses dan ditutup dari mana saja.
  // Ini mencegah masalah "stuck di loading" jika konteks dialog berubah.
  final GlobalKey<State> _loadingDialogKey = GlobalKey<State>();

  @override
  void initState() {
    super.initState();
    // Memuat daftar survei aktif saat layar diinisialisasi.
    context.read<SurveyBloc>().add(LoadActiveSurveys());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Survei & Feedback',
          style: semiBoldTextStyle(size: 18, color: Colors.white),
        ),
        backgroundColor: kbpBlue900,
        elevation: 0,
        actions: [
          // Tombol refresh untuk memuat ulang daftar survei.
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              context.read<SurveyBloc>().add(LoadActiveSurveys());
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: BlocConsumer<SurveyBloc, SurveyState>(
        listener: (context, state) {
          if (state is SurveyLoading) {
            CircularProgressIndicator(
              key: _loadingDialogKey,
            );
          } else if (state is UserCompletedSurveyChecked) {
            if (_loadingDialogKey.currentContext != null &&
                Navigator.canPop(_loadingDialogKey.currentContext!)) {
              Navigator.of(_loadingDialogKey.currentContext!).pop();
            }

            final survey = _selectedSurveyForCheck;
            if (survey == null) {
              print(
                  'Error: _selectedSurveyForCheck is null after UserCompletedSurveyChecked state.');
              showCustomSnackbar(
                context: context,
                title: 'Error',
                subtitle: 'Gagal mendapatkan detail survei.',
                type: SnackbarType.danger,
              );
              return;
            }

            if (state.hasCompleted) {
              showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Survei Sudah Diisi'),
                  content: const Text(
                      'Anda sudah mengisi survei ini. Terima kasih atas partisipasi Anda.'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        context.read<SurveyBloc>().add(LoadActiveSurveys());
                      },
                      child: const Text('Tutup'),
                    ),
                  ],
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (detailContext) => SurveyDetailScreen(
                    surveyId: survey.id,
                    userId: widget.userId,
                    userName: widget.userName,
                  ),
                ),
              ).then((_) {
                if (mounted) {
                  context.read<SurveyBloc>().add(LoadActiveSurveys());
                }
              });
            }
            _selectedSurveyForCheck = null;
          } else if (state is SurveyError) {
            if (_loadingDialogKey.currentContext != null &&
                Navigator.canPop(_loadingDialogKey.currentContext!)) {
              Navigator.of(_loadingDialogKey.currentContext!).pop();
            }
            _selectedSurveyForCheck = null;

            showCustomSnackbar(
              context: context,
              title: 'Error',
              subtitle: state.message,
              type: SnackbarType.danger,
            );
          } else if (state is SurveyCreated) {
            showCustomSnackbar(
              context: context,
              title: 'Survei Dibuat',
              subtitle: 'Survei berhasil dibuat.',
              type: SnackbarType.success,
            );
            context
                .read<SurveyBloc>()
                .add(LoadActiveSurveys()); // Refresh daftar
          } else if (state is SurveyUpdated) {
            showCustomSnackbar(
              context: context,
              title: 'Survei Diperbarui',
              subtitle: 'Survei berhasil diperbarui.',
              type: SnackbarType.success,
            );
            context
                .read<SurveyBloc>()
                .add(LoadActiveSurveys()); // Refresh daftar
          } else if (state is SurveyDeleted) {
            showCustomSnackbar(
              context: context,
              title: 'Survei Dihapus',
              subtitle: 'Survei berhasil dihapus.',
              type: SnackbarType.success,
            );
            context
                .read<SurveyBloc>()
                .add(LoadActiveSurveys()); // Refresh daftar
          }
        },
        builder: (context, state) {
          // Menampilkan indikator loading penuh jika ini adalah loading awal (misalnya LoadActiveSurveys)
          // dan tidak ada survei yang sedang diperiksa secara spesifik.
          if (state is SurveyLoading && _selectedSurveyForCheck == null) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          // Menampilkan daftar survei jika state adalah ActiveSurveysLoaded.
          else if (state is ActiveSurveysLoaded) {
            if (state.surveys.isEmpty) {
              // Tampilan jika tidak ada survei.
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.assessment_outlined,
                      size: 80,
                      color: neutral400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Tidak ada survei saat ini',
                      style: mediumTextStyle(size: 16, color: neutral700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Survei baru akan muncul di sini',
                      style: regularTextStyle(size: 14, color: neutral600),
                    ),
                  ],
                ),
              );
            }

            // Daftar survei yang dapat di-refresh.
            return RefreshIndicator(
              onRefresh: () async {
                context.read<SurveyBloc>().add(LoadActiveSurveys());
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: state.surveys.length,
                itemBuilder: (context, index) {
                  final survey = state.surveys[index];
                  return _buildSurveyCard(survey);
                },
              ),
            );
          }
          // Menampilkan pesan error penuh jika ada error dari loading awal.
          else if (state is SurveyError && _selectedSurveyForCheck == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 80,
                    color: dangerR500,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Gagal memuat survei',
                    style: semiBoldTextStyle(size: 16, color: neutral900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.message,
                    style: regularTextStyle(size: 14, color: neutral700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      context.read<SurveyBloc>().add(LoadActiveSurveys());
                    },
                    icon: const Icon(
                      Icons.refresh,
                      color: neutralWhite,
                    ),
                    label: const Text('Coba Lagi'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kbpBlue900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // Default fallback untuk state yang tidak ditangani secara eksplisit.
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      ),
      // Tombol aksi mengambang (FAB) hanya untuk peran "commandCenter".
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  // Membangun tampilan kartu untuk setiap survei dalam daftar.
  Widget _buildSurveyCard(Survey survey) {
    final formatter =
        DateFormat('dd MMM yyyy', 'id_ID'); // Format tanggal Indonesia
    final expiryDate = formatter.format(survey.expiresAt);

    // Menghitung total pertanyaan dari semua bagian survei.
    int totalQuestions = 0;
    for (var section in survey.sections) {
      totalQuestions += section.questions.length;
    }

    // Menghitung jumlah bagian survei.
    final int sectionCount = survey.sections.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          _checkIfUserCompletedSurvey(
              survey); // Memanggil fungsi pengecekan saat kartu ditekan.
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kbpBlue100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.assessment_rounded,
                      color: kbpBlue900,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          survey.title,
                          style: semiBoldTextStyle(size: 16, color: neutral900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          survey.description,
                          style: regularTextStyle(size: 14, color: neutral700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: neutral600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Berakhir: $expiryDate',
                        style: regularTextStyle(size: 12, color: neutral600),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.help_outline,
                        size: 16,
                        color: neutral600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$totalQuestions Pertanyaan${sectionCount > 1 ? ' • $sectionCount Bagian' : ''}',
                        style: regularTextStyle(size: 12, color: neutral600),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  _checkIfUserCompletedSurvey(
                      survey); // Memanggil fungsi pengecekan saat tombol ditekan.
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kbpBlue900,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Isi Survei',
                  style: mediumTextStyle(size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Membangun tombol aksi mengambang (FAB) berdasarkan peran pengguna.
  Widget? _buildFloatingActionButton() {
    // Hanya tampilkan FAB jika pengguna terautentikasi dan memiliki peran "commandCenter".
    if (context.read<AuthBloc>().state is AuthAuthenticated) {
      final state = context.read<AuthBloc>().state as AuthAuthenticated;
      if (state.user.role == 'commandCenter') {
        return FloatingActionButton(
          onPressed: () {
            // Navigasi ke layar pembuatan survei.
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SurveyCreateScreen(),
              ),
            ).then((_) {
              // Refresh daftar setelah kembali dari layar pembuatan survei.
              context.read<SurveyBloc>().add(LoadActiveSurveys());
            });
          },
          backgroundColor: kbpBlue900,
          child: const Icon(Icons.add),
        );
      }
    }
    return null; // Tidak menampilkan FAB jika tidak memenuhi syarat.
  }

  // Metode untuk memeriksa apakah pengguna sudah mengisi survei tertentu.
  void _checkIfUserCompletedSurvey(Survey survey) {
    // Simpan objek survei yang sedang dicek ke variabel state lokal.
    // Ini penting agar listener BlocConsumer dapat mengakses objek survei yang benar.
    setState(() {
      _selectedSurveyForCheck = survey;
    });

    // Kirim event ke SurveyBloc untuk memeriksa status penyelesaian survei.
    context
        .read<SurveyBloc>()
        .add(CheckUserCompletedSurvey(survey.id, widget.userId));

    // Logika penanganan respons (menutup dialog loading, navigasi, menampilkan snackbar)
    // akan ditangani oleh BlocConsumer listener di build method.
  }

  @override
  void dispose() {
    // Metode dispose tidak lagi memerlukan pembatalan StreamSubscription manual
    // karena BlocConsumer/Listener mengelolanya secara otomatis.
    super.dispose();
  }
}
