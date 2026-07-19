ALTER TABLE users
    ADD COLUMN username TEXT;

UPDATE users
SET username = 'user_' || LEFT(REPLACE(id::text, '-', ''), 16)
WHERE username IS NULL;

ALTER TABLE users
    ALTER COLUMN username SET NOT NULL,
    ALTER COLUMN username SET DEFAULT ('user_' || LEFT(REPLACE(gen_random_uuid()::text, '-', ''), 16)),
    ADD CONSTRAINT users_username_format_check
        CHECK (username ~ '^[a-z][a-z0-9_]{4,31}$');

CREATE UNIQUE INDEX users_username_unique_idx ON users (username);
