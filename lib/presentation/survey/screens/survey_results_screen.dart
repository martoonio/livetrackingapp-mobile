import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/survey/question.dart';
import 'package:livetrackingapp/domain/entities/survey/survey.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/survey/bloc/survey_bloc.dart';
// Import chart library jika diperlukan, contoh: fl_chart
// import 'package:fl_chart/fl_chart.dart';

class SurveyResultsScreen extends StatefulWidget {
  final String surveyId;

  const SurveyResultsScreen({super.key, required this.surveyId});

  @override
  State<SurveyResultsScreen> createState() => _SurveyResultsScreenState();
}

class _SurveyResultsScreenState extends State<SurveyResultsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<SurveyBloc>().add(LoadResultsForSurvey(surveyId: widget.surveyId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hasil Survei'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
      ),
      body: BlocBuilder<SurveyBloc, SurveyState>(
        builder: (context, state) {
          if (state is SurveyLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is SurveyResultsLoaded) {
            final survey = state.survey;
            final summary = state.summary;
            final totalResponses = summary['totalResponses'] ?? 0;

            if (totalResponses == 0) {
              return Center(
                child: EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Belum Ada Responden',
                  subtitle: 'Survei "${survey.title}" belum memiliki tanggapan.',
                  buttonText: 'Kembali',
                  onButtonPressed: () => Navigator.of(context).pop(),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Text(survey.title, style: boldTextStyle(size: 20, color: kbpBlue800)),
                if (survey.description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                    child: Text(survey.description!, style: regularTextStyle(color: neutral700)),
                  ),
                Text('Total Responden: $totalResponses', style: semiBoldTextStyle(color: kbpGreen700)),
                const Divider(height: 24),
                ..._buildSummaryWidgets(survey, summary),
                // TODO: Tambahkan opsi untuk melihat jawaban individual jika perlu
              ],
            );
          } else if (state is SurveyError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          return const Center(child: Text('Memuat hasil survei...'));
        },
      ),
    );
  }

  List<Widget> _buildSummaryWidgets(Survey survey, Map<String, dynamic> summary) {
    List<Widget> widgets = [];
    for (var section in survey.sections) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
        child: Text(section.title, style: boldTextStyle(size: 18, color: kbpBlue700)),
      ));
      if (section.description != null && section.description!.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(section.description!, style: regularTextStyle(color: neutral600)),
          ));
      }

      for (var question in section.questions) {
        widgets.add(Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(question.text, style: semiBoldTextStyle(size: 16)),
                const SizedBox(height: 8),
                _buildQuestionSummary(question, summary[question.questionId]),
              ],
            ),
          ),
        ));
      }
    }
    return widgets;
  }

  Widget _buildQuestionSummary(Question question, dynamic questionSummaryData) {
    if (questionSummaryData == null) {
      return Text('Tidak ada data untuk pertanyaan ini.', style: regularTextStyle(color: neutral500));
    }

    final String type = questionSummaryData['type'] ?? '';
    final int responseCount = questionSummaryData['responses'] ?? 0;

     if (responseCount == 0) {
      return Text('Belum ada tanggapan untuk pertanyaan ini.', style: regularTextStyle(color: neutral500));
    }


    switch (stringToQuestionType(type)) {
      case QuestionType.likertScale:
        final double average = questionSummaryData['average']?.toDouble() ?? 0.0;
        final int min = questionSummaryData['min'] ?? 1;
        final int max = questionSummaryData['max'] ?? 5;
        final String minLabel = questionSummaryData['minLabel'] ?? min.toString();
        final String maxLabel = questionSummaryData['maxLabel'] ?? max.toString();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rata-rata: ${average.toStringAsFixed(1)} dari $max', style: regularTextStyle()),
             const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (average - min) / (max - min == 0 ? 1 : max - min), // handle division by zero
              backgroundColor: kbpBlue100,
              valueColor: AlwaysStoppedAnimation<Color>(kbpBlue700),
              minHeight: 10,
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(minLabel, style: regularTextStyle(size: 12)), Text(maxLabel, style: regularTextStyle(size: 12))]),
          ],
        );
      case QuestionType.multipleChoice:
      case QuestionType.checkboxes:
        final Map<String, int> counts = Map<String, int>.from(questionSummaryData['counts'] ?? {});
        final List<String> options = List<String>.from(questionSummaryData['options'] ?? question.options ?? []);
         if (options.isEmpty) return Text('Tidak ada opsi jawaban.', style: regularTextStyle(color: neutral500));

        return Column(
          children: options.map((option) {
            final count = counts[option] ?? 0;
            final percentage = responseCount > 0 ? (count / responseCount) * 100 : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  Expanded(child: Text('$option:', style: regularTextStyle())),
                  Text('$count ($responseCount)', style: semiBoldTextStyle()),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100, // Lebar progress bar
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: neutral200,
                      valueColor: AlwaysStoppedAnimation<Color>(kbpGreen500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${percentage.toStringAsFixed(0)}%', style: regularTextStyle(size: 12)),

                ],
              ),
            );
          }).toList(),
        );
      case QuestionType.shortAnswer:
      case QuestionType.longAnswer:
        final List<String> answers = List<String>.from(questionSummaryData['answers'] ?? []);
         if (answers.isEmpty) return Text('Tidak ada jawaban teks.', style: regularTextStyle(color: neutral500));
        // Tampilkan beberapa contoh jawaban
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contoh Jawaban (${answers.length} total):', style: mediumTextStyle()),
            ...answers.take(3).map((ans) => Padding(
                padding: const EdgeInsets.only(top:4.0, left: 8.0),
                child: Text('• $ans', style: regularTextStyle(color: neutral700)),
            )).toList(),
            if (answers.length > 3)
                Text('... dan lainnya.', style: regularTextStyle(color: neutral600, size: 12)),
          ],
        );
      default:
        return Text('Tipe pertanyaan ini belum didukung untuk ringkasan.', style: regularTextStyle(color: neutral500));
    }
  }
}