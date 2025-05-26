import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/survey.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/survey/survey_bloc.dart';

class SurveyResponseScreen extends StatefulWidget {
  final String surveyId;
  final String userId;

  const SurveyResponseScreen({
    Key? key,
    required this.surveyId,
    required this.userId,
  }) : super(key: key);

  @override
  State<SurveyResponseScreen> createState() => _SurveyResponseScreenState();
}

class _SurveyResponseScreenState extends State<SurveyResponseScreen> {
  Survey? _survey;
  SurveyResponse? _response;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSurveyAndResponse();
  }

  Future<void> _loadSurveyAndResponse() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load survey dan respons user
      context.read<SurveyBloc>().add(LoadSurveyById(widget.surveyId));
      context
          .read<SurveyBloc>()
          .add(LoadUserSurveyResponse(widget.surveyId, widget.userId));
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Gagal memuat data: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Respons Survei',
          style: semiBoldTextStyle(size: 18, color: Colors.white),
        ),
        backgroundColor: kbpBlue900,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: BlocListener<SurveyBloc, SurveyState>(
        listener: (context, state) {
          if (state is SurveyLoaded) {
            setState(() {
              _survey = state.survey;
            });
          } else if (state is UserSurveyResponseLoaded) {
            setState(() {
              _response = state.response;
              _isLoading = false;
            });
          } else if (state is SurveyError) {
            setState(() {
              _isLoading = false;
              _errorMessage = state.message;
            });
            showCustomSnackbar(
              context: context,
              title: 'Error',
              subtitle: state.message,
              type: SnackbarType.danger,
            );
          }
        },
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 80, color: dangerR500),
              const SizedBox(height: 16),
              Text(
                'Gagal memuat respons',
                style: semiBoldTextStyle(size: 18, color: neutral900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: regularTextStyle(size: 14, color: neutral700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadSurveyAndResponse,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kbpBlue900,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_survey == null || _response == null) {
      return Center(
        child: Text(
          'Data tidak ditemukan',
          style: mediumTextStyle(size: 16, color: neutral700),
        ),
      );
    }

    // Tampilkan respons survey
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _survey!.title,
                    style: semiBoldTextStyle(size: 20, color: neutral900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _survey!.description,
                    style: regularTextStyle(size: 14, color: neutral700),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: 16, color: successG500),
                      const SizedBox(width: 4),
                      Text(
                        'Diisi pada: ${_formatDate(_response!.submittedAt)}',
                        style: mediumTextStyle(size: 12, color: neutral700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // TODO: Tampilkan pertanyaan dan jawaban yang sudah diisi
          // Anda perlu mengimplementasikan renderingnya sesuai dengan tipe pertanyaan

          // Contoh tampilan placeholder
          Text(
            'Jawaban Survei',
            style: semiBoldTextStyle(size: 18, color: neutral900),
          ),
          const SizedBox(height: 16),

          // Untuk setiap section
          ..._survey!.sections.map((section) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.title,
                          style: semiBoldTextStyle(size: 16, color: neutral900),
                        ),
                        if (section.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            section.description,
                            style:
                                regularTextStyle(size: 14, color: neutral700),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Untuk setiap pertanyaan dalam section
                        ...section.questions.map((question) {
                          return _buildQuestionResponse(
                              question, _response!.answers[question.id]);
                        }).toList(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildQuestionResponse(SurveyQuestion question, dynamic answer) {
    if (answer == null) {
      return const SizedBox.shrink();
    }

    // Tampilkan pertanyaan
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.question,
            style: mediumTextStyle(size: 14, color: neutral900),
          ),
          const SizedBox(height: 8),

          // Tampilkan jawaban berdasarkan tipe pertanyaan
          if (question.type == QuestionType.shortAnswer ||
              question.type == QuestionType.longAnswer)
            Text(
              answer['answer'] ?? 'Tidak ada jawaban',
              style: regularTextStyle(size: 14, color: neutral700),
            )
          else if (question.type == QuestionType.singleChoice)
            Text(
              answer['answer'] == 'custom'
                  ? answer['customAnswer'] ?? 'Jawaban kustom tidak tersedia'
                  : answer['answer'] ?? 'Tidak ada jawaban',
              style: regularTextStyle(size: 14, color: neutral700),
            )
          else if (question.type == QuestionType.multipleChoice)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...(answer['answers'] as List<dynamic>? ?? []).map((choice) {
                  return Text(
                    '• $choice',
                    style: regularTextStyle(size: 14, color: neutral700),
                  );
                }).toList(),
                if (answer['customAnswer'] != null &&
                    answer['customAnswer'].toString().isNotEmpty)
                  Text(
                    '• ${answer['customAnswer']}',
                    style: regularTextStyle(size: 14, color: neutral700),
                  ),
              ],
            )
          else if (question.type == QuestionType.likert)
            Row(
              children: [
                Text(
                  'Nilai: ${answer['value']}',
                  style: mediumTextStyle(size: 14, color: kbpBlue900),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: answer['value'] / (question.likertScale ?? 5),
                    backgroundColor: neutral200,
                    valueColor: AlwaysStoppedAnimation<Color>(kbpBlue700),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),

          const Divider(height: 32),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
  }
}
