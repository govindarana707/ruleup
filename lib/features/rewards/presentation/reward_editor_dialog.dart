import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ruleup/features/rewards/presentation/rewards_wallet_provider.dart';

class RewardEditorDialog extends StatefulWidget {
  const RewardEditorDialog({super.key, required this.draft});

  final RewardDraft draft;

  @override
  State<RewardEditorDialog> createState() => _RewardEditorDialogState();
}

class _RewardEditorDialogState extends State<RewardEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _cost;
  late final TextEditingController _cap;
  XFile? _image;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.draft.name);
    _cost = TextEditingController(text: widget.draft.pointsCost);
    _cap = TextEditingController(text: widget.draft.monetaryCap);
  }

  @override
  void dispose() {
    _name.dispose();
    _cost.dispose();
    _cap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.draft.id != null;
    return AlertDialog(
      key: const Key('reward-editor-dialog'),
      scrollable: true,
      title: Text(editing ? 'Edit reward' : 'Create reward'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('reward-name-field'),
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reward name',
                  hintText: 'Movie night',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a reward name.'
                    : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const Key('pick-reward-image'),
                    onPressed: () async {
                      final image = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 82,
                        maxWidth: 1600,
                        maxHeight: 1600,
                        requestFullMetadata: false,
                      );
                      if (image != null && mounted) {
                        setState(() {
                          _image = image;
                          widget.draft.removeImage = false;
                        });
                      }
                    },
                    icon: const Icon(Icons.photo_outlined),
                    label: Text(
                      _image == null
                          ? (widget.draft.imageKey == null
                                ? 'Add photo'
                                : 'Change photo')
                          : 'Photo selected',
                    ),
                  ),
                  if (_image != null || widget.draft.imageKey != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: TextButton(
                        key: const Key('remove-reward-image'),
                        onPressed: () => setState(() {
                          _image = null;
                          widget.draft.removeImage = true;
                        }),
                        child: const Text('Remove'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('reward-cost-field'),
                controller: _cost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Points cost',
                  helperText: 'Must be a positive whole number.',
                ),
                validator: (value) {
                  final points = int.tryParse(value?.trim() ?? '');
                  return points == null || points <= 0
                      ? 'Enter a positive whole number.'
                      : null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('reward-cap-field'),
                controller: _cap,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Monetary cap (optional)',
                  helperText: 'Metadata only; no payment is made.',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final cap = double.tryParse(value.trim());
                  return cap == null || !cap.isFinite || cap < 0
                      ? 'Enter zero or a positive number.'
                      : null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-reward-button'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            widget.draft
              ..name = _name.text.trim()
              ..pointsCost = _cost.text.trim()
              ..monetaryCap = _cap.text.trim();
            widget.draft.selectedImage = _image;
            Navigator.pop(context, widget.draft);
          },
          child: Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
