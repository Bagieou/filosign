# Supabase changes made from this repo

`2026-10-26_lesson_progress.sql` was applied to the FiloSign project (cdkfwqlktrlyferpmpug)
as migration `lesson_progress_tracking`:

- table `lesson_progress` (user, video, sign_passed, completed_at), read-own RLS
- `get_lesson_progress()`, `record_lesson(p_video_id, p_sign_passed)` (in-order only)
- backfill: categories already passed count as fully done
- `submit_quiz`: rejects the quiz unless every sign of the category is passed,
  only when `app_config.require_lessons = 1` (starts at 0 for older app versions)

Turn the quiz check on once everyone has the new app:
    update public.app_config set value = 1 where key = 'require_lessons';
