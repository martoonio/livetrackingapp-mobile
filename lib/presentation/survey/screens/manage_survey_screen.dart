import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/survey/survey.dart';
import 'package:livetrackingapp/presentation/auth/bloc/auth_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/survey/bloc/survey_bloc.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/presentation/survey/screens/create_edit_survey_screen.dart';
import 'package:livetrackingapp/presentation/survey/screens/survey_results_screen.dart';


class ManageSurveysScreen extends StatefulWidget {
  const ManageSurveysScreen({super.key});

  @override
  State<ManageSurveysScreen> createState() => _ManageSurveysScreenState();
}

class _ManageSurveysScreenState extends State<ManageSurveysScreen> {
  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context
          .read<SurveyBloc>()
          .add(LoadAllCommandCenterSurveys(commandCenterId: authState.user.id));
    }
  }

  Future<void> _refreshSurveys(String commandCenterId) async {
     context.read<SurveyBloc>().add(LoadAllCommandCenterSurveys(commandCenterId: commandCenterId));
  }

  void _showDeleteConfirmationDialog(BuildContext context, Survey survey) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Konfirmasi Hapus'),
          content: Text('Apakah Anda yakin ingin menghapus survei "${survey.title}"? Tindakan ini tidak dapat diurungkan.'),
          actions: <Widget>[
            TextButton(
              child: Text('Batal', style: TextStyle(color: neutral700)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: Text('Hapus', style: TextStyle(color: dangerR500)),
              onPressed: () {
                context.read<SurveyBloc>().add(DeleteSurveyById(surveyId: survey.surveyId));
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
     final String commandCenterId = (authState is AuthAuthenticated) ? authState.user.id : '';


    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Survei'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false, // Sesuaikan jika ini bukan root admin
         actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              if (authState is AuthAuthenticated) {
                _refreshSurveys(authState.user.id);
              }
            },
          ),
        ],
      ),
      body: BlocConsumer<SurveyBloc, SurveyState>(
        listener: (context, state) {
          if (state is SurveyError) {
            showCustomSnackbar(
                context: context,
                title: 'Error',
                subtitle: state.message,
                type: SnackbarType.danger);
          } else if (state is SurveyOperationSuccess) {
             showCustomSnackbar(
                context: context,
                title: 'Sukses',
                subtitle: state.message,
                type: SnackbarType.success);
            // Reload list after success
            if (authState is AuthAuthenticated) {
                 _refreshSurveys(authState.user.id);
            }
          }
        },
        builder: (context, state) {
          if (state is SurveyLoading && !(state is CommandCenterSurveysLoaded)) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is CommandCenterSurveysLoaded) {
            if (state.surveys.isEmpty) {
              return Center(
                child: EmptyState(
                  icon: Icons.ballot_outlined,
                  title: 'Belum Ada Survei',
                  subtitle: 'Anda belum membuat survei apapun. Mulai buat survei baru untuk pengguna.',
                  buttonText: 'Buat Survei Baru',
                  onButtonPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreateEditSurveyScreen()),
                    ).then((_) {
                         if (authState is AuthAuthenticated) {
                            _refreshSurveys(authState.user.id);
                        }
                    });
                  },
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.surveys.length,
              itemBuilder: (context, index) {
                final survey = state.surveys[index];
                return _buildSurveyManagementCard(context, survey);
              },
            );
          }
          return const Center(child: Text('Silakan segarkan halaman.'));
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateEditSurveyScreen()),
          ).then((_) {
              if (authState is AuthAuthenticated) {
                _refreshSurveys(authState.user.id);
            }
          });
        },
        label: const Text('Buat Survei'),
        icon: const Icon(Icons.add),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildSurveyManagementCard(BuildContext context, Survey survey) {
     final dateFormat = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(survey.title, style: boldTextStyle(size: 18, color: kbpBlue900))),
                Switch(
                  value: survey.isActive,
                  onChanged: (bool value) {
                    context.read<SurveyBloc>().add(ToggleSurveyStatus(surveyId: survey.surveyId, isActive: value));
                  },
                  activeColor: kbpGreen500,
                  inactiveThumbColor: neutral500,
                )
              ],
            ),
            const SizedBox(height: 4),
             Text(
              survey.isActive ? 'Status: Aktif' : 'Status: Tidak Aktif',
              style: regularTextStyle(size: 12, color: survey.isActive ? kbpGreen700 : neutral600),
            ),
            const SizedBox(height: 8),
            if (survey.description != null && survey.description!.isNotEmpty)
              Text(
                survey.description!,
                style: regularTextStyle(color: neutral700, size: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 12),
             Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 16, color: neutral600),
                  const SizedBox(width: 4),
                  Text(
                    'Dibuat: ${dateFormat.format(survey.createdAt)}',
                    style: regularTextStyle(size: 12, color: neutral600),
                  ),
                ],
              ),
            if (survey.targetAudience != null && survey.targetAudience!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                    children: [
                    Icon(Icons.people_alt_outlined, size: 16, color: neutral600),
                    const SizedBox(width: 4),
                    Text(
                        'Target: ${survey.targetAudience!.join(', ')}',
                        style: regularTextStyle(size: 12, color: neutral600),
                    ),
                    ],
                ),
            ],
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: Icon(Icons.bar_chart, size: 18, color: kbpGreen700),
                  label: Text('Hasil', style: mediumTextStyle(color: kbpGreen700)),
                  onPressed: () {
                     Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => SurveyResultsScreen(surveyId: survey.surveyId),
                        ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: Icon(Icons.edit_outlined, size: 18, color: kbpBlue700),
                  label: Text('Edit', style: mediumTextStyle(color: kbpBlue700)),
                  onPressed: () {
                     Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CreateEditSurveyScreen(surveyToEdit: survey),
                        ),
                    ).then((_){
                        final authState = context.read<AuthBloc>().state;
                        if (authState is AuthAuthenticated) {
                            _refreshSurveys(authState.user.id);
                        }
                    });
                  },
                ),
                 const SizedBox(width: 8),
                TextButton.icon(
                  icon: Icon(Icons.delete_outline, size: 18, color: dangerR500),
                  label: Text('Hapus', style: mediumTextStyle(color: dangerR500)),
                  onPressed: () => _showDeleteConfirmationDialog(context, survey),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}