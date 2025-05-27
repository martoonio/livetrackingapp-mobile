import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/survey/question.dart';
import 'package:livetrackingapp/domain/entities/survey/survey.dart';
import 'package:livetrackingapp/presentation/auth/bloc/auth_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/survey/bloc/survey_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class SurveyResultsScreen extends StatefulWidget {
  final String surveyId;

  const SurveyResultsScreen({super.key, required this.surveyId});

  @override
  State<SurveyResultsScreen> createState() => _SurveyResultsScreenState();
}

class _SurveyResultsScreenState extends State<SurveyResultsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showAllTextResponses = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    context
        .read<SurveyBloc>()
        .add(LoadResultsForSurvey(surveyId: widget.surveyId));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analisis Hasil Survei'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelStyle: boldTextStyle(color: Colors.white),
          unselectedLabelStyle: regularTextStyle(color: Colors.white70),
          tabs: const [
            Tab(text: 'Ringkasan'),
            Tab(text: 'Detail'),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
            final authState = context.read<AuthBloc>().state;
            if (authState is AuthAuthenticated) {
              context.read<SurveyBloc>().add(LoadAllCommandCenterSurveys(
                  commandCenterId: authState.user.id));
            }
            ;
          },
        ),
      ),
      body: WillPopScope(
        onWillPop: () async {
          // Kembali ke halaman sebelumnya dan muat ulang survei
          final authState = context.read<AuthBloc>().state;
          if (authState is AuthAuthenticated) {
            context.read<SurveyBloc>().add(LoadAllCommandCenterSurveys(
                commandCenterId: authState.user.id));
          }
          return true; // Izinkan pop
        },
        child: BlocBuilder<SurveyBloc, SurveyState>(
          builder: (context, state) {
            if (state is SurveyLoading) {
              return const Center(
                  child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Menganalisis hasil survei...')
                ],
              ));
            } else if (state is SurveyResultsLoaded) {
              final survey = state.survey;
              final summary = state.summary;
              final totalResponses = summary['totalResponses'] ?? 0;

              if (totalResponses == 0) {
                return Center(
                  child: EmptyState(
                    icon: Icons.analytics_outlined,
                    title: 'Belum Ada Responden',
                    subtitle:
                        'Survei "${survey.title}" belum memiliki tanggapan.',
                    buttonText: 'Kembali',
                    onButtonPressed: () => Navigator.of(context).pop(),
                  ),
                );
              }

              return TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Ringkasan
                  _buildSummaryTab(survey, summary, totalResponses),

                  // Tab 2: Detail
                  _buildDetailTab(survey, summary),
                ],
              );
            } else if (state is SurveyError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: dangerR400, size: 48),
                    const SizedBox(height: 16),
                    Text('Error: ${state.message}',
                        style: mediumTextStyle(color: dangerR500)),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        context.read<SurveyBloc>().add(
                            LoadResultsForSurvey(surveyId: widget.surveyId));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kbpBlue700,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              );
            }
            return const Center(child: Text('Mempersiapkan hasil survei...'));
          },
        ),
      ),
    );
  }

  // Tab 1: Ringkasan
  Widget _buildSummaryTab(
      Survey survey, Map<String, dynamic> summary, int totalResponses) {
    // Format tanggal untuk menampilkan kapan survei dibuat
    final dateFormatter = DateFormat('d MMMM yyyy');
    final surveyCreatedDate = dateFormatter.format(survey.createdAt);

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Header dengan informasi survei
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kbpBlue800, kbpBlue700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                survey.title,
                style: boldTextStyle(size: 22, color: Colors.white),
              ),
              if (survey.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    survey.description!,
                    style:
                        regularTextStyle(color: Colors.white.withOpacity(0.9)),
                  ),
                ),
              const SizedBox(height: 16),

              // Statistik utama survei
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSummaryTile('Total Responden',
                      totalResponses.toString(), Icons.people_alt_outlined),
                  _buildSummaryTile(
                      'Total Pertanyaan',
                      _getTotalQuestions(survey).toString(),
                      Icons.quiz_outlined),
                  _buildSummaryTile('Dibuat Pada', surveyCreatedDate,
                      Icons.calendar_today_outlined),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Highlight statistik penting
        Text(
          'Highlights',
          style: boldTextStyle(size: 20, color: kbpBlue800),
        ),
        const SizedBox(height: 12),

        // Statistik highlight dalam card
        _buildHighlightsSection(survey, summary),

        const SizedBox(height: 24),

        // Ringkasan per tipe pertanyaan
        Text(
          'Ringkasan Berdasarkan Tipe Pertanyaan',
          style: boldTextStyle(size: 20, color: kbpBlue800),
        ),
        const SizedBox(height: 12),
        _buildQuestionTypeSummary(survey, summary),
      ],
    );
  }

  // Tab 2: Detail
  Widget _buildDetailTab(Survey survey, Map<String, dynamic> summary) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        ..._buildSummaryWidgets(survey, summary),
      ],
    );
  }

  // Mendapatkan jumlah total pertanyaan di survei
  int _getTotalQuestions(Survey survey) {
    int count = 0;
    for (var section in survey.sections) {
      count += section.questions.length;
    }
    return count;
  }

  // Widget untuk menampilkan statistik utama di header
  Widget _buildSummaryTile(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: boldTextStyle(size: 14, color: Colors.white),
          ),
          Text(
            title,
            style: regularTextStyle(
                size: 12, color: Colors.white.withOpacity(0.9)),
          ),
        ],
      ),
    );
  }

  // Widget untuk menampilkan highlights penting dari survei
  Widget _buildHighlightsSection(Survey survey, Map<String, dynamic> summary) {
    // Cari pertanyaan dengan rating tertinggi dan terendah
    Question? highestRatedQuestion;
    Question? lowestRatedQuestion;
    double highestAvg = 0;
    double lowestAvg = 5;

    // Pertanyaan dengan respons terbanyak
    Question? mostAnsweredQuestion;
    int mostAnswers = 0;

    // Analisis data untuk menemukan highlights
    for (var section in survey.sections) {
      for (var question in section.questions) {
        final data = summary[question.questionId];
        if (data != null) {
          final int responses = data['responses'] ?? 0;

          if (responses > mostAnswers) {
            mostAnswers = responses;
            mostAnsweredQuestion = question;
          }

          if (question.type == QuestionType.likertScale) {
            final double avg = data['average']?.toDouble() ?? 0.0;
            if (avg > highestAvg && responses > 0) {
              highestAvg = avg;
              highestRatedQuestion = question;
            }
            if (avg < lowestAvg && avg > 0 && responses > 0) {
              lowestAvg = avg;
              lowestRatedQuestion = question;
            }
          }
        }
      }
    }

    return Column(
      children: [
        if (highestRatedQuestion != null)
          _buildHighlightCard(
            'Pertanyaan Dengan Rating Tertinggi',
            highestRatedQuestion.text,
            'Rating rata-rata: ${highestAvg.toStringAsFixed(1)}',
            kbpGreen500,
            Icons.thumb_up_outlined,
          ),
        if (lowestRatedQuestion != null)
          _buildHighlightCard(
            'Pertanyaan Dengan Rating Terendah',
            lowestRatedQuestion.text,
            'Rating rata-rata: ${lowestAvg.toStringAsFixed(1)}',
            dangerR400,
            Icons.thumb_down_outlined,
          ),
        if (mostAnsweredQuestion != null && mostAnswers > 0)
          _buildHighlightCard(
            'Pertanyaan Dengan Respons Terbanyak',
            mostAnsweredQuestion.text,
            '$mostAnswers responden',
            kbpBlue500,
            Icons.question_answer_outlined,
          ),
      ],
    );
  }

  // Card untuk menampilkan highlight
  Widget _buildHighlightCard(String title, String question, String statistic,
      Color color, IconData icon) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: semiBoldTextStyle(color: color)),
                  const SizedBox(height: 4),
                  Text(question, style: mediumTextStyle()),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statistic,
                      style: boldTextStyle(color: color),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Ringkasan distribusi tipe pertanyaan
  Widget _buildQuestionTypeSummary(
      Survey survey, Map<String, dynamic> summary) {
    // Hitung jumlah pertanyaan berdasarkan tipe
    final Map<QuestionType, int> typeCounts = {};
    int totalQuestions = 0;

    for (var section in survey.sections) {
      for (var question in section.questions) {
        typeCounts[question.type] = (typeCounts[question.type] ?? 0) + 1;
        totalQuestions++;
      }
    }

    // Warna untuk setiap tipe pertanyaan
    final typeColors = {
      QuestionType.likertScale: kbpBlue500,
      QuestionType.multipleChoice: kbpGreen500,
      QuestionType.checkboxes: warningY500,
      QuestionType.shortAnswer: kbpBlue300,
      QuestionType.longAnswer: kbpBlue700,
    };

    // Label yang lebih user-friendly untuk setiap tipe
    final typeLabels = {
      QuestionType.likertScale: 'Skala Likert',
      QuestionType.multipleChoice: 'Pilihan Ganda',
      QuestionType.checkboxes: 'Kotak Centang',
      QuestionType.shortAnswer: 'Jawaban Singkat',
      QuestionType.longAnswer: 'Jawaban Panjang',
    };

    // Prepare data untuk pie chart
    final List<PieChartSectionData> pieData = [];
    typeCounts.forEach((type, count) {
      final percentage = (count / totalQuestions) * 100;
      pieData.add(
        PieChartSectionData(
          value: count.toDouble(),
          title: '${percentage.toStringAsFixed(0)}%',
          color: typeColors[type] ?? neutral500,
          radius: 80,
          titleStyle: boldTextStyle(color: Colors.white, size: 14),
          badgeWidget: _getBadgeForQuestionType(type),
          badgePositionPercentageOffset: 1.0,
        ),
      );
    });

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Distribusi Tipe Pertanyaan',
              style: boldTextStyle(size: 16, color: kbpBlue800),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: pieData,
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Legend
            ...typeCounts.entries.map((entry) {
              final type = entry.key;
              final count = entry.value;
              final percentage = (count / totalQuestions) * 100;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: typeColors[type] ?? neutral500,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        typeLabels[type] ?? type.toString(),
                        style: mediumTextStyle(),
                      ),
                    ),
                    Text(
                      '$count (${percentage.toStringAsFixed(0)}%)',
                      style: semiBoldTextStyle(),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  // Badge icon untuk tipe pertanyaan pada pie chart
  Widget _getBadgeForQuestionType(QuestionType type) {
    IconData iconData;

    switch (type) {
      case QuestionType.likertScale:
        iconData = Icons.star_rate;
        break;
      case QuestionType.multipleChoice:
        iconData = Icons.radio_button_checked;
        break;
      case QuestionType.checkboxes:
        iconData = Icons.check_box;
        break;
      case QuestionType.shortAnswer:
        iconData = Icons.short_text;
        break;
      case QuestionType.longAnswer:
        iconData = Icons.text_fields;
        break;
      default:
        iconData = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, size: 16),
    );
  }

  // Detail untuk setiap pertanyaan
  List<Widget> _buildSummaryWidgets(
      Survey survey, Map<String, dynamic> summary) {
    List<Widget> widgets = [];

    // Export button
    widgets.add(
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: OutlinedButton.icon(
          onPressed: () {
            // TODO: Implement export functionality
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Ekspor hasil survei belum diimplementasikan')),
            );
          },
          icon: const Icon(Icons.download),
          label: const Text('Ekspor Hasil'),
          style: OutlinedButton.styleFrom(
            foregroundColor: kbpBlue700,
            side: BorderSide(color: kbpBlue700),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
        ),
      ),
    );

    // Daftar section dan pertanyaan
    for (var section in survey.sections) {
      widgets.add(
        Container(
          margin: const EdgeInsets.only(top: 8.0, bottom: 4.0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: kbpBlue800,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.assignment, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  section.title,
                  style: boldTextStyle(size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );

      if (section.description != null && section.description!.isNotEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0, left: 4.0, right: 4.0),
            child: Text(
              section.description!,
              style: regularTextStyle(color: neutral600),
            ),
          ),
        );
      }

      for (var question in section.questions) {
        widgets.add(
          Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: kbpBlue200, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _getIconForQuestionType(question.type),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          question.text,
                          style: semiBoldTextStyle(size: 16, color: kbpBlue900),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildEnhancedQuestionSummary(
                      question, summary[question.questionId]),
                ],
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  // Icon untuk tipe pertanyaan
  Widget _getIconForQuestionType(QuestionType type) {
    IconData iconData;
    Color iconColor;

    switch (type) {
      case QuestionType.likertScale:
        iconData = Icons.star_rate;
        iconColor = kbpBlue700;
        break;
      case QuestionType.multipleChoice:
        iconData = Icons.radio_button_checked;
        iconColor = kbpGreen600;
        break;
      case QuestionType.checkboxes:
        iconData = Icons.check_box;
        iconColor = warningY500;
        break;
      case QuestionType.shortAnswer:
        iconData = Icons.short_text;
        iconColor = kbpBlue500;
        break;
      case QuestionType.longAnswer:
        iconData = Icons.text_fields;
        iconColor = kbpBlue600;
        break;
      default:
        iconData = Icons.help_outline;
        iconColor = neutral500;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(iconData, color: iconColor, size: 20),
    );
  }

  // Enhanced summary untuk setiap pertanyaan
  Widget _buildEnhancedQuestionSummary(
      Question question, dynamic questionSummaryData) {
    if (questionSummaryData == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: neutral300,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: neutral500, size: 20),
            const SizedBox(width: 8),
            Text('Tidak ada data untuk pertanyaan ini.',
                style: regularTextStyle(color: neutral500)),
          ],
        ),
      );
    }

    final String typeString = questionSummaryData['type'] ?? '';
    final QuestionType type = stringToQuestionType(typeString);
    final int responseCount = questionSummaryData['responses'] ?? 0;

    if (responseCount == 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: neutral300,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.pending_outlined, color: neutral500, size: 20),
            const SizedBox(width: 8),
            Text('Belum ada tanggapan untuk pertanyaan ini.',
                style: regularTextStyle(color: neutral500)),
          ],
        ),
      );
    }

    switch (type) {
      case QuestionType.likertScale:
        final int min =
            questionSummaryData['min'] ?? question.likertScaleMin ?? 1;
        final int max =
            questionSummaryData['max'] ?? question.likertScaleMax ?? 5;
        final String minLabel = questionSummaryData['minLabel'] ??
            question.likertMinLabel ??
            min.toString();
        final String maxLabel = questionSummaryData['maxLabel'] ??
            question.likertMaxLabel ??
            max.toString();

        Map<String, int> distribution = {};
        if (questionSummaryData['distribution'] != null) {
          distribution =
              Map<String, int>.from(questionSummaryData['distribution']);
        } else {
          for (int i = min; i <= max; i++) {
            distribution[i.toString()] = 0;
          }
        }

        double average = questionSummaryData['average']?.toDouble() ?? 0.0;
        if (average == 0.0 && responseCount > 0) {
          int totalSum = 0;
          distribution.forEach((valueStr, count) {
            totalSum += (int.tryParse(valueStr) ?? 0) * count;
          });
          average = totalSum / responseCount;
        }

        // Prepare data for bar chart
        final List<BarChartGroupData> barGroups = [];
        for (int i = min; i <= max; i++) {
          final count = distribution[i.toString()] ?? 0;
          final percentage =
              responseCount > 0 ? (count / responseCount) * 100 : 0.0;

          barGroups.add(
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: count.toDouble(),
                  color: i < (max + min) / 2
                      ? dangerR300
                      : i == (max + min) / 2
                          ? warningY400
                          : kbpGreen500,
                  width: 22,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rata-rata dan visualisasi
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kbpBlue50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kbpBlue200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Rating Rata-Rata',
                          style: mediumTextStyle(color: kbpBlue800)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getRatingColor(average, min, max),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.star,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              average.toStringAsFixed(1),
                              style:
                                  boldTextStyle(color: Colors.white, size: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Star rating visualization
                  _buildStarRating(average, max),

                  const SizedBox(height: 8),

                  // Progress bar untuk rata-rata
                  LinearProgressIndicator(
                    value: (average - min) / (max - min == 0 ? 1 : max - min),
                    backgroundColor: kbpBlue100,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        _getRatingColor(average, min, max)),
                    minHeight: 10,
                  ),
                  const SizedBox(height: 4),

                  // Labels
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(minLabel,
                          style: regularTextStyle(size: 12, color: neutral600)),
                      Text(maxLabel,
                          style: regularTextStyle(size: 12, color: neutral600)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Bar chart untuk distribusi
            Text('Distribusi Respons',
                style: mediumTextStyle(color: kbpBlue800)),
            const SizedBox(height: 12),

            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (distribution.values.isEmpty
                              ? 0
                              : distribution.values
                                  .reduce((a, b) => a > b ? a : b))
                          .toDouble() *
                      1.2,
                  barGroups: barGroups,
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(
                              value.toInt().toString(),
                              style: regularTextStyle(size: 12),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox();
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(
                              value.toInt().toString(),
                              style: regularTextStyle(size: 10),
                            ),
                          );
                        },
                        reservedSize: 30,
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: neutral200,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Detail numbers
            ...List.generate(max - min + 1, (index) {
              final value = min + index;
              final count = distribution[value.toString()] ?? 0;
              final percentage =
                  responseCount > 0 ? (count / responseCount) * 100 : 0.0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _getRatingColor(value.toDouble(), min, max)
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$value',
                        style: mediumTextStyle(
                          color: _getRatingColor(value.toDouble(), min, max),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        backgroundColor: neutral200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getRatingColor(value.toDouble(), min, max),
                        ),
                        minHeight: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: Text(
                        '$count (${percentage.toStringAsFixed(0)}%)',
                        style: semiBoldTextStyle(size: 12),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );

      case QuestionType.multipleChoice:
      case QuestionType.checkboxes:
        final Map<String, int> counts =
            Map<String, int>.from(questionSummaryData['counts'] ?? {});
        final List<String> options = List<String>.from(
            questionSummaryData['options'] ?? question.options ?? []);

        if (options.isEmpty) {
          return Text('No answer options available.',
              style: regularTextStyle(color: neutral500));
        }

        // Sort options by count for better visualization
        options.sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));

        // Generate pie chart data
        final List<PieChartSectionData> pieData = [];

        // Define a list of colors for the pie sections
        final List<Color> pieColors = [
          kbpBlue500,
          kbpGreen500,
          warningY500,
          kbpBlue300,
          kbpGreen300,
          dangerR300,
          kbpBlue700,
          neutral500
        ];

        for (int i = 0; i < options.length; i++) {
          final option = options[i];
          final count = counts[option] ?? 0;
          final percentage =
              responseCount > 0 ? (count / responseCount) * 100 : 0.0;

          pieData.add(
            PieChartSectionData(
              value: count.toDouble(),
              title:
                  percentage >= 10 ? '${percentage.toStringAsFixed(0)}%' : '',
              color: pieColors[i % pieColors.length],
              radius: 90,
              titleStyle: boldTextStyle(color: Colors.white, size: 14),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pie chart visualization
            SizedBox(
              height: 240,
              child: PieChart(
                PieChartData(
                  sections: pieData,
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Legend and percentages
            ...options.asMap().entries.map((entry) {
              final index = entry.key;
              final option = entry.value;
              final count = counts[option] ?? 0;
              final percentage =
                  responseCount > 0 ? (count / responseCount) * 100 : 0.0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: pieColors[index % pieColors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(option, style: regularTextStyle()),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: pieColors[index % pieColors.length]
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$count (${percentage.toStringAsFixed(1)}%)',
                        style: semiBoldTextStyle(
                          color: pieColors[index % pieColors.length],
                          size: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        );

      case QuestionType.shortAnswer:
      case QuestionType.longAnswer:
        final List<String> answers =
            List<String>.from(questionSummaryData['answers'] ?? []);

        if (answers.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: neutral300,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.text_fields, color: neutral500, size: 20),
                const SizedBox(width: 8),
                Text('Tidak ada jawaban teks.',
                    style: regularTextStyle(color: neutral500)),
              ],
            ),
          );
        }

        // Show a sample of responses with expansion option
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Jawaban (${answers.length} total):',
                    style: mediumTextStyle(color: kbpBlue800)),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _showAllTextResponses = !_showAllTextResponses;
                    });
                  },
                  child: Text(
                    _showAllTextResponses
                        ? 'Tampilkan Lebih Sedikit'
                        : 'Tampilkan Semua',
                    style: mediumTextStyle(color: kbpBlue600, size: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...(_showAllTextResponses ? answers : answers.take(5))
                .map((ans) => Container(
                      margin: const EdgeInsets.only(bottom: 8.0),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kbpBlue50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: kbpBlue100),
                      ),
                      child:
                          Text(ans, style: regularTextStyle(color: neutral800)),
                    ))
                .toList(),
            if (!_showAllTextResponses && answers.length > 5)
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showAllTextResponses = true;
                    });
                  },
                  icon: Icon(Icons.expand_more, color: kbpBlue600),
                  label: Text(
                    'Lihat ${answers.length - 5} jawaban lainnya',
                    style: mediumTextStyle(color: kbpBlue600),
                  ),
                ),
              ),
          ],
        );

      default:
        return Text(
            'Tampilan ringkasan untuk tipe pertanyaan ini (${type.toString()}) belum diimplementasikan.',
            style: regularTextStyle(color: neutral500));
    }
  }

  // Helper method untuk mendapatkan warna berdasarkan rating
  Color _getRatingColor(double rating, int min, int max) {
    final midPoint = (max + min) / 2;

    if (rating < midPoint - (midPoint - min) * 0.3) {
      return dangerR400; // Rating rendah
    } else if (rating < midPoint + (max - midPoint) * 0.3) {
      return warningY500; // Rating menengah
    } else {
      return kbpGreen500; // Rating tinggi
    }
  }

  // Widget untuk menampilkan star rating
  Widget _buildStarRating(double average, int max) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(max, (index) {
        final value = index + 1;

        // Untuk partial star
        if (value > average && value - 1 < average) {
          final partial = average - (value - 1);
          return Stack(
            children: [
              Icon(Icons.star, color: neutral200, size: 28),
              ClipRect(
                clipper: _StarClipper(partial),
                child: Icon(Icons.star, color: kbpGreen500, size: 28),
              ),
            ],
          );
        }

        return Icon(
          Icons.star,
          color: value <= average ? kbpGreen500 : neutral200,
          size: 28,
        );
      }),
    );
  }
}

// Custom clipper untuk star rating
class _StarClipper extends CustomClipper<Rect> {
  final double percentage; // 0.0 to 1.0

  _StarClipper(this.percentage);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, 0, size.width * percentage, size.height);
  }

  @override
  bool shouldReclip(_StarClipper oldClipper) {
    return percentage != oldClipper.percentage;
  }
}
