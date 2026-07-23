ALTER TABLE users
    ADD COLUMN last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE conversations
    DROP CONSTRAINT conversations_kind_check,
    ADD CONSTRAINT conversations_kind_check
        CHECK (kind IN ('direct', 'meeting', 'activity', 'group')),
    ADD COLUMN created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN avatar_object_key TEXT,
    ADD COLUMN avatar_content_type TEXT,
    ADD COLUMN avatar_bytes INTEGER;

UPDATE conversations conversation
SET created_by = activity.creator_id
FROM activities activity
WHERE conversation.activity_id = activity.id;

ALTER TABLE conversation_members
    ADD COLUMN archived_at TIMESTAMPTZ;

CREATE TABLE conversation_invitations (
    id UUID PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    inviter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    invitee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'declined')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (inviter_id <> invitee_id)
);

CREATE UNIQUE INDEX conversation_invitations_pending_idx
    ON conversation_invitations (conversation_id, invitee_id)
    WHERE status = 'pending';

CREATE INDEX conversation_invitations_invitee_idx
    ON conversation_invitations (invitee_id, status, created_at DESC);
