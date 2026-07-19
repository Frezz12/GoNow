ALTER TABLE users
    ALTER COLUMN message_privacy SET DEFAULT 'everyone',
    ALTER COLUMN invitation_privacy SET DEFAULT 'everyone';

UPDATE users SET message_privacy = 'everyone' WHERE message_privacy = 'friends';
UPDATE users SET invitation_privacy = 'everyone' WHERE invitation_privacy = 'friends';

ALTER TABLE chat_messages DROP CONSTRAINT chat_messages_kind_check;
ALTER TABLE chat_messages
    ADD CONSTRAINT chat_messages_kind_check
    CHECK (kind IN (
        'text', 'placeProposal', 'timeProposal', 'system', 'invitation',
        'image', 'video', 'file', 'audio', 'voice'
    )),
    ADD COLUMN attachment_object_key TEXT,
    ADD COLUMN attachment_name TEXT,
    ADD COLUMN attachment_content_type TEXT,
    ADD COLUMN attachment_bytes INTEGER,
    ADD COLUMN duration_seconds DOUBLE PRECISION,
    ADD CONSTRAINT chat_messages_attachment_size_check
        CHECK (attachment_bytes IS NULL OR attachment_bytes BETWEEN 1 AND 52428800),
    ADD CONSTRAINT chat_messages_attachment_shape_check
        CHECK (
            (kind NOT IN ('image', 'video', 'file', 'audio', 'voice'))
            OR (
                attachment_object_key IS NOT NULL
                AND attachment_name IS NOT NULL
                AND attachment_content_type IS NOT NULL
                AND attachment_bytes IS NOT NULL
            )
        );

CREATE UNIQUE INDEX chat_messages_attachment_object_key_idx
    ON chat_messages (attachment_object_key)
    WHERE attachment_object_key IS NOT NULL;
