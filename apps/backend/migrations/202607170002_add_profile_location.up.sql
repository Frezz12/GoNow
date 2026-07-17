ALTER TABLE users
    ADD COLUMN relationship_status TEXT,
    ADD COLUMN location_label TEXT,
    ADD COLUMN latitude DOUBLE PRECISION,
    ADD COLUMN longitude DOUBLE PRECISION,
    ADD COLUMN show_distance BOOLEAN NOT NULL DEFAULT TRUE,
    ADD CONSTRAINT users_location_coordinates_check CHECK (
        (latitude IS NULL AND longitude IS NULL)
        OR (
            latitude BETWEEN -90 AND 90
            AND longitude BETWEEN -180 AND 180
        )
    );
