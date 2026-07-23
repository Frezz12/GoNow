DROP TABLE IF EXISTS conversation_invitations;

ALTER TABLE conversation_members
    DROP COLUMN IF EXISTS archived_at;

ALTER TABLE conversations
    DROP COLUMN IF EXISTS avatar_bytes,
    DROP COLUMN IF EXISTS avatar_content_type,
    DROP COLUMN IF EXISTS avatar_object_key,
    DROP COLUMN IF EXISTS created_by,
    DROP CONSTRAINT conversations_kind_check,
    ADD CONSTRAINT conversations_kind_check
        CHECK (kind IN ('direct', 'meeting', 'activity'));

ALTER TABLE users
    DROP COLUMN IF EXISTS last_seen_at;
