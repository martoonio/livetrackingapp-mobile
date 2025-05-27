import 'package:flutter/material.dart';
import 'package:livetrackingapp/domain/entities/survey/question.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';

class QuestionWidget extends StatefulWidget {
  final Question question;
  final dynamic initialValue;
  final ValueChanged<dynamic> onAnswerChanged;

  const QuestionWidget({
    super.key,
    required this.question,
    this.initialValue,
    required this.onAnswerChanged,
  });

  @override
  State<QuestionWidget> createState() => _QuestionWidgetState();
}

class _QuestionWidgetState extends State<QuestionWidget> {
  dynamic _currentValue;
  List<String> _selectedCheckboxOptions = [];
  TextEditingController _textController = TextEditingController();


  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
    if (widget.question.type == QuestionType.checkboxes && widget.initialValue is List) {
      _selectedCheckboxOptions = List<String>.from(widget.initialValue);
    } else if ((widget.question.type == QuestionType.shortAnswer || widget.question.type == QuestionType.longAnswer) && widget.initialValue is String) {
      _textController.text = widget.initialValue;
    }
  }

   @override
  void didUpdateWidget(covariant QuestionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      setState(() {
        _currentValue = widget.initialValue;
        if (widget.question.type == QuestionType.checkboxes && widget.initialValue is List) {
          _selectedCheckboxOptions = List<String>.from(widget.initialValue);
        } else if ((widget.question.type == QuestionType.shortAnswer || widget.question.type == QuestionType.longAnswer) && widget.initialValue is String) {
          _textController.text = widget.initialValue;
        }
      });
    }
  }


  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Widget _buildQuestionTitle() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            widget.question.text,
            style: semiBoldTextStyle(size: 16, color: neutral900),
          ),
        ),
        if (widget.question.isRequired)
          Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: Text('*', style: boldTextStyle(size: 16, color: dangerR500)),
          ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildQuestionTitle(),
        const SizedBox(height: 12),
        _buildAnswerInput(),
      ],
    );
  }

  Widget _buildAnswerInput() {
    switch (widget.question.type) {
      case QuestionType.shortAnswer:
        return TextFormField(
          controller: _textController,
          decoration: inputDecoration('Jawaban singkat Anda'),
          onChanged: (value) {
             _currentValue = value;
             widget.onAnswerChanged(value);
          },
          validator: widget.question.isRequired
              ? (value) => (value == null || value.isEmpty)
                  ? 'Pertanyaan ini wajib diisi.'
                  : null
              : null,
        );
      case QuestionType.longAnswer:
        return TextFormField(
          controller: _textController,
          decoration: inputDecoration('Jawaban panjang Anda'),
          maxLines: 3,
          onChanged: (value) {
            _currentValue = value;
            widget.onAnswerChanged(value);
          },
          validator: widget.question.isRequired
              ? (value) => (value == null || value.isEmpty)
                  ? 'Pertanyaan ini wajib diisi.'
                  : null
              : null,
        );
      case QuestionType.multipleChoice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widget.question.options?.map((option) {
                return RadioListTile<String>(
                  title: Text(option, style: regularTextStyle()),
                  value: option,
                  groupValue: _currentValue as String?,
                  onChanged: (String? value) {
                    setState(() {
                      _currentValue = value;
                    });
                    widget.onAnswerChanged(value);
                  },
                  activeColor: kbpBlue900,
                  contentPadding: EdgeInsets.zero,
                );
              }).toList() ??
              [],
        );
      case QuestionType.checkboxes:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widget.question.options?.map((option) {
                return CheckboxListTile(
                  title: Text(option, style: regularTextStyle()),
                  value: _selectedCheckboxOptions.contains(option),
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedCheckboxOptions.add(option);
                      } else {
                        _selectedCheckboxOptions.remove(option);
                      }
                      _currentValue = List<String>.from(_selectedCheckboxOptions); // Salin list
                    });
                    widget.onAnswerChanged(List<String>.from(_selectedCheckboxOptions));
                  },
                  activeColor: kbpBlue900,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                );
              }).toList() ??
              [],
        );
      case QuestionType.likertScale:
        final min = widget.question.likertScaleMin ?? 1;
        final max = widget.question.likertScaleMax ?? 5;
        return Column(
          children: [
            SliderTheme(
                data: SliderTheme.of(context).copyWith(
                    activeTrackColor: kbpBlue700,
                    inactiveTrackColor: kbpBlue200,
                    thumbColor: kbpBlue900,
                    overlayColor: kbpBlue700.withOpacity(0.2),
                    valueIndicatorColor: kbpBlue900,
                    valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                    trackHeight: 6.0,
                ),
                child: Slider(
                    value: (_currentValue as num? ?? min).toDouble(),
                    min: min.toDouble(),
                    max: max.toDouble(),
                    divisions: (max - min == 0) ? 1 : (max-min), // Hindari pembagian dengan nol
                    label: (_currentValue as num? ?? min).round().toString(),
                    onChanged: (double value) {
                        setState(() {
                        _currentValue = value.round();
                        });
                        widget.onAnswerChanged(value.round());
                    },
                ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.question.likertMinLabel ?? min.toString(), style: regularTextStyle(size: 12, color: neutral700)),
                  Text(widget.question.likertMaxLabel ?? max.toString(), style: regularTextStyle(size: 12, color: neutral700)),
                ],
              ),
            ),
          ],
        );
      default:
        return Text('Tipe pertanyaan tidak didukung: ${widget.question.type}');
    }
  }
}