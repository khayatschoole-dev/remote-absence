-- قاعدة بيانات مستقلة لتطبيق الغياب عن بعد (لا تحتوي هويات ولا جوالات)

create table if not exists ra_students (
  id bigint generated always as identity primary key,
  name text not null,
  stage text not null,
  section text not null,
  created_at timestamptz default now()
);

create table if not exists ra_teachers (
  id bigint generated always as identity primary key,
  name text not null unique
);

create table if not exists ra_schedule (
  id bigint generated always as identity primary key,
  day smallint not null check (day between 0 and 4),      -- 0 الأحد ... 4 الخميس
  period smallint not null check (period between 1 and 8),
  stage text not null,
  section text not null,
  teacher_id bigint references ra_teachers(id) on delete cascade,
  unique (day, period, stage, section)
);

create table if not exists ra_sessions (
  id bigint generated always as identity primary key,
  att_date date not null,
  period smallint not null,
  stage text not null,
  section text not null,
  teacher_id bigint references ra_teachers(id) on delete set null,
  teacher_name text,
  absent_count int default 0,
  saved_at timestamptz default now(),
  unique (att_date, period, stage, section)
);

create table if not exists ra_absences (
  id bigint generated always as identity primary key,
  session_id bigint not null references ra_sessions(id) on delete cascade,
  student_id bigint not null references ra_students(id) on delete cascade,
  att_date date not null,
  period smallint not null,
  unique (session_id, student_id)
);

create index if not exists ra_abs_date_idx on ra_absences(att_date);
create index if not exists ra_abs_student_idx on ra_absences(student_id);
create index if not exists ra_sess_date_idx on ra_sessions(att_date);

-- حفظ رصد الحصة دفعة واحدة (يستبدل الرصد السابق لنفس الحصة والفصل)
create or replace function ra_save_session(
  p_date date, p_period int, p_stage text, p_section text,
  p_teacher bigint, p_teacher_name text, p_students bigint[]
) returns bigint
language plpgsql security definer set search_path = public as $$
declare sid bigint;
begin
  insert into ra_sessions(att_date, period, stage, section, teacher_id, teacher_name, absent_count, saved_at)
  values (p_date, p_period, p_stage, p_section, p_teacher, p_teacher_name,
          coalesce(array_length(p_students, 1), 0), now())
  on conflict (att_date, period, stage, section) do update
    set teacher_id = excluded.teacher_id,
        teacher_name = excluded.teacher_name,
        absent_count = excluded.absent_count,
        saved_at = now()
  returning id into sid;

  delete from ra_absences where session_id = sid;

  if coalesce(array_length(p_students, 1), 0) > 0 then
    insert into ra_absences(session_id, student_id, att_date, period)
    select sid, s, p_date, p_period from unnest(p_students) as s;
  end if;
  return sid;
end $$;

alter table ra_students  enable row level security;
alter table ra_teachers  enable row level security;
alter table ra_schedule  enable row level security;
alter table ra_sessions  enable row level security;
alter table ra_absences  enable row level security;

create policy ra_students_all on ra_students for all to anon using (true) with check (true);
create policy ra_teachers_all on ra_teachers for all to anon using (true) with check (true);
create policy ra_schedule_all on ra_schedule for all to anon using (true) with check (true);
create policy ra_sessions_all on ra_sessions for all to anon using (true) with check (true);
create policy ra_absences_all on ra_absences for all to anon using (true) with check (true);

grant execute on function ra_save_session(date, int, text, text, bigint, text, bigint[]) to anon;
