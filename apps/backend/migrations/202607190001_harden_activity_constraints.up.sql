ALTER TABLE activities
    ADD CONSTRAINT activities_title_length_check
        CHECK (char_length(btrim(title)) BETWEEN 2 AND 120),
    ADD CONSTRAINT activities_category_check
        CHECK (category IN ('sport', 'walking', 'travel', 'music', 'games', 'help', 'education', 'animals', 'other')),
    ADD CONSTRAINT activities_participant_limit_upper_check
        CHECK (participant_limit IS NULL OR participant_limit <= 100000),
    ADD CONSTRAINT activities_status_check
        CHECK (status IN ('draft', 'published', 'cancelled', 'completed'));

CREATE INDEX activities_status_coordinates_idx
    ON activities (status, latitude, longitude);
