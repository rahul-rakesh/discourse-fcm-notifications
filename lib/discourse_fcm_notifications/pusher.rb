# frozen_string_literal: true

require "net/https"

module DiscourseFcmNotifications
  class Pusher
    class << self
      def push(user, payload)
        return false unless user && payload

        tokens = FcmToken.active.for_user(user.id)

        if tokens.empty?
          log_info("No active FCM tokens for user #{user.username} (id: #{user.id})")
          return false
        end

        notification_type = Notification.types[payload[:notification_type]]
        message_content = build_message(payload)

        success_count = 0
        tokens.each do |fcm_token|
          result =
            send_to_token(
              user: user,
              fcm_token: fcm_token,
              message_content: message_content,
              notification_type: notification_type,
            )
          success_count += 1 if result
        end

        log_info(
          "Sent to #{success_count}/#{tokens.count} devices for #{user.username} (notification_type: #{notification_type})",
        )
        success_count > 0
      end

      def confirm_subscribe(user, fcm_token)
        message_content = {
          title: I18n.t("discourse_fcm_notifications.confirm_title", site_title: SiteSetting.title),
          message: I18n.t("discourse_fcm_notifications.confirm_body"),
          url: Discourse.base_url.to_s,
        }

        send_to_token(
          user: user,
          fcm_token: fcm_token,
          message_content: message_content,
          notification_type: "confirmation",
        )
      end

      def subscribe(user:, token:, platform: nil, device_name: nil)
        fcm_token =
          FcmToken.register(user: user, token: token, platform: platform, device_name: device_name)

        log_info(
          "Registered FCM token for #{user.username} (platform: #{platform || "unknown"}, token_id: #{fcm_token.id})",
        )
        fcm_token
      rescue StandardError => e
        log_error("Failed to register token for #{user.username}: #{e.message}")
        nil
      end

      def unsubscribe(user:, token: nil)
        count = FcmToken.unregister(user: user, token: token)
        log_info("Unregistered #{count || "all"} FCM token(s) for #{user.username}")
        true
      rescue StandardError => e
        log_error("Failed to unregister token for #{user.username}: #{e.message}")
        false
      end

      private

      def send_to_token(user:, fcm_token:, message_content:, notification_type:)
        log_entry =
          FcmNotificationLog.log_attempt(
            user: user,
            fcm_token: fcm_token,
            notification_type: notification_type,
            payload: message_content,
          )

        begin
          fcm_client = get_fcm_client
          message = build_fcm_message(fcm_token.token, message_content)

          log_info(
            "Sending FCM to #{user.username} (token_id: #{fcm_token.id}, platform: #{fcm_token.platform || "unknown"})",
          )

          response = fcm_client.send_v1(message)

          if response[:response] == "success"
            fcm_token.mark_success!
            log_entry.mark_sent!(response_code: 200)
            log_info(
              "Successfully sent to #{user.username} (token_id: #{fcm_token.id}, log_id: #{log_entry.id})",
            )
            true
          else
            handle_fcm_error(user, fcm_token, log_entry, response)
            false
          end
        rescue StandardError => e
          log_entry.mark_failed!(e.message)
          log_error(
            "Exception sending to #{user.username} (token_id: #{fcm_token.id}): #{e.class.name} - #{e.message}",
          )
          log_error("Backtrace: #{e.backtrace.first(5).join("\n")}") if e.backtrace
          false
        end
      end

      def handle_fcm_error(user, fcm_token, log_entry, response)
        status_code = response[:status_code]
        error_body = response[:body]

        log_entry.mark_sent!(response_code: status_code, response_body: error_body)

        case status_code
        when 400
          fcm_token.mark_failure!("Invalid request: #{error_body}")
          log_error(
            "FCM 400 Bad Request for #{user.username} (token_id: #{fcm_token.id}): #{error_body}",
          )
        when 401
          log_error("FCM 401 Unauthorized - check server credentials! Response: #{error_body}")
        when 403
          log_error(
            "FCM 403 Forbidden for #{user.username} (token_id: #{fcm_token.id}) - check project permissions: #{error_body}",
          )
        when 404, 410
          log_warn(
            "FCM token expired/invalid for #{user.username} (token_id: #{fcm_token.id}), removing. Status: #{status_code}",
          )
          fcm_token.destroy
        when 429
          log_warn("FCM rate limited (429) - will retry later")
        else
          fcm_token.mark_failure!("HTTP #{status_code}: #{error_body}")
          log_error(
            "FCM Error #{status_code} for #{user.username} (token_id: #{fcm_token.id}): #{error_body}",
          )
        end
      end

      def build_message(payload)
        notification_type = Notification.types[payload[:notification_type]]
        topic_title = payload[:topic_title].to_s
        username = payload[:username].to_s

        # Smart title: try specific translation, fallback to generic with topic title
        title =
          I18n.t(
            "discourse_fcm_notifications.popup.#{notification_type}",
            site_title: SiteSetting.title,
            topic: topic_title,
            username: username,
            default: nil,
          )

        # Fallback: use topic title directly (best UX for listings/classifieds)
        if title.nil?
          title =
            if topic_title.present?
              "#{username} in \"#{topic_title}\""
            else
              "New notification from #{username}"
            end
        end

        # Clean excerpt: strip image placeholders, use topic_title if empty/only images
        excerpt = payload[:excerpt].to_s
        clean_excerpt = excerpt.gsub(/\[IMG[^\]]*\]|\[image[^\]]*\]/i, "").strip
        clean_excerpt = topic_title if clean_excerpt.blank? || clean_excerpt =~ /^\[.*\]$/

        {
          title: title,
          message: clean_excerpt,
          url: "#{Discourse.base_url}/#{payload[:post_url]}",
        }
      end

      def build_fcm_message(token, message_content)
        {
          token: token,
          data: {
            "linked_obj_type" => "link",
            "linked_obj_data" => message_content[:url],
          },
          notification: {
            title: message_content[:title],
            body: message_content[:message],
          },
          android: {
            priority: "high",
          },
          apns: {
            headers: {
              "apns-priority": "10",
            },
            payload: {
              aps: {
                sound: "default",
                "interruption-level": "active",
              },
            },
          },
        }
      end

      def get_fcm_client
        filename = Rails.root.join("tmp", "gcp_key.json").to_s

        if !File.exist?(filename) && SiteSetting.fcm_notifications_google_json.present?
          File.write(filename, SiteSetting.fcm_notifications_google_json)
          log_info("Wrote GCP credentials to #{filename}")
        end

        unless File.exist?(filename)
          raise "Missing Google JSON for push notifications. Configure fcm_notifications_google_json in site settings."
        end

        FCM.new(
          SiteSetting.fcm_notifications_api_key,
          filename,
          SiteSetting.fcm_notifications_project_id,
        )
      end

      def log_info(message)
        Rails.logger.info("[FCM] #{message}")
        store_last_log("info", message)
      end

      def log_warn(message)
        Rails.logger.warn("[FCM] #{message}")
        store_last_log("warn", message)
      end

      def log_error(message)
        Rails.logger.error("[FCM] #{message}")
        store_last_log("error", message)
        PluginStore.set(
          PLUGIN_NAME,
          "last_error",
          { message: message, timestamp: Time.current.iso8601 },
        )
      end

      def store_last_log(level, message)
        PluginStore.set(
          PLUGIN_NAME,
          "last_log",
          { level: level, message: message, timestamp: Time.current.iso8601 },
        )
      end
    end
  end
end
