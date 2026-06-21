import '../models/event_creation_model.dart';

class EventCreationController {
  static const String defaultVisibility = 'public';
  static const bool defaultApprovalRequired = true;

  static String normalizeVisibility(String value) {
    return value == 'private' ? 'private' : 'public';
  }

  static EventCreationModel buildModel({
    required String title,
    required String description,
    required String timeLabel,
    required String visibility,
    required bool isApprovalRequired,
    required int maxCapacity,
  }) {
    return EventCreationModel(
      title: title.trim(),
      description: description.trim(),
      timeLabel: timeLabel.trim(),
      visibility: normalizeVisibility(visibility),
      isApprovalRequired: isApprovalRequired,
      maxCapacity: maxCapacity,
    );
  }

  static String? validate({
    required EventCreationModel model,
    required bool hasLocation,
  }) {
    if (model.title.isEmpty) return 'Please enter event name';
    if (!hasLocation) return 'Please allow location access to create an event at your location.';
    if (model.timeLabel.isEmpty || model.timeLabel == 'Select time') {
      return 'Please select event date/time';
    }
    return null;
  }
}
