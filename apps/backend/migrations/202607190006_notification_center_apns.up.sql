CREATE TABLE notification_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    push_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    friend_requests BOOLEAN NOT NULL DEFAULT TRUE,
    messages BOOLEAN NOT NULL DEFAULT TRUE,
    invitations BOOLEAN NOT NULL DEFAULT TRUE,
    activities BOOLEAN NOT NULL DEFAULT TRUE,
    sound_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE push_devices (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    token TEXT NOT NULL UNIQUE,
    platform TEXT NOT NULL DEFAULT 'ios' CHECK (platform IN ('ios')),
    environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
    app_bundle TEXT NOT NULL,
    locale TEXT NOT NULL DEFAULT 'ru',
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, device_id, environment, app_bundle)
);

CREATE INDEX push_devices_delivery_idx
    ON push_devices (user_id, enabled, last_seen_at DESC);

CREATE TABLE notifications (
    id UUID PRIMARY KEY,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
    category TEXT NOT NULL CHECK (category IN ('social', 'messages', 'activities', 'system')),
    kind TEXT NOT NULL CHECK (kind IN (
        'friend_request', 'friend_accepted',
        'invitation', 'invitation_accepted', 'invitation_declined', 'invitation_countered',
        'new_message', 'activity_application', 'application_status',
        'activity_updated', 'activity_reminder', 'activity_cancelled', 'system'
    )),
    title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
    body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 500),
    entity_type TEXT,
    entity_id UUID,
    action_path TEXT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    dedupe_key TEXT,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX notifications_recipient_feed_idx
    ON notifications (recipient_id, created_at DESC, id DESC);
CREATE INDEX notifications_recipient_unread_idx
    ON notifications (recipient_id, created_at DESC) WHERE read_at IS NULL;
CREATE UNIQUE INDEX notifications_recipient_dedupe_idx
    ON notifications (recipient_id, dedupe_key) WHERE dedupe_key IS NOT NULL;

INSERT INTO notifications (
    id, recipient_id, actor_id, category, kind, title, body,
    entity_type, entity_id, action_path, payload, dedupe_key, created_at
)
SELECT outbox.id, outbox.recipient_id, activity.creator_id, 'activities',
       CASE outbox.event_type
           WHEN 'application_created' THEN 'activity_application'
           WHEN 'application_status_changed' THEN 'application_status'
           ELSE 'activity_updated'
       END,
       CASE outbox.event_type
           WHEN 'application_created' THEN 'Новая заявка'
           WHEN 'application_status_changed' THEN 'Статус заявки изменён'
           ELSE 'Активность обновлена'
       END,
       CASE outbox.event_type
           WHEN 'application_created' THEN 'К вашей активности отправили новую заявку'
           WHEN 'application_status_changed' THEN 'Организатор изменил статус вашей заявки'
           ELSE 'Организатор изменил место или время активности'
       END,
       'activity', outbox.activity_id,
       'gonow://activities/' || outbox.activity_id,
       outbox.payload, 'legacy:' || outbox.id, outbox.created_at
FROM activity_notification_outbox outbox
JOIN activities activity ON activity.id = outbox.activity_id
ON CONFLICT DO NOTHING;

UPDATE activity_notification_outbox
SET delivered_at = COALESCE(delivered_at, NOW());
