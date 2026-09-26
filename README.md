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

# Notification Preferences (Per-Category Muting)

Users can mute specific notification categories to stop receiving push notifications for those types. Muted notifications are filtered server-side before sending to FCM.

## API Endpoints

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

