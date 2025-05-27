import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/survey/answer.dart';
import 'package:livetrackingapp/domain/entities/survey/survey.dart';
import 'package:livetrackingapp/domain/entities/survey/survey_response.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/survey/bloc/survey_bloc.dart';
import 'package:livetrackingapp/presentation/survey/screens/question_widget.dart';
import 'package:uuid/uuid.dart';

class FillSurveyScreen extends StatefulWidget {
  final String surveyId;
  final String userId;

  const FillSurveyScreen({super.key, required this.surveyId, required this.userId});

  @override
  State<FillSurveyScreen> createState() => _FillSurveyScreenState();
}

class _FillSurveyScreenState extends State<FillSurveyScreen> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> _answers = {}; // Key: questionId, Value: answerValue
  int _currentSectionIndex = 0;
  PageController _pageController = PageController();
  Survey? _survey;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    context.read<SurveyBloc>().add(LoadSurveyForFilling(surveyId: widget.surveyId, userId: widget.userId));
  }

  void _onAnswerChanged(String questionId, dynamic value) {
    setState(() {
      _answers[questionId] = value;
    });
  }

  void _submitSurvey() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save(); // Pastikan semua onSaved terpanggil

      // Validasi pertanyaan yang wajib diisi di section terakhir
      if (_survey != null && _survey!.sections.isNotEmpty) {
        final lastSection = _survey!.sections[_currentSectionIndex];
        for (var question in lastSection.questions) {
          if (question.isRequired && (_answers[question.questionId] == null || _answers[question.questionId].toString().isEmpty)) {
            showCustomSnackbar(
                context: context,
                title: 'Validasi Gagal',
                subtitle: 'Pertanyaan "${question.text}" wajib diisi.',
                type: SnackbarType.warning);
            return;
          }
        }
      }


      List<Answer> answerEntities = [];
      _answers.forEach((questionId, value) {
        answerEntities.add(Answer(questionId: questionId, answerValue: value));
      });

      final surveyResponse = SurveyResponse(
        responseId: Uuid().v4(), // Generate unique ID
        surveyId: widget.surveyId,
        userId: widget.userId,
        submittedAt: DateTime.now(),
        answers: answerEntities,
      );
      context.read<SurveyBloc>().add(SubmitSurvey(response: surveyResponse));
    } else {
       showCustomSnackbar(
          context: context,
          title: 'Form Tidak Valid',
          subtitle: 'Harap periksa kembali jawaban Anda.',
          type: SnackbarType.warning);
    }
  }

  void _nextSection() {
     if (_survey == null || _currentSectionIndex >= _survey!.sections.length -1) return;

     // Validasi pertanyaan yang wajib diisi di section saat ini
    final currentSection = _survey!.sections[_currentSectionIndex];
    for (var question in currentSection.questions) {
        if (question.isRequired && (_answers[question.questionId] == null || _answers[question.questionId].toString().isEmpty)) {
             showCustomSnackbar(
                context: context,
                title: 'Validasi Gagal',
                subtitle: 'Pertanyaan "${question.text}" di bagian ini wajib diisi.',
                type: SnackbarType.warning);
            return; // Jangan pindah section jika ada yang belum diisi
        }
    }

    _pageController.nextPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _previousSection() {
    _pageController.previousPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_survey?.title ?? 'Isi Survei'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
      ),
      body: BlocConsumer<SurveyBloc, SurveyState>(
        listener: (context, state) {
          if (state is SurveyFormLoaded) {
            setState(() {
              _survey = state.survey;
              // Jika ada existing response, pre-fill answers
              if (state.existingResponse != null) {
                final tempAnswers = <String, dynamic>{};
                for (var answer in state.existingResponse!.answers) {
                  tempAnswers[answer.questionId] = answer.answerValue;
                }
                _answers = tempAnswers;
              }
            });
          } else if (state is SurveyOperationSuccess) {
            showCustomSnackbar(
                context: context,
                title: 'Sukses',
                subtitle: state.message,
                type: SnackbarType.success);
            Navigator.of(context).pop(); // Kembali ke halaman sebelumnya
          } else if (state is SurveyError) {
            showCustomSnackbar(
                context: context,
                title: 'Error',
                subtitle: state.message,
                type: SnackbarType.danger);
             setState(() {
              _isSubmitting = false;
            });
          } else if (state is SurveyLoading) {
            setState(() {
                _isSubmitting = true;
            });
          }
          if (state is! SurveyLoading) {
            setState(() {
                _isSubmitting = false;
            });
          }
        },
        builder: (context, state) {
          if (state is SurveyLoading && _survey == null) {
            return const Center(child: CircularProgressIndicator());
          } else if (_survey == null) {
             return Center(
              child: EmptyState(
                icon: Icons.error_outline,
                title: 'Gagal Memuat Survei',
                subtitle: 'Tidak dapat memuat detail survei. Silakan coba lagi.',
                buttonText: 'Kembali',
                onButtonPressed: () => Navigator.of(context).pop(),
              ),
            );
          }

          final surveySections = _survey!.sections;
          if (surveySections.isEmpty) {
            return const Center(child: Text('Survei ini tidak memiliki pertanyaan.'));
          }

          return Form(
            key: _formKey,
            child: Column(
              children: [
                // Section Indicator (Optional)
                if (surveySections.length > 1)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Bagian ${_currentSectionIndex + 1} dari ${surveySections.length}: ${surveySections[_currentSectionIndex].title}',
                      style: semiBoldTextStyle(size: 16, color: kbpBlue700),
                    ),
                  ),

                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: surveySections.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentSectionIndex = index;
                      });
                    },
                    itemBuilder: (context, sectionIdx) {
                      final section = surveySections[sectionIdx];
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (section.description != null && section.description!.isNotEmpty)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 16.0),
                                    child: Text(section.description!, style: regularTextStyle(color: neutral700)),
                                ),
                            ...section.questions.map((question) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 20.0),
                                child: QuestionWidget(
                                  question: question,
                                  initialValue: _answers[question.questionId],
                                  onAnswerChanged: (value) {
                                    _onAnswerChanged(question.questionId, value);
                                  },
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentSectionIndex > 0)
                        OutlinedButton.icon(
                           icon: const Icon(Icons.arrow_back),
                          label: const Text('Sebelumnya'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: kbpBlue700,
                              side: const BorderSide(color: kbpBlue700),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          onPressed: _previousSection,
                        )
                      else
                        const SizedBox(), // Placeholder

                      ElevatedButton.icon(
                        icon: _isSubmitting
                            ? Container(
                                width: 20,
                                height: 20,
                                child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(_currentSectionIndex == surveySections.length - 1
                                ? Icons.check_circle_outline
                                : Icons.arrow_forward),
                        label: Text(
                          _isSubmitting
                            ? 'Mengirim...'
                            : _currentSectionIndex == surveySections.length - 1
                                ? 'Kirim Survei'
                                : 'Berikutnya',
                        ),
                         style: ElevatedButton.styleFrom(
                            backgroundColor: kbpBlue900,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        onPressed: _isSubmitting
                          ? null
                          : (_currentSectionIndex == surveySections.length - 1
                              ? _submitSurvey
                              : _nextSection),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}