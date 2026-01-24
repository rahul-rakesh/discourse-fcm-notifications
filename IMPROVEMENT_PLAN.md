# FCM Notifications Plugin Improvement Plan

## Implementation Status: ✅ COMPLETE (Phases 1-7)

**Last Updated:** 2026-01-24

---

## Overview

This document outlines the improvements needed for the `discourse-fcm-notifications` plugin to support:
1. **Multi-device token storage** - Store multiple FCM tokens per user (for multiple devices)
2. **Comprehensive logging** - Admin-visible logs for debugging notification delivery
3. **Token management** - Better validation, cleanup, and admin UI
4. **Error handling** - Graceful handling of invalid tokens and delivery failures

---

## Implementation Progress

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Database Model for Tokens | ✅ Complete |
| Phase 2 | Logging System | ✅ Complete |
| Phase 3 | Updated Pusher Service | ✅ Complete |
| Phase 4 | Updated Controller | ✅ Complete |
| Phase 5 | Admin Interface | ✅ Complete |
| Phase 6 | Updated Plugin Entry Point | ✅ Complete |
| Phase 7 | Migration from Custom Fields | ✅ Complete |
| Phase 8 | Flutter App Updates | ⏳ Pending (separate repo) |

---

## Files Created/Modified

### New Files Created:

```
db/migrate/20250124230246_create_fcm_tokens.rb
db/migrate/20250124230247_create_fcm_notification_logs.rb
db/migrate/20250124230248_migrate_custom_fields_to_fcm_tokens.rb
app/models/discourse_fcm_notifications/fcm_token.rb
app/models/discourse_fcm_notifications/fcm_notification_log.rb
app/controllers/discourse_fcm_notifications/admin/base_controller.rb
app/controllers/discourse_fcm_notifications/admin/status_controller.rb
```

### Modified Files:

```
plugin.rb
lib/discourse_fcm_notifications/engine.rb
lib/discourse_fcm_notifications/pusher.rb
app/controllers/discourse_fcm_notifications/push_controller.rb
config/routes.rb
```

---

## Deployment Instructions

### 1. Run Migrations

```bash
cd /path/to/discourse
RAILS_ENV=production bin/rake db:migrate
```

### 2. Restart Discourse

```bash
# If using Docker
./launcher restart app

# If running standalone
bundle exec rails s
```

### 3. Verify Installation

Check the admin endpoint to verify the plugin is working:

```bash
curl -H "Api-Key: YOUR_API_KEY" -H "Api-Username: admin" \
  https://your-discourse.com/fcm_notifications/admin
```

---

## Admin API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/fcm_notifications/admin` | Dashboard stats (token counts, recent failures, last error) |
| GET | `/fcm_notifications/admin/logs?page=0` | View notification logs (paginated, 50 per page) |
| GET | `/fcm_notifications/admin/user/:username` | View all tokens for a specific user |
| POST | `/fcm_notifications/admin/test/:username` | Send test push notification to user |
| DELETE | `/fcm_notifications/admin/token/:id` | Delete a specific token |
| POST | `/fcm_notifications/admin/cleanup` | Manually trigger stale token cleanup |

### Example API Responses

**Dashboard (`GET /fcm_notifications/admin`):**
```json
{
  "total_tokens": 150,
  "active_tokens": 142,
  "users_with_tokens": 98,
  "tokens_by_platform": {
    "ios": 75,
    "android": 60,
    "web": 7,
    "null": 8
  },
  "recent_failures": 3,
  "total_logs_24h": 245,
  "last_error": {
    "message": "FCM 401 Unauthorized - check server credentials!",
    "timestamp": "2026-01-24T15:30:00Z"
  },
  "last_log": {
    "level": "info",
    "message": "Sent to 2/2 devices for username",
    "timestamp": "2026-01-24T16:00:00Z"
  }
}
```

**User Tokens (`GET /fcm_notifications/admin/user/Renegade`):**
```json
{
  "user": "Renegade",
  "user_id": 123,
  "tokens": [
    {
      "id": 45,
      "token_preview": "dK8x7NpZQm2...",
      "platform": "ios",
      "device_name": "iPhone 15 Pro",
      "last_used_at": "2026-01-24T10:00:00Z",
      "last_success_at": "2026-01-24T10:00:00Z",
      "last_failure_at": null,
      "failure_count": 0,
      "last_error": null,
      "active": true,
      "created_at": "2026-01-20T08:00:00Z"
    }
  ]
}
```

---

## User API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/fcm_notifications/automatic_subscribe` | Register a token (with platform/device_name) |
| POST | `/fcm_notifications/subscribe` | Legacy endpoint (redirects to automatic_subscribe) |
| POST | `/fcm_notifications/unsubscribe` | Unregister token(s) |
| GET | `/fcm_notifications/status` | Get current user's token status |

### Registration Request

```json
POST /fcm_notifications/automatic_subscribe
{
  "token": "FCM_DEVICE_TOKEN_HERE",
  "platform": "ios",
  "device_name": "iPhone 15 Pro"
}
```

### Registration Response

```json
{
  "success": "SUCCESS",
  "token_status": "verified",
  "token_id": 45
}
```

---

## Rails Console Commands for Testing/Debugging

```ruby
# Check tokens for a user
user = User.find_by(username: 'Renegade')
DiscourseFcmNotifications::FcmToken.for_user(user.id)

# View recent logs
DiscourseFcmNotifications::FcmNotificationLog.recent

# View failed notifications in last 24 hours
DiscourseFcmNotifications::FcmNotificationLog.failed.since(24.hours.ago)

# View logs for a specific user
DiscourseFcmNotifications::FcmNotificationLog.for_user(user.id).recent

# Manually test push to user
DiscourseFcmNotifications::Pusher.push(user, {
  notification_type: 1,
  topic_title: "Test Topic",
  username: "admin",
  excerpt: "This is a test notification",
  post_url: "t/test/123"
})

# Check last error
PluginStore.get('discourse-fcm-notifications', 'last_error')

# Check last log
PluginStore.get('discourse-fcm-notifications', 'last_log')

# Get dashboard stats
{
  total_tokens: DiscourseFcmNotifications::FcmToken.count,
  active_tokens: DiscourseFcmNotifications::FcmToken.active.count,
  by_platform: DiscourseFcmNotifications::FcmToken.group(:platform).count,
  recent_failures: DiscourseFcmNotifications::FcmNotificationLog.failed.since(24.hours.ago).count
}

# Manually cleanup stale tokens
DiscourseFcmNotifications::FcmToken.cleanup_stale_tokens
DiscourseFcmNotifications::FcmNotificationLog.cleanup_old_logs

# Delete all tokens for a user (for testing)
DiscourseFcmNotifications::FcmToken.where(user_id: user.id).destroy_all
```

---

## Key Features Implemented

### Multi-Device Token Storage
- Up to 10 tokens per user (oldest tokens pruned automatically)
- Platform tracking (ios, android, web)
- Device name tracking (optional)
- Tokens stored in dedicated `fcm_tokens` table instead of custom_fields

### Comprehensive Logging
- Every notification attempt logged to `fcm_notification_logs` table
- Logs include: status, response code, error message, payload summary
- 7-day retention (auto-cleaned by scheduled job)
- Logs viewable via admin API

### Automatic Token Cleanup
- Tokens with 3+ consecutive failures are auto-deleted
- Tokens unused for 90+ days are cleaned up daily
- HTTP 404/410 responses trigger immediate token deletion
- Daily scheduled job (`FcmCleanupStaleTokens`) handles cleanup

### Error Handling by HTTP Status Code

| Status | Action |
|--------|--------|
| 200 | Mark success, reset failure count |
| 400 | Mark failure, log error |
| 401 | Log error (server config issue) |
| 403 | Log error (permission issue) |
| 404/410 | Delete token immediately (invalid/expired) |
| 429 | Log warning (rate limited) |
| Other | Mark failure, log error |

---

## Testing Checklist

- [ ] Token registration creates FcmToken record
- [ ] Multiple devices for same user get separate tokens
- [ ] Notifications sent to all active tokens
- [ ] Failed tokens get marked and eventually deleted
- [ ] Admin can view all tokens and logs via API
- [ ] Admin can test push to specific user
- [ ] Admin can delete individual tokens
- [ ] Stale token cleanup job works
- [ ] Migration from custom_fields preserves existing tokens
- [ ] iOS notifications work
- [ ] Android notifications work

---

## Troubleshooting

### Notifications not being sent

1. Check if plugin is enabled:
```ruby
SiteSetting.fcm_notifications_enabled?
```

2. Check if user has active tokens:
```ruby
DiscourseFcmNotifications::FcmToken.active.for_user(user.id).count
```

3. Check recent logs for errors:
```ruby
DiscourseFcmNotifications::FcmNotificationLog.for_user(user.id).recent
```

4. Check last error:
```ruby
PluginStore.get('discourse-fcm-notifications', 'last_error')
```

### iOS notifications not working

1. Verify APNs configuration in Firebase Console
2. Check for 401/403 errors in logs (credential issues)
3. Ensure `apns-priority: 10` is set (already configured)
4. Check that `interruption-level: active` is set (already configured)

### Token being deleted unexpectedly

Tokens are deleted when:
- HTTP 404 or 410 response from FCM (token invalid/expired)
- 3 consecutive failures
- 90+ days since last use
- User explicitly unsubscribes

Check the `last_error` field on the token to see why it failed.

---

## Phase 8: Flutter App Updates (Pending)

The Flutter app should be updated to send platform info when registering tokens:

```dart
// In fcm_provider.dart - _sendTokenToServerIfNeeded()
await _apiClient.post(
  '/fcm_notifications/automatic_subscribe',
  data: {
    'token': state.token,
    'platform': Platform.isIOS ? 'ios' : 'android',
    'device_name': await _getDeviceName(), // Optional
  },
);
```

This allows the server to track which platform each token belongs to for debugging.
