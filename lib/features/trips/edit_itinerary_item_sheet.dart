import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'itinerary_item_model.dart';
import 'itinerary_provider.dart';

class EditItineraryItemSheet extends ConsumerStatefulWidget {
  final ItineraryItem item;

  const EditItineraryItemSheet({super.key, required this.item});

  @override
  ConsumerState<EditItineraryItemSheet> createState() =>
      _EditItineraryItemSheetState();
}

class _EditItineraryItemSheetState
    extends ConsumerState<EditItineraryItemSheet> {
  late TextEditingController titleController;
  late TextEditingController descriptionController;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.item.title);
    descriptionController =
        TextEditingController(text: widget.item.description);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Edit Itinerary Item',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: titleController,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: descriptionController,
            decoration: const InputDecoration(labelText: 'Description'),
            maxLines: 3,
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: () {
              final updated = widget.item.copyWith(
                title: titleController.text.trim(),
                description: descriptionController.text.trim(),
              );

              ref
                  .read(itineraryProvider.notifier)
                  .updateItem(updated);

              Navigator.pop(context);
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}
