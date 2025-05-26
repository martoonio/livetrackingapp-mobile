import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/survey.dart';
import 'package:livetrackingapp/presentation/auth/bloc/auth_bloc.dart';
import 'package:livetrackingapp/presentation/survey/survey_bloc.dart';
import 'package:intl/intl.dart';
import '../component/utils.dart'; // Pastikan utils.dart sudah ada dan benar
import 'package:uuid/uuid.dart'; // Untuk generate ID unik

class SurveyCreateScreen extends StatefulWidget {
  final Survey? survey; // Jika tidak null, berarti edit survey yang sudah ada

  const SurveyCreateScreen({Key? key, this.survey}) : super(key: key);

  @override
  State<SurveyCreateScreen> createState() => _SurveyCreateScreenState();
}

class _SurveyCreateScreenState extends State<SurveyCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late DateTime _expiryDate;

  List<SurveySection> _sections = [];
  int _currentSectionIndex = 0;

  final Uuid _uuid = const Uuid(); // Untuk generate ID

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.survey?.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.survey?.description ?? '');
    _expiryDate = widget.survey?.expiresAt ??
        DateTime.now().add(const Duration(days: 30));

    if (widget.survey != null && widget.survey!.sections.isNotEmpty) {
      _sections = List.from(widget.survey!.sections.map((section) =>
          section.copyWith(
              questions: List.from(section.questions
                  .map((question) => question.copyWith())
                  .toList()))));
    } else {
      _initializeDefaultSection();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    // Dispose controller pertanyaan dan pilihan jika ada
    for (var section in _sections) {
      for (var question in section.questions) {
        // Jika ada controller di dalam SurveyQuestion, dispose di sini
        // Contoh: question.textController.dispose();
      }
    }
    super.dispose();
  }

  void _initializeDefaultSection() {
    setState(() {
      _sections = [
        SurveySection(
          id: _uuid.v4(), // Generate ID unik untuk section
          title: 'Bagian 1',
          description: 'Deskripsi bagian 1',
          questions: [],
        )
      ];
      _currentSectionIndex = 0;
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)), // 5 tahun
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: kbpBlue900, // Warna utama date picker
              onPrimary: Colors.white, // Warna teks pada header utama
              onSurface: neutral900, // Warna teks pada tanggal
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: kbpBlue900, // Warna tombol OK dan Batal
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _expiryDate) {
      setState(() {
        _expiryDate = picked;
      });
    }
  }

  void _addNewSection() {
    setState(() {
      _sections.add(SurveySection(
        id: _uuid.v4(),
        title: 'Bagian ${_sections.length + 1}',
        description: 'Deskripsi bagian ${_sections.length + 1}',
        questions: [],
      ));
      _currentSectionIndex = _sections.length - 1; // Pindah ke section baru
    });
  }

  void _deleteSection(int index) {
    if (_sections.length <= 1) {
      showCustomSnackbar(
        context: context,
        title: 'Tidak Dapat Menghapus',
        subtitle: 'Survey harus memiliki minimal satu bagian.',
        type: SnackbarType.warning,
      );
      return;
    }
    setState(() {
      _sections.removeAt(index);
      if (_currentSectionIndex >= index && _currentSectionIndex > 0) {
        _currentSectionIndex--;
      } else if (_sections.isEmpty) {
        _initializeDefaultSection(); // Jika semua dihapus, buat section default
      } else if (_currentSectionIndex >= _sections.length) {
         _currentSectionIndex = _sections.length -1;
      }
    });
  }

  void _editSectionDialog(int index) {
    final section = _sections[index];
    final titleController = TextEditingController(text: section.title);
    final descController = TextEditingController(text: section.description);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Bagian', style: semiBoldTextStyle(size: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'Judul Bagian',
                labelStyle: regularTextStyle(color: neutral700),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Judul bagian tidak boleh kosong.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: descController,
              decoration: InputDecoration(
                labelText: 'Deskripsi Bagian (Opsional)',
                labelStyle: regularTextStyle(color: neutral700),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal', style: mediumTextStyle(color: neutral700)),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isNotEmpty) {
                 setState(() {
                  _sections[index] = _sections[index].copyWith(
                    title: titleController.text.trim(),
                    description: descController.text.trim(),
                  );
                });
                Navigator.pop(context);
              } else {
                 showCustomSnackbar(
                  context: context,
                  title: 'Judul Diperlukan',
                  subtitle: 'Silakan masukkan judul bagian.',
                  type: SnackbarType.warning,
                );
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: kbpBlue900, foregroundColor: Colors.white),
            child:
                Text('Simpan', style: semiBoldTextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((_) {
      titleController.dispose();
      descController.dispose();
    });
  }

  void _addOrEditQuestionDialog({SurveyQuestion? existingQuestion, int? questionIndex}) {
    final isEditing = existingQuestion != null;
    final questionController = TextEditingController(text: existingQuestion?.question ?? '');
    final questionDescController = TextEditingController(text: existingQuestion?.description ?? '');
    QuestionType selectedQuestionType = existingQuestion?.type ?? QuestionType.shortAnswer;
    int likertScale = existingQuestion?.likertScale ?? 5;
    Map<String, String> likertLabels = Map.from(existingQuestion?.likertLabels ?? {'1': 'Sangat Tidak Setuju', '2': 'Tidak Setuju', '3': 'Netral', '4': 'Setuju', '5': 'Sangat Setuju'});

    List<TextEditingController> choiceControllers = (existingQuestion?.choices?.map((choice) => TextEditingController(text: choice)).toList() ?? [TextEditingController(), TextEditingController()]);
    if (choiceControllers.length < 2 && (selectedQuestionType == QuestionType.singleChoice || selectedQuestionType == QuestionType.multipleChoice)) {
        choiceControllers.addAll(List.generate(2 - choiceControllers.length, (_) => TextEditingController()));
    }

    bool allowCustomAnswer = existingQuestion?.allowCustomAnswer ?? false;
    String customAnswerLabel = existingQuestion?.customAnswerLabel ?? "Lainnya";
    bool isRequired = existingQuestion?.isRequired ?? true;

    final dialogFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: Text(isEditing ? 'Edit Pertanyaan' : 'Tambah Pertanyaan', style: semiBoldTextStyle(size: 18)),
          content: Form(
            key: dialogFormKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: questionController,
                    decoration: InputDecoration(labelText: 'Pertanyaan', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Pertanyaan tidak boleh kosong.' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: questionDescController,
                    decoration: InputDecoration(labelText: 'Deskripsi (Opsional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<QuestionType>(
                    value: selectedQuestionType,
                    decoration: InputDecoration(labelText: 'Tipe Pertanyaan', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    items: QuestionType.values.map((type) => DropdownMenuItem(value: type, child: Text(_getQuestionTypeLabel(type)))).toList(),
                    onChanged: (value) => setDialogState(() => selectedQuestionType = value!),
                  ),
                  const SizedBox(height: 16),
                   CheckboxListTile(
                    title: Text("Wajib diisi", style: regularTextStyle()),
                    value: isRequired,
                    onChanged: (bool? value) {
                      setDialogState(() {
                        isRequired = value ?? true;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),

                  if (selectedQuestionType == QuestionType.likert) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: likertScale,
                      decoration: InputDecoration(labelText: 'Jumlah Skala Likert', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                      items: [3, 4, 5, 7, 10].map((scale) => DropdownMenuItem(value: scale, child: Text('$scale Poin'))).toList(),
                      onChanged: (value) => setDialogState(() {
                        likertScale = value!;
                        likertLabels.clear(); // Reset labels
                         for (int i = 1; i <= likertScale; i++) {
                            likertLabels['$i'] = existingQuestion?.likertLabels?['$i'] ?? "";
                         }
                         if (likertScale == 5 && existingQuestion?.likertLabels == null) { // Set default for 5 scale if new
                            likertLabels = {'1': 'Sangat Tidak Setuju', '2': 'Tidak Setuju', '3': 'Netral', '4': 'Setuju', '5': 'Sangat Setuju'};
                         }
                      }),
                    ),
                    const SizedBox(height: 16),
                    Text('Label Skala:', style: mediumTextStyle()),
                    ...List.generate(likertScale, (i) {
                      final key = (i + 1).toString();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextFormField(
                          initialValue: likertLabels[key] ?? '',
                          decoration: InputDecoration(labelText: 'Label untuk Poin $key', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                          onChanged: (value) => likertLabels[key] = value,
                           validator: (value) => (value == null || value.trim().isEmpty) ? 'Label tidak boleh kosong.' : null,
                        ),
                      );
                    }),
                  ],
                  if (selectedQuestionType == QuestionType.singleChoice || selectedQuestionType == QuestionType.multipleChoice) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Pilihan Jawaban', style: mediumTextStyle()),
                        IconButton(icon: const Icon(Icons.add_circle_outline, color: kbpBlue900), onPressed: () => setDialogState(() => choiceControllers.add(TextEditingController()))),
                      ],
                    ),
                    ...List.generate(choiceControllers.length, (i) => Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: choiceControllers[i],
                              decoration: InputDecoration(labelText: 'Pilihan ${i + 1}', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              validator: (value) => (value == null || value.trim().isEmpty) ? 'Pilihan tidak boleh kosong.' : null,
                            ),
                          ),
                          if (choiceControllers.length > 2) IconButton(icon: const Icon(Icons.remove_circle_outline, color: dangerR500), onPressed: () => setDialogState(() => choiceControllers.removeAt(i).dispose())),
                        ],
                      ),
                    )),
                    CheckboxListTile(
                      title: Text("Izinkan jawaban kustom ('Lainnya')", style: regularTextStyle()),
                      value: allowCustomAnswer,
                      onChanged: (bool? value) => setDialogState(() => allowCustomAnswer = value!),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (allowCustomAnswer) TextFormField(
                      initialValue: customAnswerLabel,
                      decoration: InputDecoration(labelText: "Label untuk jawaban kustom (e.g., 'Lainnya')", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                      onChanged: (value) => customAnswerLabel = value.trim().isNotEmpty ? value : "Lainnya",
                    ),
                  ]
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Batal', style: mediumTextStyle(color: neutral700))),
            ElevatedButton(
              onPressed: () {
                if (dialogFormKey.currentState!.validate()) {
                  final newQuestion = SurveyQuestion(
                    id: isEditing ? existingQuestion.id : _uuid.v4(),
                    question: questionController.text.trim(),
                    description: questionDescController.text.trim(),
                    type: selectedQuestionType,
                    likertScale: selectedQuestionType == QuestionType.likert ? likertScale : null,
                    likertLabels: selectedQuestionType == QuestionType.likert ? Map.from(likertLabels) : null, // Pastikan copy map
                    choices: (selectedQuestionType == QuestionType.singleChoice || selectedQuestionType == QuestionType.multipleChoice) ? choiceControllers.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList() : null,
                    allowCustomAnswer: (selectedQuestionType == QuestionType.singleChoice || selectedQuestionType == QuestionType.multipleChoice) ? allowCustomAnswer : false,
                    customAnswerLabel: (selectedQuestionType == QuestionType.singleChoice || selectedQuestionType == QuestionType.multipleChoice) ? customAnswerLabel : null,
                    isRequired: isRequired,
                  );
                  setState(() { // Ini adalah setState dari _SurveyCreateScreenState
                    final currentQuestions = List<SurveyQuestion>.from(_sections[_currentSectionIndex].questions);
                    if (isEditing && questionIndex != null) {
                      currentQuestions[questionIndex] = newQuestion;
                    } else {
                      currentQuestions.add(newQuestion);
                    }
                     _sections[_currentSectionIndex] = _sections[_currentSectionIndex].copyWith(questions: currentQuestions);
                  });
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: kbpBlue900, foregroundColor: Colors.white),
              child: Text(isEditing ? 'Simpan Perubahan' : 'Tambah Pertanyaan', style: semiBoldTextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    ).then((_) {
      // Dispose choice controllers
      for (var controller in choiceControllers) {
        controller.dispose();
      }
    });
  }


  void _deleteQuestion(int sectionIndex, int questionIndex) {
    setState(() {
      final updatedQuestions =
          List<SurveyQuestion>.from(_sections[sectionIndex].questions);
      updatedQuestions.removeAt(questionIndex);
      _sections[sectionIndex] =
          _sections[sectionIndex].copyWith(questions: updatedQuestions);
    });
  }

  void _moveQuestionToSectionDialog(int currentSectionIdx, int questionIdx) {
    int targetSectionIndex = currentSectionIdx; // Default ke section saat ini

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Pindahkan Pertanyaan ke Bagian Lain', style: semiBoldTextStyle(size: 18)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: targetSectionIndex,
                  items: List.generate(_sections.length, (index) {
                    return DropdownMenuItem(
                      value: index,
                      child: Text(_sections[index].title),
                    );
                  }),
                  onChanged: (value) {
                    setDialogState(() {
                      targetSectionIndex = value!;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Pilih Bagian Tujuan',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Batal')),
              ElevatedButton(
                onPressed: () {
                  if (targetSectionIndex != currentSectionIdx) {
                    setState(() {
                      final questionToMove = _sections[currentSectionIdx].questions[questionIdx];
                      // Hapus dari section lama
                      final oldSectionQuestions = List<SurveyQuestion>.from(_sections[currentSectionIdx].questions);
                      oldSectionQuestions.removeAt(questionIdx);
                      _sections[currentSectionIdx] = _sections[currentSectionIdx].copyWith(questions: oldSectionQuestions);

                      // Tambah ke section baru
                      final newSectionQuestions = List<SurveyQuestion>.from(_sections[targetSectionIndex].questions);
                      newSectionQuestions.add(questionToMove);
                       _sections[targetSectionIndex] = _sections[targetSectionIndex].copyWith(questions: newSectionQuestions);
                    });
                  }
                  Navigator.pop(context);
                },
                child: Text('Pindahkan'),
                style: ElevatedButton.styleFrom(backgroundColor: kbpBlue900, foregroundColor: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }


  void _saveSurvey() async {
    if (!_formKey.currentState!.validate()) {
      showCustomSnackbar(
        context: context,
        title: 'Form Tidak Valid',
        subtitle: 'Harap periksa kembali semua input yang diperlukan.',
        type: SnackbarType.warning,
      );
      return;
    }

    bool hasQuestionsInAnySection = _sections.any((section) => section.questions.isNotEmpty);
    if (!hasQuestionsInAnySection) {
       showCustomSnackbar(
        context: context,
        title: 'Pertanyaan Kosong',
        subtitle: 'Survey harus memiliki setidaknya satu pertanyaan di salah satu bagian.',
        type: SnackbarType.warning,
      );
      return;
    }
    // Validasi bahwa setiap section memiliki setidaknya satu pertanyaan jika ada section
    if (_sections.any((section) => section.title.trim().isNotEmpty && section.questions.isEmpty)) {
         bool confirmNoQuestions = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Konfirmasi Bagian Kosong'),
                content: Text('Beberapa bagian tidak memiliki pertanyaan. Apakah Anda ingin melanjutkan menyimpan survei?'),
                actions: <Widget>[
                  TextButton(
                    child: Text('Batal'),
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                  ),
                  TextButton(
                    child: Text('Lanjutkan'),
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                  ),
                ],
              );
            },
          ) ?? false;

        if (!confirmNoQuestions) {
            return;
        }
    }


    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      showCustomSnackbar(
        context: context,
        title: 'Autentikasi Gagal',
        subtitle: 'Harap login ulang untuk menyimpan survei.',
        type: SnackbarType.danger,
      );
      return;
    }

    final surveyToSave = Survey(
      id: widget.survey?.id ?? _uuid.v4(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      createdAt: widget.survey?.createdAt ?? DateTime.now(),
      expiresAt: _expiryDate,
      createdBy: widget.survey?.createdBy ?? authState.user.id,
      isActive: true, // Atau ambil dari UI jika ada pilihan
      sections: _sections.map((section) => section.copyWith(
        // Pastikan ID untuk section dan question juga unik
        id: section.id.isEmpty ? _uuid.v4() : section.id,
        questions: section.questions.map((q) => q.copyWith(
          id: q.id.isEmpty ? _uuid.v4() : q.id,
        )).toList()
      )).toList(),
    );

    if (widget.survey == null) {
      context.read<SurveyBloc>().add(CreateSurvey(surveyToSave));
    } else {
      context.read<SurveyBloc>().add(UpdateSurvey(surveyToSave));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SurveyBloc, SurveyState>(
      listener: (context, state) {
        if (state is SurveyLoading) {
          DialogUtils.showLoadingDialog(context, message: "Menyimpan survei...");
        } else if (state is SurveyCreated || state is SurveyUpdated) {
          Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
          showCustomSnackbar(
            context: context,
            title: widget.survey == null ? 'Survey Dibuat' : 'Survey Diperbarui',
            subtitle: 'Berhasil disimpan.',
            type: SnackbarType.success,
          );
          Navigator.pop(context, true); // Kembali & indikasi sukses
        } else if (state is SurveyError) {
          Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
          showCustomSnackbar(
            context: context,
            title: 'Gagal Menyimpan',
            subtitle: state.message,
            type: SnackbarType.danger,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.survey == null ? 'Buat Survey Baru' : 'Edit Survey', style: semiBoldTextStyle(color: Colors.white)),
          backgroundColor: kbpBlue900,
          foregroundColor: Colors.white,
          actions: [
            TextButton(
              onPressed: _saveSurvey,
              child: Text('Simpan', style: semiBoldTextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: Column(
          children: [
            // Section Tabs
            if (_sections.isNotEmpty)
              Container(
                height: 60,
                color: kbpBlue50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  itemCount: _sections.length,
                  itemBuilder: (context, index) {
                    final isActive = index == _currentSectionIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ChoiceChip(
                        label: Text(_sections[index].title.isEmpty ? "Bagian ${index + 1}" : _sections[index].title, style: mediumTextStyle(color: isActive ? Colors.white : kbpBlue900)),
                        selected: isActive,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _currentSectionIndex = index);
                          }
                        },
                        selectedColor: kbpBlue900,
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: isActive ? kbpBlue900 : kbpBlue300)
                        ),
                        elevation: isActive ? 2 : 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    );
                  },
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSurveyInfoCard(),
                      const SizedBox(height: 24),
                      if (_sections.isNotEmpty) _buildSectionCard(_sections[_currentSectionIndex], _currentSectionIndex),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                           if (_sections.length > 1)
                            TextButton.icon(
                                icon: Icon(Icons.delete_outline, color: dangerR500),
                                label: Text('Hapus Bagian Ini', style: mediumTextStyle(color: dangerR500)),
                                onPressed: () => _deleteSection(_currentSectionIndex),
                            ),
                          ElevatedButton.icon(
                            icon: Icon(Icons.add_box_outlined, color: Colors.white),
                            label: Text('Tambah Bagian Baru', style: mediumTextStyle(color:Colors.white)),
                            onPressed: _addNewSection,
                            style: ElevatedButton.styleFrom(backgroundColor: kbpBlue700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSurveyInfoCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Informasi Survey', style: semiBoldTextStyle(size: 18)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(labelText: 'Judul Survey', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Judul tidak boleh kosong.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(labelText: 'Deskripsi (Opsional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Text('Tanggal Kadaluarsa', style: mediumTextStyle()),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _selectDate(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(border: Border.all(color: neutral300), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat('dd MMMM yyyy', 'id_ID').format(_expiryDate), style: regularTextStyle()),
                    const Icon(Icons.calendar_today, color: kbpBlue900),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(SurveySection section, int sectionIndex) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text('Mengedit: ${section.title}', style: semiBoldTextStyle(size: 18), overflow: TextOverflow.ellipsis,)),
                IconButton(icon: Icon(Icons.edit_note, color: kbpBlue700), onPressed: () => _editSectionDialog(sectionIndex), tooltip: "Edit Judul/Deskripsi Bagian",),
              ],
            ),
            if (section.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(section.description, style: regularTextStyle(color: neutral700)),
            ],
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pertanyaan (${section.questions.length})', style: semiBoldTextStyle(size: 16)),
                ElevatedButton.icon(
                  icon: Icon(Icons.add_circle_outline, color: Colors.white),
                  label: Text('Tambah Pertanyaan', style: mediumTextStyle(color:Colors.white)),
                  onPressed: () => _addOrEditQuestionDialog(),
                  style: ElevatedButton.styleFrom(backgroundColor: kbpGreen500, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (section.questions.isEmpty)
              Center(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: Text('Belum ada pertanyaan di bagian ini.', style: regularTextStyle(color: neutral600))))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: section.questions.length,
                itemBuilder: (context, qIndex) {
                  final question = section.questions[qIndex];
                  return _buildQuestionItem(question, sectionIndex, qIndex);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionItem(SurveyQuestion question, int sectionIndex, int questionIndex) {
    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: neutral300)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${questionIndex + 1}.', style: mediumTextStyle(color: kbpBlue900)),
                const SizedBox(width: 8),
                Expanded(child: Text(question.question, style: semiBoldTextStyle())),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: neutral700),
                  onSelected: (value) {
                    if (value == 'edit') _addOrEditQuestionDialog(existingQuestion: question, questionIndex: questionIndex);
                    else if (value == 'delete') _deleteQuestion(sectionIndex, questionIndex);
                    else if (value == 'move') _moveQuestionToSectionDialog(sectionIndex, questionIndex);
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size:18, color: kbpBlue700), SizedBox(width:8), Text('Edit')])),
                     if (_sections.length > 1)
                        PopupMenuItem<String>(value: 'move', child: Row(children: [Icon(Icons.swap_horiz_outlined, size:18, color: kbpBlue700), SizedBox(width:8), Text('Pindahkan')])),
                    PopupMenuItem<String>(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size:18, color: dangerR500), SizedBox(width:8), Text('Hapus')])),
                  ],
                ),
              ],
            ),
            if (question.description.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 20.0, top: 4),
                child: Text(question.description, style: regularTextStyle(color: neutral600, size: paragrafLG)),
              )
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: _getQuestionTypeColor(question.type).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: Text(_getQuestionTypeLabel(question.type), style: mediumTextStyle(size: 12, color: _getQuestionTypeColor(question.type))),
                ),
                const SizedBox(width: 8),
                 if(question.isRequired)
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: dangerR50.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                        child: Text("Wajib", style: mediumTextStyle(size: 12, color: dangerR500)),
                    ),
              ],
            ),
             if (question.type == QuestionType.likert && question.likertLabels != null) ...[
                Padding(
                    padding: const EdgeInsets.only(top:8.0, left: 4.0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: question.likertLabels!.entries.map((e) => Text('${e.key}: ${e.value}', style: regularTextStyle(size: paragrafLG, color: neutral700))).toList(),
                    ),
                ),
            ],
            if ((question.type == QuestionType.singleChoice || question.type == QuestionType.multipleChoice) && question.choices != null) ...[
                 Padding(
                    padding: const EdgeInsets.only(top:8.0, left: 4.0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: question.choices!.map((c) => Text('• $c', style: regularTextStyle(size: paragrafLG, color: neutral700))).toList(),
                    ),
                ),
                if(question.allowCustomAnswer)
                     Padding(
                        padding: const EdgeInsets.only(top:4.0, left: 4.0),
                        child: Text('(+ ${question.customAnswerLabel ?? "Lainnya"})', style: regularTextStyle(size: paragrafLG, color: neutral700)),
                    ),
            ]
          ],
        ),
      ),
    );
  }

  String _getQuestionTypeLabel(QuestionType type) {
    switch (type) {
      case QuestionType.likert: return 'Skala Likert';
      case QuestionType.shortAnswer: return 'Jawaban Singkat';
      case QuestionType.longAnswer: return 'Jawaban Panjang';
      case QuestionType.singleChoice: return 'Pilihan Ganda';
      case QuestionType.multipleChoice: return 'Kotak Centang';
      default: return 'Unknown';
    }
  }

  Color _getQuestionTypeColor(QuestionType type) {
    switch (type) {
      case QuestionType.likert: return kbpBlue900;
      case QuestionType.shortAnswer: return kbpGreen600;
      case QuestionType.longAnswer: return warningY500;
      case QuestionType.singleChoice: return Colors.purple.shade700;
      case QuestionType.multipleChoice: return Colors.teal.shade700;
      default: return neutral700;
    }
  }
}


// Helper untuk dialog loading (bisa ditaruh di utils.dart)
class DialogUtils {
  static void showLoadingDialog(BuildContext context, {String message = "Loading...", GlobalKey? key}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          key: key, // Gunakan key di sini
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: kbpBlue900),
                const SizedBox(width: 20),
                Text(message, style: mediumTextStyle()),
              ],
            ),
          ),
        );
      },
    );
  }
}