DROP INDEX IF EXISTS users_username_unique_idx;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_username_format_check,
    DROP COLUMN IF EXISTS username;
