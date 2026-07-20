DROP INDEX IF EXISTS conversations_activity_id_unique_idx;

DELETE FROM conversations
WHERE activity_id IS NOT NULL;

ALTER TABLE conversations
    DROP COLUMN IF EXISTS activity_id;
