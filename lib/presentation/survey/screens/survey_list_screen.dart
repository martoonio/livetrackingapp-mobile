import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/user.dart' as app_user;
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/auth/bloc/auth_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/survey/bloc/survey_bloc.dart';
import 'package:livetrackingapp/domain/entities/survey/survey.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/presentation/survey/screens/fill_survey_screen.dart';
import 'package:livetrackingapp/presentation/survey/screens/survey_results_screen.dart';


class SurveyListScreen extends StatefulWidget {
  const SurveyListScreen({super.key});

  @override
  State<SurveyListScreen> createState() => _SurveyListScreenState();
}

class _SurveyListScreenState extends State<SurveyListScreen> {
  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context.read<SurveyBloc>().add(LoadActiveSurveys(
            userId: authState.user.id,
            userRole: authState.user.role,
            clusterId: authState.user.role == 'patrol' ? authState.user.id : null, // Asumsi clusterId sama dengan userId untuk patrol
          ));
    }
  }

  Future<void> _refreshSurveys() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context.read<SurveyBloc>().add(LoadActiveSurveys(
            userId: authState.user.id,
            userRole: authState.user.role,
            clusterId: authState.user.role == 'patrol' ? authState.user.id : null,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final User? currentUser = (authState is AuthAuthenticated) ? authState.user : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Survei Aktif'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _refreshSurveys,
        child: BlocConsumer<SurveyBloc, SurveyState>(
          listener: (context, state) {
            if (state is SurveyError) {
              showCustomSnackbar(
                  context: context,
                  title: 'Error',
                  subtitle: state.message,
                  type: SnackbarType.danger);
            }
          },
          builder: (context, state) {
            if (state is SurveyLoading && !(state is ActiveSurveysLoaded)) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is ActiveSurveysLoaded) {
              if (state.surveys.isEmpty) {
                return Center(
                  child: EmptyState(
                    icon: Icons.playlist_add_check_circle_outlined,
                    title: 'Tidak Ada Survei',
                    subtitle: 'Saat ini tidak ada survei aktif yang tersedia untuk Anda.',
                    buttonText: 'Segarkan',
                    onButtonPressed: _refreshSurveys,
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: state.surveys.length,
                itemBuilder: (context, index) {
                  final survey = state.surveys[index];
                  return _buildSurveyCard(context, survey, currentUser);
                },
              );
            }
            return const Center(child: Text('Silakan segarkan halaman.'));
          },
        ),
      ),
    );
  }

  Widget _buildSurveyCard(BuildContext context, Survey survey, app_user.User? currentUser) {
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (currentUser != null) {
             Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FillSurveyScreen(surveyId: survey.surveyId, userId: currentUser.id),
                ),
              );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(survey.title, style: boldTextStyle(size: 18, color: kbpBlue900)),
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
                  Icon(Icons.person_outline, size: 16, color: neutral600),
                  const SizedBox(width: 4),
                  Text(
                    'Dibuat oleh: Tim Pusat', // Anda mungkin ingin menyimpan nama pembuat survei
                    style: regularTextStyle(size: 12, color: neutral600),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 16, color: neutral600),
                  const SizedBox(width: 4),
                  Text(
                    'Dibuat pada: ${dateFormat.format(survey.createdAt)}',
                    style: regularTextStyle(size: 12, color: neutral600),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (currentUser?.role == 'commandCenter')
                    TextButton.icon(
                      icon: Icon(Icons.bar_chart, size: 18, color: kbpGreen700),
                      label: Text('Lihat Hasil', style: mediumTextStyle(color: kbpGreen700)),
                      onPressed: () {
                         Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => SurveyResultsScreen(surveyId: survey.surveyId),
                            ),
                        );
                      },
                    ),
                  if (currentUser?.role == 'commandCenter') const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: Icon(Icons.edit_note, size: 18),
                    label: const Text('Isi Survei'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kbpBlue700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                       if (currentUser != null) {
                           Navigator.push(
                                context,
                                MaterialPageRoute(
                                builder: (_) => FillSurveyScreen(surveyId: survey.surveyId, userId: currentUser.id),
                                ),
                            );
                       }
                    },
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}