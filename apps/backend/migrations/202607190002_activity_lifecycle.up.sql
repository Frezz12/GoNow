ALTER TABLE activities
    DROP CONSTRAINT IF EXISTS activities_title_length_check,
    DROP CONSTRAINT IF EXISTS activities_category_check,
    DROP CONSTRAINT IF EXISTS activities_status_check;

ALTER TABLE activities
    ADD COLUMN description VARCHAR(3000) NOT NULL DEFAULT '',
    ADD COLUMN address TEXT,
    ADD COLUMN venue_name VARCHAR(120),
    ADD COLUMN location_visibility VARCHAR(32) NOT NULL DEFAULT 'everyone',
    ADD COLUMN duration_minutes INTEGER NOT NULL DEFAULT 60,
    ADD COLUMN show_after TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ADD COLUMN hide_after TIMESTAMPTZ,
    ADD COLUMN join_policy VARCHAR(24) NOT NULL DEFAULT 'request',
    ADD COLUMN age_min SMALLINT,
    ADD COLUMN age_max SMALLINT,
    ADD COLUMN languages TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN skill_level VARCHAR(24) NOT NULL DEFAULT 'any',
    ADD COLUMN cost_type VARCHAR(32) NOT NULL DEFAULT 'free',
    ADD COLUMN cost_amount_cents BIGINT,
    ADD COLUMN cost_note VARCHAR(240),
    ADD COLUMN bring_items TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN rules TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN additional_questions JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN recruitment_closed BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE activities
    ADD CONSTRAINT activities_title_length_check
        CHECK (char_length(btrim(title)) BETWEEN 2 AND 70),
    ADD CONSTRAINT activities_description_length_check
        CHECK (char_length(description) <= 3000),
    ADD CONSTRAINT activities_category_check
        CHECK (category IN ('walking', 'sport', 'travel', 'music', 'games', 'food', 'education', 'animals', 'help', 'event', 'other')),
    ADD CONSTRAINT activities_status_check
        CHECK (status IN ('draft', 'scheduled', 'published', 'full', 'started', 'completed', 'cancelled', 'expired', 'hidden', 'blocked')),
    ADD CONSTRAINT activities_location_visibility_check
        CHECK (location_visibility IN ('everyone', 'accepted_participants', 'one_hour_before')),
    ADD CONSTRAINT activities_duration_check
        CHECK (duration_minutes BETWEEN 1 AND 43200),
    ADD CONSTRAINT activities_map_window_check
        CHECK (hide_after IS NULL OR hide_after > show_after),
    ADD CONSTRAINT activities_join_policy_check
        CHECK (join_policy IN ('request', 'instant')),
    ADD CONSTRAINT activities_age_range_check
        CHECK ((age_min IS NULL OR age_min BETWEEN 0 AND 120) AND (age_max IS NULL OR age_max BETWEEN 0 AND 120) AND (age_min IS NULL OR age_max IS NULL OR age_min <= age_max)),
    ADD CONSTRAINT activities_skill_level_check
        CHECK (skill_level IN ('any', 'beginner', 'intermediate', 'experienced')),
    ADD CONSTRAINT activities_cost_type_check
        CHECK (cost_type IN ('free', 'fixed', 'self_paid', 'estimated')),
    ADD CONSTRAINT activities_cost_amount_check
        CHECK (cost_amount_cents IS NULL OR cost_amount_cents >= 0);

CREATE TABLE activity_photos (
    id UUID PRIMARY KEY,
    activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    object_key TEXT NOT NULL,
    content_type VARCHAR(64) NOT NULL,
    bytes INTEGER NOT NULL CHECK (bytes > 0),
    sort_index SMALLINT NOT NULL CHECK (sort_index BETWEEN 0 AND 5),
    is_cover BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (activity_id, sort_index)
);

CREATE UNIQUE INDEX activity_photos_single_cover_idx
    ON activity_photos (activity_id) WHERE is_cover;

CREATE TABLE activity_applications (
    id UUID PRIMARY KEY,
    activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    applicant_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(24) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled', 'expired')),
    message VARCHAR(1000),
    answers JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (activity_id, applicant_id)
);

CREATE INDEX activity_applications_activity_status_idx
    ON activity_applications (activity_id, status, created_at DESC);
CREATE INDEX activity_applications_applicant_idx
    ON activity_applications (applicant_id, created_at DESC);

CREATE TABLE activity_notification_outbox (
    id UUID PRIMARY KEY,
    activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type VARCHAR(64) NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at TIMESTAMPTZ
);

CREATE TABLE activity_reviews (
    id UUID PRIMARY KEY,
    activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment VARCHAR(2000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (activity_id, author_id, subject_id)
);

CREATE INDEX activities_visibility_window_idx
    ON activities (status, show_after, hide_after, starts_at);
