import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/player_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final profile = playerService.currentProfile;

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PROFILE')),
        body: const Center(child: Text('NO PROFILE DATA')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('OPERATOR PROFILE'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          _buildStatRow('CALLSIGN', profile.displayName, context),
          const Divider(height: 32, color: Colors.grey),
          _buildStatRow('GAMES PLAYED', '${profile.gamesPlayed}', context),
          const SizedBox(height: 16),
          _buildStatRow('BEST SCORE', '${profile.bestScore.toInt()} PTS', context),
          const SizedBox(height: 16),
          _buildStatRow('TOTAL SCORE', '${profile.totalScore.toInt()} PTS', context),
          const SizedBox(height: 48),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () => _showChangeNameDialog(context, playerService),
            child: const Text('CHANGE CALLSIGN'),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            onPressed: () => _confirmReset(context, playerService),
            child: const Text('RESET DATA'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        Text(value, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Future<void> _showChangeNameDialog(BuildContext context, PlayerService service) async {
    final controller = TextEditingController(text: service.currentProfile?.displayName);
    
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('CHANGE CALLSIGN', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          textCapitalization: TextCapitalization.characters,
          maxLength: 12,
          decoration: InputDecoration(
            counterText: '',
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5))),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('SAVE', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await service.updateDisplayName(newName);
    }
  }

  Future<void> _confirmReset(BuildContext context, PlayerService service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('RESET DATA?', style: TextStyle(color: Colors.red)),
        content: const Text('This will permanently delete your local stats and profile. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('RESET', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await service.resetLocalData();
    }
  }
}
