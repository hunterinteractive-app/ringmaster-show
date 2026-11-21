import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Show-specific guidance displayed before the registration form.
class ShowRegistrationNotice extends StatelessWidget {
  const ShowRegistrationNotice({super.key, required this.showId});

  final String showId;

  // Houston 2027 Open and Youth Breeding Rabbit only. The Cavy and Youth
  // Meat Pen shows have separate registration rules.
  static const _breedUpdateShows = {
    '232b7ed8-8032-4c05-aa87-db8e00de7dc2',
    '275bbfe9-6ef7-4c86-b914-23afee7ceffc',
  };

  @override
  Widget build(BuildContext context) {
    if (!_breedUpdateShows.contains(showId)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: AppTheme.surfaceTextScope(
        context,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: AppColors.secondaryButton),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Breed can be updated at check-in.',
                  style: TextStyle(color: AppColors.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
