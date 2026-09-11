# safespit

## Score persistence

Completed challenge scores are always saved locally first. To enable Supabase
sync, run the SQL migration at `backend/migrations/001_scores.sql` in the
Supabase SQL editor, enable anonymous authentication, and build with:

`flutter run -d RZCW310M0ZR --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_KEY`

The publishable key is safe to use in a client app with the RLS policies from
the migration. Never use a Supabase `service_role` key in Flutter. Without
these defines, scores remain in the local offline queue and the game remains
fully usable.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
