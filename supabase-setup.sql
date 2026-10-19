-- Scenelet: shared accounts and ratings
-- Paste everything into Supabase → SQL Editor → New query, then press Run.

-- Public profiles (username visible to everyone)
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  username text unique not null check (username ~ '^[a-z0-9_]{3,20}$'),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "Profiles are public" on public.profiles for select using (true);
create policy "Users edit own profile" on public.profiles for update using (auth.uid() = id);

-- Private data (diary, watchlist, lists, likes…)
create table if not exists public.user_data (
  id uuid primary key references auth.users on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.user_data enable row level security;
create policy "Read own data" on public.user_data for select using (auth.uid() = id);
create policy "Insert own data" on public.user_data for insert with check (auth.uid() = id);
create policy "Update own data" on public.user_data for update using (auth.uid() = id);

-- Ratings: public, so every film shows the average of all members
create table if not exists public.ratings (
  user_id uuid not null references auth.users on delete cascade,
  film_id integer not null,
  rating numeric(2,1) not null check (rating >= 0.5 and rating <= 5 and rating * 2 = floor(rating * 2)),
  updated_at timestamptz not null default now(),
  primary key (user_id, film_id)
);
create index if not exists ratings_film_idx on public.ratings (film_id);
alter table public.ratings enable row level security;
create policy "Ratings are public" on public.ratings for select using (true);
create policy "Insert own rating" on public.ratings for insert with check (auth.uid() = user_id);
create policy "Update own rating" on public.ratings for update using (auth.uid() = user_id);
create policy "Delete own rating" on public.ratings for delete using (auth.uid() = user_id);

-- Create the profile automatically when someone signs up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username) values (new.id, new.raw_user_meta_data->>'username');
  insert into public.user_data (id) values (new.id);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();
