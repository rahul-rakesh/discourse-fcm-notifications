# discourse-fcm-notifications
Plugin for having Discourse deliver push notifications to your custom iOS/Android app through Firebase.

This assumes you have a custom app that includes access to your Discourse forum. It won't work without such an app. If you don't have an app, I've designed a [basic app](https://payhip.com/b/3Dplj) that will let users browse your Discourse forum and receive push notifications, but submitting an app to the App Store and Google Play Store is not super simple. Alternatively, you can use the Discourse Pushover Notifications plugin instead, but then it's two clicks for users to go from a notification to your forum.

# Installation

See [the plugin install readme](https://meta.discourse.org/t/install-plugins-in-discourse/19157).

Create a Google Firebase project for your app. Add the Firebase project ID, token and the json (with OAuth data) to the plugin settings in your Discourse installation.

Your app can activate push notifications for the active user by sending the device token to YOUR_FORUM.com/fcm_notifications/automatic_subscribe?token=... . Be sure to call this every time the device token changes. To deactivate push notifications for the active user, call YOUR_FORUM.com/fcm_notifications/automatic_subscribe?token=REMOVE . 

Alternatively, you can have users copy-paste their device tokens in their preference -> Notifications. 

# Receiving push notifications in your app

The push notifications that this app creates will include:

````
'data': {
  "linked_obj_type" => 'link',
  "linked_obj_data" => <url to the post/message referenced in the message>,
  "notification_type" => <the Discourse notification type id, e.g. "6" for a private message>,
  "topic_id" => <the topic's id>,
  "post_number" => <the post's number in the topic>,
},
'notification': {
  title: <something like "USERNAME sent you a private message in TOPIC">,
  body: <beginning of the message>,
}
````

Every data value is a string, as FCM requires. `notification_type`, `topic_id` and `post_number` are sent only when the notification has them; the confirmation push sent on subscribing has none of the three. `linked_obj_data` is the site address followed by the post's path, with one slash between them.

An app that reads only `linked_obj_data` can keep opening it in an in-app browser. An app that reads `notification_type` can route the tap itself: a private message (6) to the conversation, a reply to the post, and so on.

A plugin may add its own keys to the data through the payload's `push_data` hash. They never replace `linked_obj_type`, `linked_obj_data` or the three routing keys, and empty values are left out.

# Pushes for a plugin's own notifications

Core pushes only the notifications it alerts on itself (replies, mentions, private messages and the like). A plugin that writes its own notification rows with `Notification.create!` gets no push from core. This plugin pushes such a row when, and only when, a plugin has put the row's type in a push category, so the member can always turn it off.

How it works:

1. Core announces every new row (`:notification_created`). If the row's type is in a plugin category, a job is queued **60 seconds** later (`Pusher::ROW_PUSH_DELAY`).
2. The job re-reads the row. A row deleted in the meantime (withdrawn) or already read on the site is not pushed. Nor is a row whose member is suspended, in do-not-disturb, or has no active app token.
3. The job asks the plugins for the push's words. A row no plugin gives words for is not pushed.
4. The push goes through the same mute check, log and send as every other push, with the row's own `notification_type`, `topic_id` and `post_number`.

A push already delivered cannot be taken back: a row withdrawn after its push stays on the phone until the member dismisses it.

## The modifiers a plugin registers

All three are core modifiers (`register_modifier` in the plugin's `plugin.rb`). A modifier runs only while its plugin is enabled.

**`fcm_notifications_plugin_categories`** `(categories) -> categories`: add `{ "key" => [type_id, ...] }` for each category the plugin offers. A plugin category never takes a key of the list below, never holds a type of that list or a type core pushes itself (`PostAlerter::NOTIFIABLE_TYPES`), and is dropped when empty. This plugin cannot see every type other code pushes through core's path, so a plugin must not offer one that is already pushed.

```ruby
register_modifier(:fcm_notifications_plugin_categories) do |categories|
  categories.merge("market" => [920, 921, 922])
end
```

**`fcm_notifications_row_payload`** `(payload, notification) -> payload or nil`: return `payload` when it is already set (another plugin answered), otherwise a hash for a row of yours, or nil for no push:

| Key | |
|---|---|
| `excerpt` | the body (required) |
| `translated_title` | the title; otherwise the usual title from `topic_title` and `username` |
| `topic_title` | |
| `post_url` | a path starting with `/`, linked as `linked_obj_data` |
| `push_data` | extra data keys, such as `url` and `item_id`; values sent as strings |
| `tag` | a collapse tag (64 bytes at most): a newer push with the same tag replaces the older one in the phone's tray (`android.notification.tag`, `apns-collapse-id`) |

Symbol or string keys both work. `notification_type`, `topic_id` and `post_number` are always taken from the row.

**`fcm_notifications_push_category`** `(category, payload, user) -> category key or nil`: file a push core sends under one of your categories, so the member's switch for that category stops it too (a plugin's automatic private messages, for one). It adds a mute and never lifts one: the push is still stopped by the switch for its type, so a member who turned that off, perhaps on an app build that cannot show your category, keeps it off. Return `category` when it is already set.

# Notification Preferences (Per-Category Muting)

Users can mute specific notification categories to stop receiving push notifications for those types. Muted notifications are filtered server-side before sending to FCM.

## API Endpoints

A plugin category (above) is listed beside these, on until the member turns it off, and stored in the same list of muted keys.

**GET** `/fcm_notifications/preferences` — Returns current preference state:
```json
{
  "categories": {
    "replies": true,
    "mentions": true,
    "quotes": true,
    "likes": false,
    "private_messages": true,
    "chat": false,
    "following": true,
    "watching": true,
    "badges": true,
    "bookmarks": true,
    "linked": true
  }
}
```

**PUT** `/fcm_notifications/preferences` — Update muted categories:
```json
{
  "muted_categories": ["likes", "chat"]
}
```

## Available Categories

| Category Key | Discourse Notification Type IDs |
|---|---|
| replies | 2 |
| mentions | 1, 15 |
| quotes | 3 |
| likes | 5, 25 |
| private_messages | 6, 7 |
| chat | 29, 30, 31, 32, 33 |
| following | 800, 801, 802 |
| watching | 9, 17, 36 |
| badges | 12 |
| bookmarks | 18, 24 |
| linked | 11, 39 |

