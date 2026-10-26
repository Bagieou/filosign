-- Applied to the FiloSign project as migration 20261026052827 lesson_progress_tracking.

-- Per-lesson progress: a lesson counts once its video was watched and its
-- sign check tried (sign_passed = the sign was actually recognized).
create table if not exists public.lesson_progress (
  user_id      uuid    not null references auth.users(id) on delete cascade,
  video_id     integer not null references public.videos(id) on delete cascade,
  sign_passed  boolean not null default false,
  completed_at timestamptz not null default now(),
  primary key (user_id, video_id)
);
alter table public.lesson_progress enable row level security;
drop policy if exists "read own lesson progress" on public.lesson_progress;
create policy "read own lesson progress" on public.lesson_progress
  for select to authenticated using (auth.uid() = user_id);

create or replace function public.get_lesson_progress()
returns table (video_id integer, sign_passed boolean)
language sql stable security definer set search_path = public as $$
  select lp.video_id, lp.sign_passed from public.lesson_progress lp where lp.user_id = auth.uid();
$$;

-- Lessons are recorded in order only: the first lesson of a category, or one
-- whose previous lesson (by videos.position) is already recorded.
create or replace function public.record_lesson(p_video_id integer, p_sign_passed boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_cat  integer;
  v_pos  integer;
  v_prev integer;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  select category_id, position into v_cat, v_pos from public.videos where id = p_video_id;
  if v_cat is null then raise exception 'video not found'; end if;
  if not coalesce(public.can_access_category(v_user, v_cat), false) then
    raise exception 'category is locked';
  end if;
  select id into v_prev from public.videos
   where category_id = v_cat and position < v_pos
   order by position desc limit 1;
  if v_prev is not null and not exists (
       select 1 from public.lesson_progress where user_id = v_user and video_id = v_prev) then
    raise exception 'finish the previous lesson first';
  end if;
  insert into public.lesson_progress (user_id, video_id, sign_passed)
  values (v_user, p_video_id, p_sign_passed)
  on conflict (user_id, video_id) do update
    set sign_passed  = public.lesson_progress.sign_passed or excluded.sign_passed,
        completed_at = case when excluded.sign_passed and not public.lesson_progress.sign_passed
                            then now() else public.lesson_progress.completed_at end;
end;
$$;

revoke execute on function public.get_lesson_progress() from public, anon;
revoke execute on function public.record_lesson(integer, boolean) from public, anon;
grant execute on function public.get_lesson_progress() to authenticated;
grant execute on function public.record_lesson(integer, boolean) to authenticated;

-- Existing progress: categories already passed count as fully done.
insert into public.lesson_progress (user_id, video_id, sign_passed)
select cp.user_id, v.id, true
  from public.category_progress cp
  join public.videos v on v.category_id = cp.category_id
 where cp.passed
on conflict (user_id, video_id) do nothing;

-- Switch: 1 = submit_quiz requires every sign of the category passed.
-- Starts at 0 so older app versions (which never record lessons) keep working.
insert into public.app_config (key, value) values ('require_lessons', 0)
on conflict (key) do nothing;

create or replace function public.submit_quiz(p_category_id integer, p_score numeric)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_user uuid := auth.uid();
  v_pass numeric := (select value from public.app_config where key = 'pass_score');
  v_passed boolean;
  v_next int;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  if p_score < 0 or p_score > 100 then raise exception 'invalid score'; end if;

  -- coalesce: an unknown category id returns null, which must count as locked
  if not coalesce(public.can_access_category(v_user, p_category_id), false) then
    raise exception 'category is locked';
  end if;

  -- every lesson of the category must have its sign passed (when switched on)
  if coalesce((select value from public.app_config where key = 'require_lessons'), 0) = 1
     and exists (select 1 from public.videos v
                  where v.category_id = p_category_id
                    and not exists (select 1 from public.lesson_progress lp
                                     where lp.user_id = v_user and lp.video_id = v.id
                                       and lp.sign_passed)) then
    raise exception 'finish all lessons of this category first';
  end if;

  v_passed := p_score >= v_pass;

  insert into public.quiz_attempts (user_id, category_id, score, passed)
  values (v_user, p_category_id, p_score, v_passed);

  insert into public.category_progress
    (user_id, category_id, passed, best_quiz_score, last_quiz_score, attempts, completed_at)
  values
    (v_user, p_category_id, v_passed, p_score, p_score, 1,
     case when v_passed then now() end)
  on conflict (user_id, category_id) do update
    set passed          = public.category_progress.passed or v_passed,
        best_quiz_score = greatest(public.category_progress.best_quiz_score, p_score),
        last_quiz_score = p_score,
        attempts        = public.category_progress.attempts + 1,
        completed_at    = coalesce(public.category_progress.completed_at,
                                   case when v_passed then now() end);

  perform public.record_activity();

  select c2.id into v_next
  from public.categories c1
  join public.categories c2 on c2.position = c1.position + 1
  where c1.id = p_category_id;

  return jsonb_build_object(
    'passed', v_passed,
    'score', p_score,
    'retake_required', not v_passed,
    'next_category_unlocked', case when v_passed then v_next end
  );
end;
$function$;
