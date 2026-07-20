ALTER TABLE conversations
    ADD COLUMN activity_id UUID REFERENCES activities(id) ON DELETE CASCADE;

INSERT INTO conversations (id, kind, title, activity_id, created_at, updated_at)
SELECT
    gen_random_uuid(),
    'activity',
    'Активность · ' || activities.title,
    activities.id,
    activities.created_at,
    NOW()
FROM activities;

INSERT INTO conversation_members (conversation_id, user_id, joined_at)
SELECT conversations.id, activities.creator_id, activities.created_at
FROM conversations
JOIN activities ON activities.id = conversations.activity_id
ON CONFLICT (conversation_id, user_id) DO NOTHING;

INSERT INTO conversation_members (conversation_id, user_id, joined_at)
SELECT conversations.id, activity_applications.applicant_id, activity_applications.updated_at
FROM conversations
JOIN activity_applications ON activity_applications.activity_id = conversations.activity_id
WHERE activity_applications.status = 'accepted'
ON CONFLICT (conversation_id, user_id) DO NOTHING;

CREATE UNIQUE INDEX conversations_activity_id_unique_idx
    ON conversations (activity_id)
    WHERE activity_id IS NOT NULL;
