CREATE TABLE user_photos (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    object_key TEXT NOT NULL UNIQUE,
    content_type TEXT NOT NULL,
    bytes INTEGER NOT NULL CHECK (bytes > 0 AND bytes <= 8388608),
    is_avatar BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX user_photos_one_avatar_per_user_idx
    ON user_photos (user_id)
    WHERE is_avatar;

CREATE INDEX user_photos_user_created_at_idx
    ON user_photos (user_id, created_at DESC);
