import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/survey/question.dart';
import 'package:livetrackingapp/domain/entities/survey/section.dart';
import 'package:livetrackingapp/domain/entities/survey/survey.dart';
import 'package:livetrackingapp/domain/entities/user.dart' as app_user;
import 'package:livetrackingapp/presentation/auth/bloc/auth_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/survey/bloc/survey_bloc.dart';
import 'package:uuid/uuid.dart';

class CreateEditSurveyScreen extends StatefulWidget {
  final Survey? surveyToEdit;

  const CreateEditSurveyScreen({super.key, this.surveyToEdit});

  bool get isEditing => surveyToEdit != null;

  @override
  State<CreateEditSurveyScreen> createState() => _CreateEditSurveyScreenState();
}

class _CreateEditSurveyScreenState extends State<CreateEditSurveyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isActive = true;
  List<String> _targetAudience = ['all'];
  List<_SectionUIData> _sectionsData = [];
  bool _isSaving = false;

  final List<String> _audienceOptions = ['all', 'patrol', 'commandCenter'];

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  void _initializeForm() {
    if (widget.isEditing && widget.surveyToEdit != null) {
      final survey = widget.surveyToEdit!;
      _titleController.text = survey.title;
      _descriptionController.text = survey.description ?? '';
      _isActive = survey.isActive;
      _targetAudience = List<String>.from(survey.targetAudience ?? ['all']);

      _sectionsData =
          survey.sections.map((s) => _SectionUIData.fromSection(s)).toList();

      // Ensure each section has at least one question
      for (var sectionData in _sectionsData) {
        if (sectionData.questions.isEmpty) {
          sectionData.questions.add(_QuestionUIData.createDefault());
        }
      }
    } else {
      // Add initial section with one question
      _addSection(addDefaultQuestion: true);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    for (var section in _sectionsData) {
      section.dispose();
    }
    super.dispose();
  }

  void _addSection({bool addDefaultQuestion = false}) {
    setState(() {
      final newSection =
          _SectionUIData.createDefault(order: _sectionsData.length);
      if (addDefaultQuestion) {
        newSection.questions.add(_QuestionUIData.createDefault());
      }
      _sectionsData.add(newSection);
    });
  }

  void _removeSection(int index) {
    if (_sectionsData.length <= 1) {
      showCustomSnackbar(
        context: context,
        title: "Info",
        subtitle: "Survey must have at least one section",
        type: SnackbarType.warning,
      );
      return;
    }

    setState(() {
      final removedSection = _sectionsData.removeAt(index);
      removedSection.dispose();

      // Update order for remaining sections
      for (int i = 0; i < _sectionsData.length; i++) {
        _sectionsData[i].order = i;
      }
    });
  }

  void _addQuestion(int sectionIndex) {
    if (sectionIndex < 0 || sectionIndex >= _sectionsData.length) return;

    setState(() {
      final section = _sectionsData[sectionIndex];
      section.questions.add(_QuestionUIData.createDefault(
        order: section.questions.length,
      ));
    });
  }

  void _removeQuestion(int sectionIndex, int questionIndex) {
    if (sectionIndex < 0 ||
        sectionIndex >= _sectionsData.length ||
        questionIndex < 0 ||
        questionIndex >= _sectionsData[sectionIndex].questions.length) {
      return;
    }

    final section = _sectionsData[sectionIndex];
    if (section.questions.length <= 1) {
      showCustomSnackbar(
        context: context,
        title: "Info",
        subtitle: "Section must have at least one question",
        type: SnackbarType.warning,
      );
      return;
    }

    setState(() {
      final removedQuestion = section.questions.removeAt(questionIndex);
      removedQuestion.dispose();

      // Update order for remaining questions
      for (int i = 0; i < section.questions.length; i++) {
        section.questions[i].order = i;
      }
    });
  }

  bool _validateForm() {
    // Validate survey title
    if (_titleController.text.trim().isEmpty) {
      showCustomSnackbar(
        context: context,
        title: "Validation Error",
        subtitle: "Survey title cannot be empty",
        type: SnackbarType.warning,
      );
      return false;
    }

    // Validate sections
    if (_sectionsData.isEmpty) {
      showCustomSnackbar(
        context: context,
        title: "Validation Error",
        subtitle: "Survey must have at least one section",
        type: SnackbarType.warning,
      );
      return false;
    }

    // Validate each section and question
    for (int i = 0; i < _sectionsData.length; i++) {
      final section = _sectionsData[i];

      // Validate section title
      if (section.titleController.text.trim().isEmpty) {
        showCustomSnackbar(
          context: context,
          title: "Validation Error",
          subtitle: "Section ${i + 1} title cannot be empty",
          type: SnackbarType.warning,
        );
        return false;
      }

      // Validate questions in section
      if (section.questions.isEmpty) {
        showCustomSnackbar(
          context: context,
          title: "Validation Error",
          subtitle: "Section ${i + 1} must have at least one question",
          type: SnackbarType.warning,
        );
        return false;
      }

      for (int j = 0; j < section.questions.length; j++) {
        final question = section.questions[j];

        // Validate question text
        if (question.textController.text.trim().isEmpty) {
          showCustomSnackbar(
            context: context,
            title: "Validation Error",
            subtitle: "Question ${j + 1} in section ${i + 1} cannot be empty",
            type: SnackbarType.warning,
          );
          return false;
        }

        // Validate question options if needed
        if (question.type == QuestionType.multipleChoice ||
            question.type == QuestionType.checkboxes) {
          final validOptions = question.options
              .where((opt) => opt.controller.text.trim().isNotEmpty)
              .length;

          if (validOptions < 2) {
            showCustomSnackbar(
              context: context,
              title: "Validation Error",
              subtitle:
                  "Question ${j + 1} in section ${i + 1} needs at least 2 valid options",
              type: SnackbarType.warning,
            );
            return false;
          }
        }

        // Validate likert scale labels
        if (question.type == QuestionType.likertScale) {
          if (question.likertMinLabelController.text.trim().isEmpty ||
              question.likertMaxLabelController.text.trim().isEmpty) {
            showCustomSnackbar(
              context: context,
              title: "Validation Error",
              subtitle:
                  "Question ${j + 1} in section ${i + 1} requires both Likert scale labels",
              type: SnackbarType.warning,
            );
            return false;
          }
        }
      }
    }

    return true;
  }

  void _saveSurvey() {
    if (!_validateForm()) return;

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      showCustomSnackbar(
        context: context,
        title: "Error",
        subtitle: "User not authenticated",
        type: SnackbarType.danger,
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final surveyId =
          widget.isEditing ? widget.surveyToEdit!.surveyId : const Uuid().v4();
      final now = DateTime.now();

      // Convert UI data to domain models
      final sections = _sectionsData.map((sectionData) {
        final questions = sectionData.questions.map((questionData) {
          List<String>? options;
          if (questionData.type == QuestionType.multipleChoice ||
              questionData.type == QuestionType.checkboxes) {
            options = questionData.options
                .map((opt) => opt.controller.text.trim())
                .where((text) => text.isNotEmpty)
                .toList();
          }

          return Question(
            questionId: questionData.questionId,
            text: questionData.textController.text.trim(),
            type: questionData.type,
            isRequired: questionData.isRequired,
            options: options,
            likertScaleMin: questionData.type == QuestionType.likertScale
                ? questionData.likertScaleMin
                : null,
            likertScaleMax: questionData.type == QuestionType.likertScale
                ? questionData.likertScaleMax
                : null,
            likertMinLabel: questionData.type == QuestionType.likertScale
                ? questionData.likertMinLabelController.text.trim()
                : null,
            likertMaxLabel: questionData.type == QuestionType.likertScale
                ? questionData.likertMaxLabelController.text.trim()
                : null,
            order: questionData.order,
          );
        }).toList();

        return Section(
          sectionId: sectionData.sectionId,
          title: sectionData.titleController.text.trim(),
          description: sectionData.descriptionController.text.trim(),
          order: sectionData.order,
          questions: questions,
        );
      }).toList();

      final sectionsAndQuestionsData = <String, List<Map<String, dynamic>>>{};
      for (var section in sections) {
        // Create a list to hold questions for each section
        final questionsList = <Map<String, dynamic>>[];
        
        // Add section data
        questionsList.add({
          'title': section.title,
          'description': section.description ?? '',
          'order': section.order,
          'isSectionData': true,  // Flag to identify section data
        });
        
        // Add questions data
        for (var q in section.questions) {
          final questionMap = q.toMap();
          questionMap['questionId'] = q.questionId;
          questionMap['order'] = q.order;
          questionsList.add(questionMap);
        }
        
        // Store the list in the map
        sectionsAndQuestionsData[section.sectionId] = questionsList;
      }

      // Create survey object
      final survey = Survey(
        surveyId: surveyId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        createdBy: authState.user.id,
        createdAt: widget.isEditing ? widget.surveyToEdit!.createdAt : now,
        updatedAt: now,
        sections: sections,
        isActive: _isActive,
        targetAudience: _targetAudience,
      );

      // Dispatch save event
      context.read<SurveyBloc>().add(SaveSurvey(
            survey: survey,
            sectionsAndQuestionsData: sectionsAndQuestionsData,
            isUpdate: widget.isEditing,
          ));
    } catch (e) {
      setState(() => _isSaving = false);
      showCustomSnackbar(
        context: context,
        title: "Error",
        subtitle: "Failed to save survey: ${e.toString()}",
        type: SnackbarType.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Survey' : 'Create New Survey'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveSurvey,
            tooltip: 'Save Survey',
          ),
        ],
      ),
      body: BlocListener<SurveyBloc, SurveyState>(
        listener: (context, state) {
          if (state is SurveyLoading) {
            setState(() => _isSaving = true);
          } else {
            setState(() => _isSaving = false);
          }

          if (state is SurveyOperationSuccess) {
            showCustomSnackbar(
              context: context,
              title: 'Success',
              subtitle: state.message,
              type: SnackbarType.success,
            );
            Navigator.of(context).pop();
          } else if (state is SurveyError) {
            showCustomSnackbar(
              context: context,
              title: 'Error',
              subtitle: state.message,
              type: SnackbarType.danger,
            );
          }
        },
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSurveyInfoCard(),
                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Survey Sections & Questions',
                        style: boldTextStyle(size: 18, color: kbpBlue800),
                      ),
                    ),
                    if (_sectionsData.isNotEmpty)
                      Text(
                        'Drag to reorder',
                        style: regularTextStyle(size: 12, color: neutral600),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Sections list with reordering
                if (_sectionsData.isEmpty) _buildEmptySectionsPlaceholder(),

                // Ganti ListView dengan ReorderableListView untuk section
                if (_sectionsData.isNotEmpty)
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: _onReorderSection,
                    itemCount: _sectionsData.length,
                    itemBuilder: (context, index) {
                      // Gunakan Key unik untuk setiap section
                      return KeyedSubtree(
                        key: ValueKey(
                            'section_${_sectionsData[index].sectionId}'),
                        child: _buildSectionCard(index),
                      );
                    },
                  ),

                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add New Section'),
                  onPressed: _addSection,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kbpBlue700,
                    side: const BorderSide(color: kbpBlue300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 80), // Space for FAB
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _saveSurvey,
        label: Text(_isSaving
            ? "Saving..."
            : (widget.isEditing ? 'Save Changes' : 'Create Survey')),
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ))
            : const Icon(Icons.save),
        backgroundColor: _isSaving ? kbpBlue300 : kbpBlue900,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
            Text(
              'General Information',
              style: semiBoldTextStyle(size: 16, color: kbpBlue700),
            ),
            const Divider(height: 20),

            // Survey Title
            TextFormField(
              controller: _titleController,
              decoration: _inputDecoration('Survey Title', Icons.title),
              validator: (value) =>
                  value?.trim().isEmpty ?? true ? 'Required field' : null,
            ),
            const SizedBox(height: 16),

            // Survey Description
            TextFormField(
              controller: _descriptionController,
              decoration: _inputDecoration(
                  'Survey Description (Optional)', Icons.description),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Target Audience
            Text(
              'Target Audience',
              style: mediumTextStyle(color: kbpBlue700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: _audienceOptions.map((audience) {
                final isSelected = _targetAudience.contains(audience);
                return ChoiceChip(
                  label: Text(audience),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        if (audience == 'all') {
                          _targetAudience = ['all'];
                        } else {
                          _targetAudience.remove('all');
                          _targetAudience.add(audience);
                        }
                      } else {
                        _targetAudience.remove(audience);
                        if (_targetAudience.isEmpty) {
                          _targetAudience.add('all');
                        }
                      }
                    });
                  },
                  selectedColor: kbpBlue700,
                  backgroundColor: kbpBlue50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side:
                        BorderSide(color: isSelected ? kbpBlue700 : kbpBlue300),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Survey Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Survey Status:',
                  style: mediumTextStyle(color: kbpBlue700),
                ),
                Switch(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  activeColor: kbpGreen500,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySectionsPlaceholder() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      child: Center(
        child: Text(
          "Click '+' to add your first section",
          style: regularTextStyle(color: neutral600),
        ),
      ),
    );
  }

  Widget _buildSectionCard(int sectionIndex) {
    if (sectionIndex < 0 || sectionIndex >= _sectionsData.length) {
      return const SizedBox();
    }

    final section = _sectionsData[sectionIndex];
    final questions = section.questions;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: kbpBlue200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header with drag handle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // Drag handle icon
                      Icon(
                        Icons.drag_handle,
                        size: 20,
                        color: neutral500,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Section ${sectionIndex + 1}',
                        style: semiBoldTextStyle(size: 16, color: kbpBlue700),
                      ),
                    ],
                  ),
                ),
                // Section reorder and delete buttons
                Row(
                  children: [
                    // Move Up button
                    if (sectionIndex > 0)
                      IconButton(
                        icon: Icon(Icons.arrow_upward,
                            size: 20, color: kbpBlue600),
                        onPressed: () => _moveSectionUp(sectionIndex),
                        tooltip: 'Move Up',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    const SizedBox(width: 8),
                    // Move Down button
                    if (sectionIndex < _sectionsData.length - 1)
                      IconButton(
                        icon: Icon(Icons.arrow_downward,
                            size: 20, color: kbpBlue600),
                        onPressed: () => _moveSectionDown(sectionIndex),
                        tooltip: 'Move Down',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    const SizedBox(width: 12),
                    // Delete button
                    if (_sectionsData.length > 1)
                      IconButton(
                        icon: Icon(Icons.delete, size: 20, color: dangerR400),
                        onPressed: () => _removeSection(sectionIndex),
                        tooltip: 'Remove Section',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),

            // Section Title
            TextFormField(
              controller: section.titleController,
              decoration:
                  _inputDecoration('Section Title', Icons.view_headline),
              validator: (value) =>
                  value?.trim().isEmpty ?? true ? 'Required field' : null,
            ),
            const SizedBox(height: 16),

            // Section Description
            TextFormField(
              controller: section.descriptionController,
              decoration: _inputDecoration(
                  'Section Description (Optional)', Icons.short_text),
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            // Questions Header with reorder indicator
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Questions for Section ${sectionIndex + 1}',
                    style: mediumTextStyle(color: kbpBlue800),
                  ),
                ),
                if (questions.isNotEmpty)
                  Text(
                    'Drag to reorder',
                    style: regularTextStyle(size: 12, color: neutral600),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Questions List with reordering
            if (questions.isEmpty) _buildEmptyQuestionsPlaceholder(),

            if (questions.isNotEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: (oldIndex, newIndex) =>
                    _onReorderQuestion(sectionIndex, oldIndex, newIndex),
                itemCount: questions.length,
                itemBuilder: (context, questionIndex) {
                  return KeyedSubtree(
                    key: ValueKey(
                        'question_${questions[questionIndex].questionId}'),
                    child: _buildQuestionCard(sectionIndex, questionIndex),
                  );
                },
              ),

            // Add Question Button
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Question'),
              onPressed: () => _addQuestion(sectionIndex),
              style: OutlinedButton.styleFrom(
                foregroundColor: kbpBlue700,
                side: const BorderSide(color: kbpBlue300),
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyQuestionsPlaceholder() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15.0),
      child: Center(
        child: Text(
          "Click '+' to add your first question",
          style: regularTextStyle(color: neutral600),
        ),
      ),
    );
  }

  Widget _buildQuestionCard(int sectionIndex, int questionIndex) {
    final question = _sectionsData[sectionIndex].questions[questionIndex];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: neutral300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question Header with drag handle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // Drag handle icon
                      Icon(
                        Icons.drag_handle,
                        size: 18,
                        color: neutral400,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Question ${questionIndex + 1}',
                        style: mediumTextStyle(size: 14, color: kbpBlue700),
                      ),
                    ],
                  ),
                ),
                // Question reorder and delete buttons
                Row(
                  children: [
                    // Move Up button
                    if (questionIndex > 0)
                      IconButton(
                        icon: Icon(Icons.arrow_upward,
                            size: 18, color: kbpBlue600),
                        onPressed: () =>
                            _moveQuestionUp(sectionIndex, questionIndex),
                        tooltip: 'Move Up',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    const SizedBox(width: 4),
                    // Move Down button
                    if (questionIndex <
                        _sectionsData[sectionIndex].questions.length - 1)
                      IconButton(
                        icon: Icon(Icons.arrow_downward,
                            size: 18, color: kbpBlue600),
                        onPressed: () =>
                            _moveQuestionDown(sectionIndex, questionIndex),
                        tooltip: 'Move Down',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    const SizedBox(width: 8),
                    // Delete button
                    if (_sectionsData[sectionIndex].questions.length > 1)
                      IconButton(
                        icon: Icon(Icons.delete, size: 18, color: dangerR300),
                        onPressed: () =>
                            _removeQuestion(sectionIndex, questionIndex),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Question Text
            TextFormField(
              controller: question.textController,
              decoration: _inputDecoration('Question Text', Icons.help_outline),
              validator: (value) =>
                  value?.trim().isEmpty ?? true ? 'Required field' : null,
            ),
            const SizedBox(height: 12),

            // Question Type and Required
            Column(
              children: [
                DropdownButtonFormField<QuestionType>(
                  value: question.type,
                  decoration: _inputDecoration('Question Type', Icons.rule),
                  items: QuestionType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(_getQuestionTypeName(type)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        question.type = value;
                        // Initialize options if needed
                        if ((value == QuestionType.multipleChoice ||
                                value == QuestionType.checkboxes) &&
                            question.options.isEmpty) {
                          question.options.addAll([
                            _OptionUIData(controller: TextEditingController()),
                            _OptionUIData(controller: TextEditingController()),
                          ]);
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Required?', style: regularTextStyle(size: 14)),
                    Switch(
                      inactiveThumbColor: neutral300,
                      inactiveTrackColor: neutral200,
                      value: question.isRequired,
                      onChanged: (value) =>
                          setState(() => question.isRequired = value),
                      activeColor: kbpBlue700,
                    ),
                  ],
                ),
              ],
            ),

            // Additional question type specific inputs
            if (question.type == QuestionType.multipleChoice ||
                question.type == QuestionType.checkboxes)
              _buildOptionsEditor(question),

            if (question.type == QuestionType.likertScale)
              _buildLikertScaleEditor(question),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsEditor(_QuestionUIData question) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Answer Options:',
            style: mediumTextStyle(color: kbpBlue700),
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: question.options.length,
            itemBuilder: (context, index) {
              final option = question.options[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: option.controller,
                        decoration:
                            _inputDecoration('Option ${index + 1}', null),
                      ),
                    ),
                    if (question.options.length > 2)
                      IconButton(
                        icon: Icon(Icons.remove, color: dangerR300),
                        onPressed: () {
                          setState(() {
                            final removedOption =
                                question.options.removeAt(index);
                            removedOption.controller.dispose();
                          });
                        },
                      ),
                  ],
                ),
              );
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              'Add Option',
              style: mediumTextStyle(color: kbpBlue700),
            ),
            onPressed: () {
              setState(() {
                question.options
                    .add(_OptionUIData(controller: TextEditingController()));
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLikertScaleEditor(_QuestionUIData question) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Likert Scale Settings:',
            style: mediumTextStyle(color: kbpBlue700),
          ),
          const SizedBox(height: 10),

          // Labels
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: question.likertMinLabelController,
                  decoration: _inputDecoration(
                      'Min Label (e.g., "Strongly Disagree")', null),
                  validator: (value) =>
                      value?.trim().isEmpty ?? true ? 'Required field' : null,
                ),
              ),
              const SizedBox(width: 10),
              const Text("to"),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: question.likertMaxLabelController,
                  decoration: _inputDecoration(
                      'Max Label (e.g., "Strongly Agree")', null),
                  validator: (value) =>
                      value?.trim().isEmpty ?? true ? 'Required field' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Scale Range
          Row(
            children: [
              Text('Scale Range: ', style: regularTextStyle()),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: question.likertScaleMin,
                items: List.generate(5, (i) => i + 1)
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(v.toString()),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      question.likertScaleMin = value;
                      if (question.likertScaleMax < value) {
                        question.likertScaleMax = value;
                      }
                    });
                  }
                },
              ),
              const SizedBox(width: 10),
              const Text("to"),
              const SizedBox(width: 10),
              DropdownButton<int>(
                value: question.likertScaleMax,
                items: List.generate(10, (i) => i + 1)
                    .where((v) => v >= question.likertScaleMin)
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(v.toString()),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => question.likertScaleMax = value);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getQuestionTypeName(QuestionType type) {
    switch (type) {
      case QuestionType.shortAnswer:
        return 'Short Answer';
      case QuestionType.longAnswer:
        return 'Paragraph';
      case QuestionType.multipleChoice:
        return 'Multiple Choice';
      case QuestionType.checkboxes:
        return 'Checkboxes';
      case QuestionType.likertScale:
        return 'Likert Scale';
      default:
        return type.toString().split('.').last;
    }
  }

  InputDecoration _inputDecoration(String label, IconData? icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: regularTextStyle(color: neutral700),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      prefixIcon: icon != null ? Icon(icon, color: kbpBlue700) : null,
    );
  }

  // Fungsi untuk menangani reordering section
  void _onReorderSection(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        // Jika memindahkan ke bawah, sesuaikan index karena
        // item yang dipindahkan akan dihapus terlebih dahulu
        newIndex -= 1;
      }
      final item = _sectionsData.removeAt(oldIndex);
      _sectionsData.insert(newIndex, item);

      // Update order untuk semua section
      for (int i = 0; i < _sectionsData.length; i++) {
        _sectionsData[i].order = i;
      }
    });
  }

  // Fungsi untuk menangani reordering pertanyaan dalam section
  void _onReorderQuestion(int sectionIndex, int oldIndex, int newIndex) {
    if (sectionIndex < 0 || sectionIndex >= _sectionsData.length) return;

    setState(() {
      final section = _sectionsData[sectionIndex];
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = section.questions.removeAt(oldIndex);
      section.questions.insert(newIndex, item);

      // Update order untuk semua pertanyaan
      for (int i = 0; i < section.questions.length; i++) {
        section.questions[i].order = i;
      }
    });
  }

  // 3. Tambahkan metode untuk section reordering
  void _moveSectionUp(int index) {
    if (index <= 0 || index >= _sectionsData.length) return;
    setState(() {
      final section = _sectionsData.removeAt(index);
      _sectionsData.insert(index - 1, section);

      // Update order untuk semua section
      for (int i = 0; i < _sectionsData.length; i++) {
        _sectionsData[i].order = i;
      }
    });
  }

  void _moveSectionDown(int index) {
    if (index < 0 || index >= _sectionsData.length - 1) return;
    setState(() {
      final section = _sectionsData.removeAt(index);
      _sectionsData.insert(index + 1, section);

      // Update order untuk semua section
      for (int i = 0; i < _sectionsData.length; i++) {
        _sectionsData[i].order = i;
      }
    });
  }

// 4. Tambahkan metode untuk question reordering
  void _moveQuestionUp(int sectionIndex, int questionIndex) {
    if (sectionIndex < 0 ||
        sectionIndex >= _sectionsData.length ||
        questionIndex <= 0 ||
        questionIndex >= _sectionsData[sectionIndex].questions.length) {
      return;
    }
    setState(() {
      final section = _sectionsData[sectionIndex];
      final question = section.questions.removeAt(questionIndex);
      section.questions.insert(questionIndex - 1, question);

      // Update order untuk semua pertanyaan
      for (int i = 0; i < section.questions.length; i++) {
        section.questions[i].order = i;
      }
    });
  }

  void _moveQuestionDown(int sectionIndex, int questionIndex) {
    if (sectionIndex < 0 ||
        sectionIndex >= _sectionsData.length ||
        questionIndex < 0 ||
        questionIndex >= _sectionsData[sectionIndex].questions.length - 1) {
      return;
    }
    setState(() {
      final section = _sectionsData[sectionIndex];
      final question = section.questions.removeAt(questionIndex);
      section.questions.insert(questionIndex + 1, question);

      // Update order untuk semua pertanyaan
      for (int i = 0; i < section.questions.length; i++) {
        section.questions[i].order = i;
      }
    });
  }
}

// Helper classes for UI state management
class _SectionUIData {
  final String sectionId;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  int order;
  final List<_QuestionUIData> questions;

  _SectionUIData({
    required this.sectionId,
    required this.titleController,
    required this.descriptionController,
    required this.order,
    required this.questions,
  });

  factory _SectionUIData.createDefault({int order = 0}) {
    return _SectionUIData(
      sectionId: const Uuid().v4(),
      titleController: TextEditingController(),
      descriptionController: TextEditingController(),
      order: order,
      questions: [],
    );
  }

  factory _SectionUIData.fromSection(Section section) {
    return _SectionUIData(
      sectionId: section.sectionId,
      titleController: TextEditingController(text: section.title),
      descriptionController:
          TextEditingController(text: section.description ?? ''),
      order: section.order,
      questions: section.questions
          .map((q) => _QuestionUIData.fromQuestion(q))
          .toList(),
    );
  }

  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    for (var question in questions) {
      question.dispose();
    }
  }
}

class _QuestionUIData {
  final String questionId;
  final TextEditingController textController;
  QuestionType type;
  bool isRequired;
  final List<_OptionUIData> options;
  int likertScaleMin;
  int likertScaleMax;
  final TextEditingController likertMinLabelController;
  final TextEditingController likertMaxLabelController;
  int order;

  _QuestionUIData({
    required this.questionId,
    required this.textController,
    this.type = QuestionType.shortAnswer,
    this.isRequired = false,
    required this.options,
    this.likertScaleMin = 1,
    this.likertScaleMax = 5,
    required this.likertMinLabelController,
    required this.likertMaxLabelController,
    required this.order,
  });

  factory _QuestionUIData.createDefault({int order = 0}) {
    return _QuestionUIData(
      questionId: const Uuid().v4(),
      textController: TextEditingController(),
      type: QuestionType.shortAnswer,
      isRequired: false,
      options: [],
      likertScaleMin: 1,
      likertScaleMax: 5,
      likertMinLabelController: TextEditingController(),
      likertMaxLabelController: TextEditingController(),
      order: order,
    );
  }

  factory _QuestionUIData.fromQuestion(Question question) {
    return _QuestionUIData(
      questionId: question.questionId,
      textController: TextEditingController(text: question.text),
      type: question.type,
      isRequired: question.isRequired,
      options: (question.options ?? [])
          .map((opt) => _OptionUIData(
                controller: TextEditingController(text: opt),
                text: opt,
              ))
          .toList(),
      likertScaleMin: question.likertScaleMin ?? 1,
      likertScaleMax: question.likertScaleMax ?? 5,
      likertMinLabelController:
          TextEditingController(text: question.likertMinLabel ?? ''),
      likertMaxLabelController:
          TextEditingController(text: question.likertMaxLabel ?? ''),
      order: question.order,
    );
  }

  void dispose() {
    textController.dispose();
    likertMinLabelController.dispose();
    likertMaxLabelController.dispose();
    for (var option in options) {
      option.controller.dispose();
    }
  }
}

class _OptionUIData {
  final TextEditingController controller;
  String text;

  _OptionUIData({
    required this.controller,
    this.text = '',
  });
}
