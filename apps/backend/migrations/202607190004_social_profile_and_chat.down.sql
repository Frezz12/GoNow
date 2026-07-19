DROP TABLE IF EXISTS chat_message_votes;
DROP TABLE IF EXISTS chat_messages;
DROP TABLE IF EXISTS meeting_invitations;
DROP TABLE IF EXISTS conversation_members;
DROP TABLE IF EXISTS conversations;
DROP TABLE IF EXISTS friendships;

ALTER TABLE users
    DROP COLUMN IF EXISTS invitation_privacy,
    DROP COLUMN IF EXISTS message_privacy;

DROP TABLE IF EXISTS profile_photo_likes;
DROP INDEX IF EXISTS user_photos_one_current_avatar_per_user_idx;
DELETE FROM user_photos WHERE is_avatar = TRUE AND is_current_avatar = FALSE;
ALTER TABLE user_photos
    DROP CONSTRAINT IF EXISTS user_photos_current_avatar_kind_check,
    DROP COLUMN IF EXISTS description,
    DROP COLUMN IF EXISTS is_current_avatar;
CREATE UNIQUE INDEX user_photos_one_avatar_per_user_idx
    ON user_photos (user_id)
    WHERE is_avatar;
