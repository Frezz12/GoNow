ALTER TABLE chat_messages
    ADD COLUMN reply_to_id UUID REFERENCES chat_messages(id) ON DELETE SET NULL,
    ADD COLUMN edited_at TIMESTAMPTZ;

CREATE INDEX chat_messages_reply_to_idx
    ON chat_messages (reply_to_id)
    WHERE reply_to_id IS NOT NULL;
