# frozen_string_literal: true

# name: discourse-fcm-notifications
# about: Plugin for integrating Firebase Cloud Messaging notifications with multi-device support
# version: 0.3.0
# authors: Judith Meyer, Jeff Wong, Renegade
# url: https://github.com/sprachprofi/discourse-fcm-notifications

enabled_site_setting :fcm_notifications_enabled

gem "signet", "0.21.0"
gem "os", "1.1.4"
gem "memoist", "0.16.2"
gem "google-cloud-env", "2.3.1"
gem "google-logging-utils", "0.2.0"
gem "googleauth", "1.15.1"
gem "fcm", "1.0.8"

module ::DiscourseFcmNotifications
  PLUGIN_NAME = "discourse-fcm-notifications"

  def self.enabled?
    SiteSetting.fcm_notifications_enabled
  end
end

require_relative "lib/discourse_fcm_notifications/engine"

after_initialize do
  # Handle push notification events
  DiscourseEvent.on(:push_notification) do |user, payload|
    if SiteSetting.fcm_notifications_enabled?
      Jobs.enqueue(:send_fcm_notifications, user_id: user.id, payload: payload)
    end
  end

  # A plugin's own notification rows never pass core's push path. One reaches the phone only
  # when a plugin has put its type in a push category, so the member can always turn it off,
  # and a minute late, so a row withdrawn or read on the site by then is not pushed.
  on(:notification_created) do |notification|
    if DiscourseFcmNotifications::FcmNotificationPreference.plugin_type_ids.include?(
         notification.notification_type,
       )
      Jobs.enqueue_in(
        DiscourseFcmNotifications::Pusher::ROW_PUSH_DELAY,
        :send_fcm_notification_row,
        notification_id: notification.id,
      )
    end
  rescue StandardError => e
    # A push that cannot be queued never fails the act that wrote the row.
    Rails.logger.warn("[FCM] row push not queued for notification #{notification&.id}: #{e.class}")
  end

  # Job to send FCM notifications
  module ::Jobs
    class SendFcmNotifications < ::Jobs::Base
      def execute(args)
        return unless SiteSetting.fcm_notifications_enabled?

        user = User.find_by(id: args[:user_id])
        return unless user

        DiscourseFcmNotifications::Pusher.push(user, args[:payload])
      end
    end

    class SendFcmNotificationRow < ::Jobs::Base
      def execute(args)
        return unless SiteSetting.fcm_notifications_enabled?

        notification = Notification.find_by(id: args[:notification_id])
        return if notification.nil? || notification.read?

        DiscourseFcmNotifications::Pusher.push_row(notification)
      end
    end

    # Scheduled job for cleaning up stale tokens and old logs
    class FcmCleanupStaleTokens < ::Jobs::Scheduled
      every 1.day

      def execute(args)
        return unless SiteSetting.fcm_notifications_enabled?

        deleted_tokens = DiscourseFcmNotifications::FcmToken.cleanup_stale_tokens
        deleted_logs = DiscourseFcmNotifications::FcmNotificationLog.cleanup_old_logs

        if deleted_tokens > 0 || deleted_logs > 0
          Rails.logger.info(
            "[FCM] Cleanup: removed #{deleted_tokens} stale tokens and #{deleted_logs} old logs",
          )
        end
      end
    end
  end
end
