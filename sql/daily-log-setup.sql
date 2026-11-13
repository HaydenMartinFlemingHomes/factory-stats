-- Platform 1 Daily Log — database setup
-- Run ONCE in Supabase: Dashboard -> SQL Editor -> New query -> paste all of this -> Run.
-- Safe to re-run: it only creates things that don't already exist.
-- Does NOT touch the existing Factory Stats table (fh_projects).

-- 1. Projects (entered at project start-up)
create table if not exists public.line_projects (
  id                 uuid primary key default gen_random_uuid(),
  project_ref        text not null unique,
  project_name       text not null,
  project_type       text not null check (project_type in ('standard','ifb')),
  budget_days        numeric(6,2) check (budget_days is null or budget_days >= 0),
  target_completion  timestamptz,
  status             text not null default 'active' check (status in ('active','complete')),
  created_by         text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- 2. Project readiness (entered at the start, or part way — can be several per project)
create table if not exists public.line_readiness (
  id                  uuid primary key default gen_random_uuid(),
  project_id          uuid not null references public.line_projects(id) on delete cascade,
  entry_date          date not null default current_date,
  cutting_list_ready  boolean,
  cut_gap_mins        integer check (cut_gap_mins is null or cut_gap_mins >= 0),
  cut_gap_reason      text,
  drawings_ready      boolean,
  panel_gap_mins      integer check (panel_gap_mins is null or panel_gap_mins >= 0),
  panel_gap_reason    text,
  entered_by          text,
  created_at          timestamptz not null default now()
);

-- 3. Daily record (one per project per day; updated through the day)
create table if not exists public.line_daily (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.line_projects(id) on delete cascade,
  work_date          date not null,
  people_on_line     integer check (people_on_line is null or people_on_line >= 0),
  target_qty         integer check (target_qty is null or target_qty >= 0),
  q1                 integer check (q1 is null or q1 >= 0),
  q2                 integer check (q2 is null or q2 >= 0),
  q3                 integer check (q3 is null or q3 >= 0),
  q4                 integer check (q4 is null or q4 >= 0),
  cdt_fouls          integer check (cdt_fouls is null or cdt_fouls >= 0),
  cdt_downtime_mins  integer check (cdt_downtime_mins is null or cdt_downtime_mins >= 0),
  disruptions        text,
  entered_by         text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (project_id, work_date)
);

-- 4. End of project (fouls + internal panels; one per project)
create table if not exists public.line_project_end (
  project_id                    uuid primary key references public.line_projects(id) on delete cascade,
  planing_fouls                 integer check (planing_fouls is null or planing_fouls >= 0),
  cutting_fouls                 integer check (cutting_fouls is null or cutting_fouls >= 0),
  ripping_fouls                 integer check (ripping_fouls is null or ripping_fouls >= 0),
  subbing_fouls                 integer check (subbing_fouls is null or subbing_fouls >= 0),
  panel_fouls                   integer check (panel_fouls is null or panel_fouls >= 0),
  cdt_fouls                     integer check (cdt_fouls is null or cdt_fouls >= 0),
  machine_fouls_mins            integer check (machine_fouls_mins is null or machine_fouls_mins >= 0),
  internal_panels_in_line_time  boolean,
  entered_by                    text,
  completed_at                  timestamptz not null default now()
);

create index if not exists line_daily_date_idx      on public.line_daily (work_date);
create index if not exists line_readiness_proj_idx  on public.line_readiness (project_id, created_at desc);

-- Access for the app (same public key as Factory Stats): read, add and edit.
-- No delete from the app — mistakes are corrected by editing.
alter table public.line_projects    enable row level security;
alter table public.line_readiness   enable row level security;
alter table public.line_daily       enable row level security;
alter table public.line_project_end enable row level security;

grant select, insert, update on public.line_projects, public.line_readiness,
  public.line_daily, public.line_project_end to anon;

do $$
declare t text;
begin
  foreach t in array array['line_projects','line_readiness','line_daily','line_project_end'] loop
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t and policyname='app_select') then
      execute format('create policy app_select on public.%I for select to anon using (true)', t);
    end if;
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t and policyname='app_insert') then
      execute format('create policy app_insert on public.%I for insert to anon with check (true)', t);
    end if;
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t and policyname='app_update') then
      execute format('create policy app_update on public.%I for update to anon using (true) with check (true)', t);
    end if;
  end loop;
end $$;
