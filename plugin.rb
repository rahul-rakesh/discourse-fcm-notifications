# frozen_string_literal: true

# name: discourse-fcm-notifications
# about: Plugin for integrating Firebase Cloud Messaging notifications with multi-device support
# version: 0.3.0
# authors: Judith Meyer, Jeff Wong, Renegade
# url: https://github.com/sprachprofi/discourse-fcm-notifications

enabled_site_setting :fcm_notifications_enabled

gem "signet", "0.17.0"
gem "os", "1.1.4"
gem "memoist", "0.16.2"
gem "googleauth", "1.7.0"
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
