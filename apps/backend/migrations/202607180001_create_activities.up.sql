CREATE TABLE activities (
    id UUID PRIMARY KEY,
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(120) NOT NULL,
    category VARCHAR(32) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    participant_limit INTEGER CHECK (participant_limit IS NULL OR participant_limit > 0),
    status VARCHAR(24) NOT NULL DEFAULT 'published',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX activities_map_visibility_idx
    ON activities (status, starts_at);
CREATE INDEX activities_latitude_idx ON activities (latitude);
CREATE INDEX activities_longitude_idx ON activities (longitude);
CREATE INDEX activities_creator_idx ON activities (creator_id, created_at DESC);
