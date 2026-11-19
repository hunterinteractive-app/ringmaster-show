import 'package:flutter/material.dart';

import '../screens/my_animals_screen.dart';
import '../screens/my_entries_screen.dart';
import '../screens/show_list_screen.dart';
import '../theme/app_theme.dart';

enum ExhibitorDestination { shows, entries, animals }

class ExhibitorNavigation extends StatelessWidget {
  const ExhibitorNavigation({super.key, required this.current});

  final ExhibitorDestination current;

  static const _fromShows = 'exhibitor-tab';

  void _select(BuildContext context, ExhibitorDestination destination) {
    if (destination == current) return;

    final navigator = Navigator.of(context);
    final fromShows = ModalRoute.of(context)?.settings.name == _fromShows;
    if (destination == ExhibitorDestination.shows &&
        fromShows &&
        navigator.canPop()) {
      navigator.pop();
      return;
    }

    final route = MaterialPageRoute<void>(
      settings: current == ExhibitorDestination.shows || fromShows
          ? const RouteSettings(name: _fromShows)
          : null,
      builder: (_) => switch (destination) {
        ExhibitorDestination.shows => const ShowListScreen(),
        ExhibitorDestination.entries => const MyEntriesScreen(),
        ExhibitorDestination.animals => const MyAnimalsScreen(),
      },
    );
    if (current == ExhibitorDestination.shows) {
      navigator.push(route);
    } else {
      navigator.pushReplacement(route);
    }
  }

  @override
  Widget build(BuildContext context) => NavigationBar(
    height: 64,
    backgroundColor: AppColors.surface,
    indicatorColor: AppColors.primaryButton,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    selectedIndex: current.index,
    onDestinationSelected: (index) =>
        _select(context, ExhibitorDestination.values[index]),
    destinations: const [
      NavigationDestination(icon: Icon(Icons.event_outlined), label: 'Shows'),
      NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        label: 'My Entries',
      ),
      NavigationDestination(icon: Icon(Icons.pets), label: 'My Animals'),
    ],
  );
}
