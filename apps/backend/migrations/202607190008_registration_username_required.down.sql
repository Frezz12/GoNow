ALTER TABLE users
    ALTER COLUMN username SET DEFAULT ('user_' || LEFT(REPLACE(gen_random_uuid()::text, '-', ''), 16));
