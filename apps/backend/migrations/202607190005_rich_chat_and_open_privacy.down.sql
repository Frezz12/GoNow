DROP INDEX IF EXISTS chat_messages_attachment_object_key_idx;
ALTER TABLE chat_messages
    DROP CONSTRAINT IF EXISTS chat_messages_attachment_shape_check,
    DROP CONSTRAINT IF EXISTS chat_messages_attachment_size_check,
    DROP CONSTRAINT IF EXISTS chat_messages_kind_check,
    DROP COLUMN IF EXISTS duration_seconds,
    DROP COLUMN IF EXISTS attachment_bytes,
    DROP COLUMN IF EXISTS attachment_content_type,
    DROP COLUMN IF EXISTS attachment_name,
    DROP COLUMN IF EXISTS attachment_object_key;
ALTER TABLE chat_messages
    ADD CONSTRAINT chat_messages_kind_check
    CHECK (kind IN ('text', 'placeProposal', 'timeProposal', 'system', 'invitation'));

ALTER TABLE users
    ALTER COLUMN message_privacy SET DEFAULT 'friends',
    ALTER COLUMN invitation_privacy SET DEFAULT 'friends';
