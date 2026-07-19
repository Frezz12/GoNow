DROP INDEX IF EXISTS activities_status_coordinates_idx;

ALTER TABLE activities
    DROP CONSTRAINT IF EXISTS activities_status_check,
    DROP CONSTRAINT IF EXISTS activities_participant_limit_upper_check,
    DROP CONSTRAINT IF EXISTS activities_category_check,
    DROP CONSTRAINT IF EXISTS activities_title_length_check;
