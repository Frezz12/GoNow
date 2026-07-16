ALTER TABLE users
    ADD COLUMN birth_date DATE,
    ADD COLUMN city TEXT,
    ADD COLUMN occupation TEXT,
    ADD COLUMN bio TEXT,
    ADD COLUMN interests TEXT[] NOT NULL DEFAULT '{}';
