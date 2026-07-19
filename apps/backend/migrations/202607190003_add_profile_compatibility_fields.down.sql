ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_preferred_group_size_check,
    DROP COLUMN IF EXISTS preferred_group_size,
    DROP COLUMN IF EXISTS availability,
    DROP COLUMN IF EXISTS languages;
