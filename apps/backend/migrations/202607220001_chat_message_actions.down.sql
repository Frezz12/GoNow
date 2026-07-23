DROP INDEX IF EXISTS chat_messages_reply_to_idx;
ALTER TABLE chat_messages
    DROP COLUMN IF EXISTS edited_at,
    DROP COLUMN IF EXISTS reply_to_id;
