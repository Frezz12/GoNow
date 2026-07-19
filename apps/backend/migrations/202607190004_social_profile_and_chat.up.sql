DROP INDEX IF EXISTS user_photos_one_avatar_per_user_idx;

ALTER TABLE user_photos
    ADD COLUMN is_current_avatar BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN description TEXT;

UPDATE user_photos SET is_current_avatar = TRUE WHERE is_avatar = TRUE;

CREATE UNIQUE INDEX user_photos_one_current_avatar_per_user_idx
    ON user_photos (user_id)
    WHERE is_current_avatar;

ALTER TABLE user_photos
    ADD CONSTRAINT user_photos_current_avatar_kind_check
    CHECK (NOT is_current_avatar OR is_avatar);

CREATE TABLE profile_photo_likes (
    photo_id UUID NOT NULL REFERENCES user_photos(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (photo_id, user_id)
);

ALTER TABLE users
    ADD COLUMN message_privacy TEXT NOT NULL DEFAULT 'friends'
        CHECK (message_privacy IN ('everyone', 'friends', 'nobody')),
    ADD COLUMN invitation_privacy TEXT NOT NULL DEFAULT 'friends'
        CHECK (invitation_privacy IN ('everyone', 'friends', 'verified', 'nobody'));

CREATE TABLE friendships (
    user_low UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_high UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    requested_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'declined')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_low, user_high),
    CHECK (user_low <> user_high),
    CHECK (requested_by = user_low OR requested_by = user_high)
);

CREATE INDEX friendships_user_low_idx ON friendships (user_low, status);
CREATE INDEX friendships_user_high_idx ON friendships (user_high, status);

CREATE TABLE conversations (
    id UUID PRIMARY KEY,
    kind TEXT NOT NULL DEFAULT 'direct'
        CHECK (kind IN ('direct', 'meeting', 'activity')),
    direct_key TEXT UNIQUE,
    title TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE conversation_members (
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_read_at TIMESTAMPTZ,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX conversation_members_user_idx
    ON conversation_members (user_id, conversation_id);

CREATE TABLE meeting_invitations (
    id UUID PRIMARY KEY,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_id UUID REFERENCES activities(id) ON DELETE SET NULL,
    conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
    template TEXT NOT NULL,
    proposed_at TIMESTAMPTZ,
    place TEXT,
    message TEXT,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'declined', 'expired', 'countered')),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (sender_id <> recipient_id)
);

CREATE UNIQUE INDEX meeting_invitations_one_pending_pair_idx
    ON meeting_invitations (LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id))
    WHERE status = 'pending';

CREATE INDEX meeting_invitations_recipient_idx
    ON meeting_invitations (recipient_id, status, created_at DESC);

CREATE TABLE chat_messages (
    id UUID PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL DEFAULT 'text'
        CHECK (kind IN ('text', 'placeProposal', 'timeProposal', 'system', 'invitation')),
    body TEXT NOT NULL,
    proposal_detail TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX chat_messages_conversation_created_idx
    ON chat_messages (conversation_id, created_at);

CREATE TABLE chat_message_votes (
    message_id UUID NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, user_id)
);
