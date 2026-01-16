# FILE: lib/discourse_fcm_notifications/pusher.rb

# frozen_string_literal: true
require "net/https"

module ::DiscourseFcmNotifications
  class Pusher

    def self.push(user, payload)
      message = {
        title: I18n.t(
          "discourse_fcm_notifications.popup.#{Notification.types[payload[:notification_type]]}",
          site_title: SiteSetting.title,
          topic: payload[:topic_title],
          username: payload[:username]
        ),
        message: payload[:excerpt],
        url: "#{Discourse.base_url}/#{payload[:post_url]}"
      }
      self.send_notification(user, message)
    end

    def self.confirm_subscribe(user)
      message = {
        title: I18n.t(
          "discourse_fcm_notifications.confirm_title",
          site_title: SiteSetting.title,
          ),
        message: I18n.t("discourse_fcm_notifications.confirm_body"),
        url: "#{Discourse.base_url}"
      }
      self.send_notification(user, message)
    end

    def self.subscribe(user, subscription)
      user.custom_fields[DiscourseFcmNotifications::PLUGIN_NAME] = subscription
      user.save_custom_fields(true)
    end

    def self.unsubscribe(user)
      user.custom_fields.delete(DiscourseFcmNotifications::PLUGIN_NAME)
      user.save_custom_fields(true)
    end

    private

    def self.send_notification(user, message_hash)
      return unless user && message_hash

      token = user.custom_fields[DiscourseFcmNotifications::PLUGIN_NAME]
      return if token.blank?

      begin
        Rails.logger.info "Sending FCM notification to #{user.username}: #{message_hash[:title]}"

        # Use a temporary file path that is safer within Docker/Linux environments
        filename = Rails.root.join("tmp", "gcp_key.json").to_s

        if !File.exist?(filename) && SiteSetting.fcm_notifications_google_json.present?
          File.write(filename, SiteSetting.fcm_notifications_google_json)
        end

        raise "Error: Missing google json for push notifications" unless File.exist?(filename)

        fcm = FCM.new(SiteSetting.fcm_notifications_api_key, filename, SiteSetting.fcm_notifications_project_id)

        message = {
          'token': token,
          'data': {
            "linked_obj_type" => 'link',
            "linked_obj_data" => message_hash[:url],
          },
          'notification': {
            title: message_hash[:title],
            body: message_hash[:message],
          },
          'android': {
            "priority": "high", # Changed to high for instant delivery
          },
          'apns': {
            headers: { "apns-priority": "10" }, # Changed to 10 for instant delivery
            payload: {
              aps: {
                "sound": "default",
                "interruption-level": "active"
              }
            },
          }
        }

        response = fcm.send_v1(message)

        if response[:response] == 'success'
          return true
        else
          # If token is invalid, automatically unsubscribe to keep DB clean
          if response[:status_code] == 404 || response[:status_code] == 410
            Rails.logger.warn "FCM token expired for #{user.username}. Unsubscribing."
            self.unsubscribe(user)
          else
            Rails.logger.error "FCM Error (#{response[:status_code]}): #{response[:body]}"
          end
          return false
        end
      rescue => e
        Rails.logger.error "FCM Exception for #{user.username}: #{e.message}"
        return false
      end
    end
  end
end
