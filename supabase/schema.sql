-- ============================================================
-- hd-03 회원가입 실습 — 데이터베이스 만들기
--
-- 사용법
--   1. Supabase 대시보드 > SQL Editor > New query
--   2. 이 파일 내용을 통째로 붙여넣고 Run
--   3. 아래 "확인" 절의 쿼리로 잘 됐는지 본다
--
-- 여러 번 실행해도 안전하게 짰습니다. 실수했다 싶으면 그냥 다시 실행하세요.
-- ============================================================


-- ------------------------------------------------------------
-- 왜 이름 앞에 hd03_ 를 붙이나
--
-- Supabase 프로젝트 하나에는 여러 사이트의 표가 함께 들어갈 수 있습니다.
-- 이름을 그냥 profiles 라고 지으면 다음에 만드는 사이트와 부딪힙니다.
-- 그래서 사이트마다 앞에 짧은 접두사를 붙입니다.
--
-- 본인 것으로 바꾸고 싶으면 이 파일에서 hd03_ 를 전부 찾아 바꾸고,
-- index.html 의 PROFILE_TABLE 값도 똑같이 바꾸면 됩니다.
-- ------------------------------------------------------------

begin;

-- ------------------------------------------------------------
-- 1) 회원 정보를 담을 표
--
-- id 가 auth.users 를 가리킵니다. 로그인 계정 1개당 프로필 1개입니다.
-- on delete cascade: 계정을 지우면 프로필도 같이 지워집니다.
--
-- check 는 값이 조건에 맞지 않으면 아예 저장을 거부하는 장치입니다.
-- 화면(JS)에서도 검사하지만, 화면 검사는 개발자 도구로 우회할 수 있습니다.
-- 진짜 방어선은 여기입니다.
-- ------------------------------------------------------------
create table if not exists public.hd03_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  full_name text not null check (char_length(btrim(full_name)) between 2 and 50),
  phone text not null check (phone ~ '^01[016789][0-9]{7,8}$'),
  privacy_consent_at timestamptz not null default now(),
  site_code text not null default 'hd-03',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.hd03_profiles is 'hd-03 회원가입 실습용 프로필. 로그인 계정과 1:1.';
comment on column public.hd03_profiles.phone is '하이픈 없이 숫자만 저장합니다. 예: 01012345678';


-- ------------------------------------------------------------
-- 2) RLS — 여기가 이 수업의 핵심입니다
--
-- 브라우저에 넣은 publishable 키는 누구나 볼 수 있습니다.
-- 그래서 "키를 아는 사람"이 아니라 "로그인한 본인"만 자기 행을 보게 막아야 합니다.
-- 그 장치가 RLS(Row Level Security)입니다.
--
-- enable row level security 를 켜면 기본이 "전부 차단"이 됩니다.
-- 그다음 policy 로 허용할 것만 하나씩 열어 줍니다.
--
-- ⚠ RLS를 켜지 않으면 키를 가진 누구나 전체 회원 명단을 내려받을 수 있습니다.
--    실제로 자주 나는 사고입니다.
-- ------------------------------------------------------------
alter table public.hd03_profiles enable row level security;

-- 비로그인 방문자(anon)는 이 표에 아예 손댈 수 없습니다.
revoke all on table public.hd03_profiles from anon;

-- 로그인 사용자에게 필요한 것은 조회와 수정뿐입니다.
-- 삽입은 아래 트리거가 대신 하고, 삭제는 계정 삭제로만 일어납니다.
revoke all on table public.hd03_profiles from authenticated;
grant select, update on table public.hd03_profiles to authenticated;

drop policy if exists "hd03_profiles_select_own" on public.hd03_profiles;
drop policy if exists "hd03_profiles_update_own" on public.hd03_profiles;

-- auth.uid() 는 "지금 요청을 보낸 로그인 사용자의 id"입니다.
-- 그것이 행의 id 와 같을 때만 통과시킵니다. 남의 행은 아예 안 보입니다.
create policy "hd03_profiles_select_own"
on public.hd03_profiles
for select
to authenticated
using ((select auth.uid()) = id);

-- update 에는 using 과 with check 가 둘 다 필요합니다.
--   using      : 어떤 행을 고칠 수 있는가
--   with check : 고친 결과가 어떠해야 하는가
-- with check 를 빼면 남의 id 로 바꿔치기하는 수정이 통과합니다.
create policy "hd03_profiles_update_own"
on public.hd03_profiles
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);


-- ------------------------------------------------------------
-- 3) 가입하면 프로필이 자동으로 생기게
--
-- 회원가입은 auth.users 에 계정이 생기는 일입니다.
-- 우리 표에도 한 줄 넣어야 하는데, 브라우저가 두 번 나눠 요청하면
-- 중간에 창을 닫았을 때 계정만 있고 프로필이 없는 상태가 됩니다.
-- 그래서 계정이 생기는 순간 데이터베이스가 알아서 넣게 합니다. 이것이 트리거입니다.
--
-- security definer: 이 함수는 만든 사람(관리자) 권한으로 돕니다.
--   그래서 RLS로 막아 둔 표에도 넣을 수 있습니다.
-- set search_path = '': 함수가 볼 스키마를 비워 두고 이름을 전부 public. 으로 적습니다.
--   이걸 빼면 남이 만든 같은 이름 함수가 대신 불릴 수 있습니다(보안 사고 유형).
-- ------------------------------------------------------------
create or replace function public.hd03_handle_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_email text;
  v_name text;
  v_phone text;
  v_site_code text;
  v_consent text;
begin
  v_email := lower(btrim(coalesce(new.email, '')));
  v_name  := btrim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));

  -- 화면에서 010-1234-5678 처럼 보내도 숫자만 남깁니다.
  v_phone := regexp_replace(coalesce(new.raw_user_meta_data ->> 'phone', ''), '[^0-9]', '', 'g');

  v_consent := lower(coalesce(new.raw_user_meta_data ->> 'privacy_consent', 'false'));

  -- 값이 비어 있으면 기본값으로 되돌립니다.
  -- nullif 만 쓰면 NULL 이 되는데, site_code 는 not null 이라 가입 전체가 실패합니다.
  v_site_code := coalesce(
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'site_code', '')), ''),
    'hd-03'
  );

  if v_email = '' then
    raise exception '이메일이 없어 회원 정보를 만들 수 없습니다.';
  end if;

  if char_length(v_name) < 2 or char_length(v_name) > 50 then
    raise exception '이름은 2~50자여야 합니다.';
  end if;

  if v_phone !~ '^01[016789][0-9]{7,8}$' then
    raise exception '휴대전화 번호 형식이 올바르지 않습니다.';
  end if;

  if v_consent <> 'true' then
    raise exception '개인정보 수집·이용 동의가 필요합니다.';
  end if;

  insert into public.hd03_profiles (
    id, email, full_name, phone, privacy_consent_at, site_code
  )
  values (
    new.id, v_email, v_name, v_phone, now(), v_site_code
  )
  -- 같은 id 가 이미 있으면 새로 넣는 대신 갱신합니다.
  -- on conflict 를 빼면 두 번째 시도에서 오류가 납니다.
  on conflict (id) do update
  set email = excluded.email,
      full_name = excluded.full_name,
      phone = excluded.phone,
      site_code = excluded.site_code,
      updated_at = now();

  return new;
end;
$fn$;

-- 함수 실행 권한은 두 군데서 자동으로 붙습니다.
--   ① PostgreSQL 이 만들 때 PUBLIC 에게 주는 기본값
--   ② Supabase 가 새 함수마다 anon 에게 자동으로 주는 것
-- 그래서 PUBLIC 만 회수하면 anon 이 남습니다. 둘 다 끊어야 합니다.
revoke all on function public.hd03_handle_signup() from public;
revoke all on function public.hd03_handle_signup() from anon;
grant execute on function public.hd03_handle_signup() to authenticated;

drop trigger if exists hd03_on_auth_user_created on auth.users;

-- when 절에 주목하세요.
-- 이 프로젝트에 다른 사이트의 가입도 들어온다면, 조건 없이 걸었을 때
-- 위에서 raise 한 오류가 그 사이트들의 가입까지 전부 막아 버립니다.
-- 그래서 "우리 화면에서 온 가입"일 때만 발동하게 합니다.
--
-- 이 문자열은 index.html 의 SIGNUP_SOURCE 와 정확히 같아야 합니다.
-- 한 글자만 달라도 오류 없이 조용히 프로필이 안 만들어집니다. 찾기 어려운 종류의 버그입니다.
create trigger hd03_on_auth_user_created
after insert on auth.users
for each row
when ((new.raw_user_meta_data ->> 'signup_source') = 'hd03-membership-v1')
execute function public.hd03_handle_signup();


-- ------------------------------------------------------------
-- 4) 수정할 때마다 updated_at 을 자동으로 갱신
--
-- 앱에서 매번 챙기면 빠뜨리기 쉽습니다. 데이터베이스가 하게 둡니다.
-- ------------------------------------------------------------
create or replace function public.hd03_set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

revoke all on function public.hd03_set_updated_at() from public;
revoke all on function public.hd03_set_updated_at() from anon;
grant execute on function public.hd03_set_updated_at() to authenticated;

drop trigger if exists hd03_set_updated_at on public.hd03_profiles;

create trigger hd03_set_updated_at
before update on public.hd03_profiles
for each row
execute function public.hd03_set_updated_at();

commit;


-- ============================================================
-- 확인
--
-- (1) 표가 생겼는가
--     select * from public.hd03_profiles;
--     -> 아직 가입 전이니 0줄이 정상입니다. 오류가 안 나면 성공입니다.
--
-- (2) RLS 가 켜졌는가
--     select relrowsecurity from pg_class
--      where oid = 'public.hd03_profiles'::regclass;
--     -> true 여야 합니다. false 면 위 2)번을 다시 실행하세요.
--
-- (3) 정책이 2개 있는가
--     select policyname, cmd from pg_policies
--      where tablename = 'hd03_profiles';
--     -> select 1개, update 1개
--
-- (4) 함수에 anon 권한이 남지 않았는가
--     select proname, array_to_string(proacl, E'\n') from pg_proc p
--       join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and proname like 'hd03%';
--     -> anon=X 라는 글자가 보이면 안 됩니다.
--
--
-- 대시보드에서 함께 해 둘 것
--
--   Authentication > Sign In / Providers > Email
--     Email 을 켜 둡니다. 처음 연습할 때는 "Confirm email" 을 꺼 두면
--     메일 확인 없이 바로 로그인돼서 편합니다. 다 되면 다시 켜세요.
--
--   Authentication > URL Configuration
--     Site URL 에 본인 사이트 주소를 넣습니다.
--     예) https://<본인아이디>.github.io/hd-03/
--     이걸 안 하면 메일의 링크가 엉뚱한 곳으로 갑니다.
-- ============================================================
