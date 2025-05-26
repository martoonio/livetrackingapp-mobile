import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/survey.dart'; // Pastikan path ini benar
import 'package:livetrackingapp/presentation/survey/survey_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';

class SurveyDetailScreen extends StatefulWidget {
  final String surveyId; // Ubah dari Survey ke String surveyId
  final String userId;
  final String userName;

  const SurveyDetailScreen({
    Key? key,
    required this.surveyId, // Parameter surveyId
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<SurveyDetailScreen> createState() => _SurveyDetailScreenState();
}

class _SurveyDetailScreenState extends State<SurveyDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _answers = {}; // Menyimpan jawaban per questionId
  int _currentSectionIndex = 0;
  bool _canProceed = false;
  bool _isSubmitting = false;

  Survey? _currentSurvey; // Tambahkan variabel untuk menyimpan objek survey

  @override
  void initState() {
    super.initState();
    // Load survey by ID
    context.read<SurveyBloc>().add(LoadSurveyById(widget.surveyId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Detail Survei',
          style: semiBoldTextStyle(
            size: 20,
            color: Colors.white,
          ),
        ),
        backgroundColor: kbpBlue900,
        elevation: 0,
      ),
      body: BlocConsumer<SurveyBloc, SurveyState>(
        listener: (context, state) {
          if (state is SurveyResponseSubmitted) {
            // Tampilkan snackbar sukses dan kembali ke layar sebelumnya
            showCustomSnackbar(
              context: context,
              title: 'Berhasil',
              subtitle: 'Terima kasih telah mengisi survei ini',
              type: SnackbarType.success,
            );

            // Tunggu sebentar agar snackbar terlihat, lalu kembali
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                Navigator.pop(context);
              }
            });
          } else if (state is SurveyError) {
            // Reset status loading
            setState(() {
              _isSubmitting = false;
            });

            // Tampilkan pesan error
            showCustomSnackbar(
              context: context,
              title: 'Gagal',
              subtitle: state.message,
              type: SnackbarType.danger,
            );
          } else if (state is SurveyLoaded) {
            setState(() {
              _currentSurvey = state.survey;
              // Inisialisasi jawaban jika ada dari survey yang sudah diisi sebelumnya (jika ada fitur edit jawaban)
              // Untuk saat ini, kita asumsikan survey diisi dari awal.
            });
          }
        },
        builder: (context, state) {
          if (state is SurveyLoading || _currentSurvey == null) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is SurveyLoaded || _currentSurvey != null) {
            final survey = _currentSurvey!; // Gunakan _currentSurvey

            if (survey.sections.isEmpty) {
              return Center(
                child: Text(
                  'Survei ini tidak memiliki pertanyaan',
                  style: mediumTextStyle(),
                ),
              );
            }

            final currentSection = survey.sections[_currentSectionIndex];

            // Cek apakah semua pertanyaan wajib di section ini sudah dijawab
            _canProceed = _checkCanProceed(currentSection);

            return Column(
              children: [
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Info Survey
                          Text(
                            survey.title,
                            style: semiBoldTextStyle(size: 24),
                          ),
                          if (survey.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              survey.description,
                              style: regularTextStyle(color: neutral700),
                            ),
                          ],

                          const SizedBox(height: 24),

                          // Section Info
                          if (survey.sections.length > 1) ...[
                            LinearProgressIndicator(
                              value: (_currentSectionIndex + 1) /
                                  survey.sections.length,
                              backgroundColor: neutral200,
                              color: kbpBlue900,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Bagian ${_currentSectionIndex + 1} dari ${survey.sections.length}',
                              style: mediumTextStyle(color: neutral700),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Section Title & Description
                          Text(
                            currentSection.title,
                            style: semiBoldTextStyle(size: 20),
                          ),
                          if (currentSection.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              currentSection.description,
                              style: regularTextStyle(color: neutral700),
                            ),
                          ],

                          const SizedBox(height: 24),

                          // Questions in current section
                          ...List.generate(
                            currentSection.questions.length,
                            (index) => Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: _buildQuestion(
                                context,
                                currentSection.questions[index],
                                index,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Navigation buttons
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentSectionIndex > 0)
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _currentSectionIndex--;
                            });
                          },
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Sebelumnya'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: kbpBlue900,
                            side: BorderSide(color: kbpBlue900),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      if (_currentSectionIndex < survey.sections.length - 1)
                        ElevatedButton.icon(
                          onPressed: _canProceed
                              ? () {
                                  setState(() {
                                    _currentSectionIndex++;
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Selanjutnya'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kbpBlue900,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: neutral300,
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed:
                              _canProceed ? () => _submitSurvey(survey) : null,
                          icon: const Icon(Icons.check),
                          label: const Text('Selesai'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: successG500,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: neutral300,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          } else if (state is SurveyError) {
            return Center(
              child: Text(
                'Error: ${state.message}',
                style: regularTextStyle(color: dangerR500),
              ),
            );
          }

          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  bool _checkCanProceed(SurveySection section) {
    print('Checking if can proceed for section: ${section.title}');

    for (var question in section.questions) {
      if (question.isRequired) {
        final answerData = _answers[question.id];
        print(
            'Question ID: ${question.id}, Type: ${question.type}, Answer: $answerData');

        switch (question.type) {
          case QuestionType.likert:
            if (answerData == null ||
                answerData['value'] == null ||
                answerData['value'] == 0) {
              print('Failed check: Likert value missing or 0');
              return false;
            }
            break;

          case QuestionType.shortAnswer:
          case QuestionType.longAnswer:
            if (answerData == null ||
                answerData['answer'] == null ||
                answerData['answer'].toString().trim().isEmpty) {
              print('Failed check: Text answer empty');
              return false;
            }
            break;

          case QuestionType.singleChoice:
            if (answerData == null || answerData['answer'] == null) {
              print('Failed check: Single choice not selected');
              return false;
            }
            // Jika ada custom answer, cek apakah terisi
            if (answerData['answer'] == 'custom' &&
                (answerData['customAnswer'] == null ||
                    answerData['customAnswer'].toString().trim().isEmpty)) {
              print('Failed check: Custom answer required but empty');
              return false;
            }
            break;

          case QuestionType.multipleChoice:
            // PERBAIKAN: Kondisi yang salah untuk multipleChoice
            // Pertanyaan multipleChoice valid jika:
            // 1. Ada jawaban normal yang dipilih, ATAU
            // 2. Ada custom answer yang diisi

            bool hasSelectedChoices = answerData != null &&
                answerData['answers'] != null &&
                (answerData['answers'] as List).isNotEmpty;

            bool hasCustomAnswer = answerData != null &&
                answerData['customAnswer'] != null &&
                answerData['customAnswer'].toString().trim().isNotEmpty;

            if (!hasSelectedChoices && !hasCustomAnswer) {
              print('Failed check: No choices selected for multiple choice');
              return false;
            }

            // Jika custom answer diaktifkan tapi kosong
            if (answerData != null &&
                answerData['customAnswer'] != null &&
                answerData['customAnswer'].toString().trim().isEmpty) {
              print('Failed check: Custom answer enabled but empty');
              return false;
            }
            break;
        }
      }
    }

    print('All checks passed for section: ${section.title}');
    return true;
  }

  Widget _buildQuestion(
      BuildContext context, SurveyQuestion question, int index) {
    // Inisialisasi jawaban dari _answers jika sudah ada
    // Ini penting agar jawaban tidak hilang saat widget direbuild
    dynamic initialAnswerValue;
    String? initialCustomAnswer;
    List<String> initialSelectedChoices = [];

    if (_answers.containsKey(question.id)) {
      final existingAnswer = _answers[question.id];
      if (question.type == QuestionType.likert) {
        initialAnswerValue = existingAnswer['value'];
      } else if (question.type == QuestionType.shortAnswer ||
          question.type == QuestionType.longAnswer) {
        initialAnswerValue = existingAnswer['answer'];
      } else if (question.type == QuestionType.singleChoice) {
        initialAnswerValue = existingAnswer['answer'];
        initialCustomAnswer = existingAnswer['customAnswer'];
      } else if (question.type == QuestionType.multipleChoice) {
        initialSelectedChoices =
            List<String>.from(existingAnswer['answers'] ?? []);
        initialCustomAnswer = existingAnswer['customAnswer'];
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: kbpBlue900,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: semiBoldTextStyle(size: 14, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question.question,
                      style: semiBoldTextStyle(size: 16, color: neutral900),
                    ),
                    if (question.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        question.description,
                        style: regularTextStyle(size: 14, color: neutral700),
                      ),
                    ],
                    if (question.isRequired) ...[
                      const SizedBox(height: 4),
                      Text(
                        '* Wajib diisi',
                        style: regularTextStyle(size: 12, color: dangerR500),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Berbagai tipe pertanyaan
          if (question.type == QuestionType.likert) ...[
            _buildLikertScale(question, initialAnswerValue)
          ] else if (question.type == QuestionType.shortAnswer) ...[
            _buildShortAnswer(question, initialAnswerValue)
          ] else if (question.type == QuestionType.longAnswer) ...[
            _buildLongAnswer(question, initialAnswerValue)
          ]
          // Tambahkan tipe pertanyaan baru
          else if (question.type == QuestionType.singleChoice) ...[
            _buildSingleChoice(
                question, initialAnswerValue, initialCustomAnswer)
          ] else if (question.type == QuestionType.multipleChoice) ...[
            _buildMultipleChoice(
                question, initialSelectedChoices, initialCustomAnswer)
          ],
        ],
      ),
    );
  }

  Widget _buildLikertScale(SurveyQuestion question, dynamic initialValue) {
    // Initialize value if not set
    _answers[question.id] ??= {
      'type': 'likert',
      'value': 0
    }; // Default 0 untuk belum dipilih

    // Get likert labels or use defaults
    final likertLabels = question.likertLabels ??
        {
          '1': 'Sangat Tidak Setuju',
          '2': 'Tidak Setuju',
          '3': 'Netral',
          '4': 'Setuju',
          '5': 'Sangat Setuju',
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              likertLabels['1'] ?? 'Sangat Tidak Setuju',
              style: regularTextStyle(size: 12, color: neutral700),
            ),
            Text(
              likertLabels['${question.likertScale ?? 5}'] ?? 'Sangat Setuju',
              style: regularTextStyle(size: 12, color: neutral700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(question.likertScale ?? 5, (index) {
            final value = index + 1;
            return Column(
              children: [
                Radio(
                  value: value,
                  groupValue: _answers[question.id]?['value'],
                  activeColor: kbpBlue900,
                  onChanged: (newValue) {
                    setState(() {
                      _answers[question.id] = {
                        'type': 'likert',
                        'value': newValue
                      };
                    });
                  },
                ),
                Text(
                  '$value',
                  style: mediumTextStyle(size: 14, color: neutral800),
                ),
              ],
            );
          }),
        ),
        if (question.isRequired &&
            (_answers[question.id]?['value'] == null ||
                _answers[question.id]?['value'] == 0)) ...[
          const SizedBox(height: 4),
          Text(
            'Silakan pilih salah satu opsi',
            style: regularTextStyle(size: 12, color: dangerR500),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Keterangan: ${likertLabels[_answers[question.id]?['value'].toString()] ?? "Belum dipilih"}',
          style: regularTextStyle(
              size: 12,
              color: (_answers[question.id]?['value'] == null ||
                      _answers[question.id]?['value'] == 0)
                  ? neutral600
                  : kbpBlue900),
        ),
      ],
    );
  }

  Widget _buildShortAnswer(SurveyQuestion question, dynamic initialValue) {
    // Inisialisasi jawaban jika belum ada
    _answers[question.id] ??= {'type': 'shortAnswer', 'answer': ''};

    return TextFormField(
      initialValue: initialValue as String? ?? '',
      decoration: InputDecoration(
        hintText: 'Ketik jawaban singkat Anda di sini',
        hintStyle: regularTextStyle(size: 14, color: neutral500),
        filled: true,
        fillColor: neutral300,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: neutral300, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: neutral300, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: kbpBlue700, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: dangerR500, width: 1),
        ),
      ),
      style: regularTextStyle(size: 16, color: neutral900),
      maxLines: 1,
      validator: question.isRequired
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Jawaban tidak boleh kosong';
              }
              return null;
            }
          : null,
      onChanged: (value) {
        _answers[question.id] = {'type': 'shortAnswer', 'answer': value};
      },
    );
  }

  Widget _buildLongAnswer(SurveyQuestion question, dynamic initialValue) {
    // Inisialisasi jawaban jika belum ada
    _answers[question.id] ??= {'type': 'longAnswer', 'answer': ''};

    return TextFormField(
      initialValue: initialValue as String? ?? '',
      decoration: InputDecoration(
        hintText: 'Ketik jawaban lengkap Anda di sini',
        hintStyle: regularTextStyle(size: 14, color: neutral500),
        filled: true,
        fillColor: neutral300,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: neutral300, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: neutral300, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: kbpBlue700, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: dangerR500, width: 1),
        ),
      ),
      style: regularTextStyle(size: 16, color: neutral900),
      maxLines: 5,
      minLines: 3,
      validator: question.isRequired
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Jawaban tidak boleh kosong';
              }
              return null;
            }
          : null,
      onChanged: (value) {
        _answers[question.id] = {'type': 'longAnswer', 'answer': value};
      },
    );
  }

  Widget _buildSingleChoice(SurveyQuestion question, dynamic initialAnswer,
      String? initialCustomAnswer) {
    // Inisialisasi jawaban jika belum ada
    _answers[question.id] ??= {
      'type': 'singleChoice',
      'answer': null,
      'customAnswer': null
    };

    return StatefulBuilder(
      builder: (context, setState) {
        String? currentAnswer = _answers[question.id]?['answer'];
        String? currentCustomAnswer = _answers[question.id]?['customAnswer'];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pilihan radio button
            ...question.choices!
                .map((choice) => RadioListTile<String>(
                      title: Text(choice, style: regularTextStyle()),
                      value: choice,
                      groupValue: currentAnswer,
                      onChanged: (value) {
                        setState(() {
                          currentAnswer = value;
                          currentCustomAnswer =
                              null; // Reset custom answer jika memilih opsi reguler
                          _answers[question.id] = {
                            'type': 'singleChoice',
                            'answer': currentAnswer,
                            'customAnswer': currentCustomAnswer,
                          };
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ))
                .toList(),

            // Opsi "Lainnya" jika diizinkan
            if (question.allowCustomAnswer) ...[
              RadioListTile<String>(
                title: Text(question.customAnswerLabel!,
                    style: regularTextStyle()),
                value: 'custom',
                groupValue: currentAnswer,
                onChanged: (value) {
                  setState(() {
                    currentAnswer = value;
                    // Jika memilih custom, pastikan customAnswer tidak null
                    if (currentAnswer == 'custom' &&
                        currentCustomAnswer == null) {
                      currentCustomAnswer = '';
                    }
                    _answers[question.id] = {
                      'type': 'singleChoice',
                      'answer': currentAnswer,
                      'customAnswer': currentCustomAnswer,
                    };
                  });
                },
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),

              // Field untuk jawaban kustom, hanya muncul jika "Lainnya" dipilih
              if (currentAnswer == 'custom')
                Padding(
                  padding: const EdgeInsets.only(left: 32, right: 16),
                  child: TextFormField(
                    initialValue: currentCustomAnswer,
                    decoration: InputDecoration(
                      hintText: 'Ketik jawaban Anda di sini',
                      hintStyle: regularTextStyle(color: neutral500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        currentCustomAnswer = value;
                        _answers[question.id] = {
                          'type': 'singleChoice',
                          'answer': currentAnswer,
                          'customAnswer': currentCustomAnswer,
                        };
                      });
                    },
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMultipleChoice(SurveyQuestion question,
      List<String> initialSelectedChoices, String? initialCustomAnswer) {
    // Inisialisasi jawaban jika belum ada
    _answers[question.id] ??= {
      'type': 'multipleChoice',
      'answers': [],
      'customAnswer': null
    };

    return StatefulBuilder(
      builder: (context, setState) {
        List<String> currentSelectedChoices =
            List<String>.from(_answers[question.id]?['answers'] ?? []);
        String? currentCustomAnswer = _answers[question.id]?['customAnswer'];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pilihan checkbox
            ...question.choices!
                .map((choice) => CheckboxListTile(
                      title: Text(choice, style: regularTextStyle()),
                      value: currentSelectedChoices.contains(choice),
                      onChanged: (value) {
                        setState(() {
                          if (value!) {
                            currentSelectedChoices.add(choice);
                          } else {
                            currentSelectedChoices.remove(choice);
                          }
                          _answers[question.id] = {
                            'type': 'multipleChoice',
                            'answers': currentSelectedChoices,
                            'customAnswer': currentCustomAnswer,
                          };
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    ))
                .toList(),

            // Opsi "Lainnya" jika diizinkan
            if (question.allowCustomAnswer) ...[
              CheckboxListTile(
                title: Text(question.customAnswerLabel!,
                    style: regularTextStyle()),
                value: currentCustomAnswer != null,
                onChanged: (value) {
                  setState(() {
                    if (value!) {
                      currentCustomAnswer =
                          currentCustomAnswer ?? ''; // Inisialisasi jika null
                    } else {
                      currentCustomAnswer = null;
                    }
                    _answers[question.id] = {
                      'type': 'multipleChoice',
                      'answers': currentSelectedChoices,
                      'customAnswer': currentCustomAnswer,
                    };
                  });
                },
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),

              // Field untuk jawaban kustom, hanya muncul jika "Lainnya" dipilih
              if (currentCustomAnswer != null)
                Padding(
                  padding: const EdgeInsets.only(left: 32, right: 16),
                  child: TextFormField(
                    initialValue: currentCustomAnswer,
                    decoration: InputDecoration(
                      hintText: 'Ketik jawaban Anda di sini',
                      hintStyle: regularTextStyle(color: neutral500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        currentCustomAnswer = value;
                        _answers[question.id] = {
                          'type': 'multipleChoice',
                          'answers': currentSelectedChoices,
                          'customAnswer': currentCustomAnswer,
                        };
                      });
                    },
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  void _submitSurvey(Survey survey) async {
    print('======= SUBMIT SURVEY =======');
    print('Answers: $_answers');

    // Validasi form secara keseluruhan
    final formValid = _formKey.currentState!.validate();
    print('Form validation: $formValid');

    if (!formValid) {
      showCustomSnackbar(
        context: context,
        title: 'Form Belum Lengkap',
        subtitle: 'Silakan lengkapi semua pertanyaan wajib',
        type: SnackbarType.danger,
      );
      return;
    }

    // Cek apakah semua section yang required sudah diisi
    bool allSectionsValid = true;
    for (var i = 0; i < survey.sections.length; i++) {
      final section = survey.sections[i];
      final sectionValid = _checkCanProceed(section);
      print('Section ${i + 1} validation: $sectionValid');

      if (!sectionValid) {
        allSectionsValid = false;
        setState(() {
          _currentSectionIndex = i; // Pindah ke section yang belum lengkap
        });

        showCustomSnackbar(
          context: context,
          title: 'Pertanyaan Belum Lengkap',
          subtitle: 'Silakan lengkapi pertanyaan wajib di bagian ${i + 1}',
          type: SnackbarType.warning,
        );
        return;
      }
    }

    print('All sections valid: $allSectionsValid');

    // Set submitting state
    setState(() {
      _isSubmitting = true;
    });

    try {
      // Create survey response
      final responseId = DateTime.now().millisecondsSinceEpoch.toString();
      final response = SurveyResponse(
        id: responseId,
        surveyId: survey.id,
        userId: widget.userId,
        userName: widget.userName,
        submittedAt: DateTime.now(),
        answers: _answers,
      );

      print('Submitting response with ID: $responseId');

      // Submit response
      context.read<SurveyBloc>().add(SubmitSurveyResponse(response));
    } catch (e) {
      print('Error submitting survey: $e');
      setState(() {
        _isSubmitting = false;
      });

      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Gagal mengirim survei: ${e.toString()}',
        type: SnackbarType.danger,
      );
    }
  }
}
