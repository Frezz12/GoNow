ALTER TABLE users
    DROP CONSTRAINT users_location_coordinates_check,
    DROP COLUMN show_distance,
    DROP COLUMN longitude,
    DROP COLUMN latitude,
    DROP COLUMN location_label,
    DROP COLUMN relationship_status;
