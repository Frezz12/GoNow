DROP INDEX IF EXISTS activities_visibility_window_idx;
DROP TABLE IF EXISTS activity_reviews;
DROP TABLE IF EXISTS activity_notification_outbox;
DROP TABLE IF EXISTS activity_applications;
DROP TABLE IF EXISTS activity_photos;

ALTER TABLE activities
    DROP CONSTRAINT IF EXISTS activities_cost_amount_check,
    DROP CONSTRAINT IF EXISTS activities_cost_type_check,
    DROP CONSTRAINT IF EXISTS activities_skill_level_check,
    DROP CONSTRAINT IF EXISTS activities_age_range_check,
    DROP CONSTRAINT IF EXISTS activities_join_policy_check,
    DROP CONSTRAINT IF EXISTS activities_map_window_check,
    DROP CONSTRAINT IF EXISTS activities_duration_check,
    DROP CONSTRAINT IF EXISTS activities_location_visibility_check,
    DROP CONSTRAINT IF EXISTS activities_description_length_check,
    DROP CONSTRAINT IF EXISTS activities_title_length_check,
    DROP CONSTRAINT IF EXISTS activities_category_check,
    DROP CONSTRAINT IF EXISTS activities_status_check,
    DROP COLUMN IF EXISTS recruitment_closed,
    DROP COLUMN IF EXISTS additional_questions,
    DROP COLUMN IF EXISTS rules,
    DROP COLUMN IF EXISTS bring_items,
    DROP COLUMN IF EXISTS cost_note,
    DROP COLUMN IF EXISTS cost_amount_cents,
    DROP COLUMN IF EXISTS cost_type,
    DROP COLUMN IF EXISTS skill_level,
    DROP COLUMN IF EXISTS languages,
    DROP COLUMN IF EXISTS age_max,
    DROP COLUMN IF EXISTS age_min,
    DROP COLUMN IF EXISTS join_policy,
    DROP COLUMN IF EXISTS hide_after,
    DROP COLUMN IF EXISTS show_after,
    DROP COLUMN IF EXISTS duration_minutes,
    DROP COLUMN IF EXISTS location_visibility,
    DROP COLUMN IF EXISTS venue_name,
    DROP COLUMN IF EXISTS address,
    DROP COLUMN IF EXISTS description;

ALTER TABLE activities
    ADD CONSTRAINT activities_title_length_check
        CHECK (char_length(btrim(title)) BETWEEN 2 AND 120),
    ADD CONSTRAINT activities_category_check
        CHECK (category IN ('sport', 'walking', 'travel', 'music', 'games', 'help', 'education', 'animals', 'other')),
    ADD CONSTRAINT activities_status_check
        CHECK (status IN ('draft', 'published', 'cancelled', 'completed'));
