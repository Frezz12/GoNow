ALTER TABLE users
    ADD COLUMN languages TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN availability TEXT,
    ADD COLUMN preferred_group_size TEXT,
    ADD CONSTRAINT users_preferred_group_size_check CHECK (
        preferred_group_size IS NULL
        OR preferred_group_size IN ('oneToOne', 'smallGroup', 'largeGroup', 'any')
    );
