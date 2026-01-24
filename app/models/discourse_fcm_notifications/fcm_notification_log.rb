# frozen_string_literal: true

module DiscourseFcmNotifications
  class FcmNotificationLog < ActiveRecord::Base
    self.table_name = "fcm_notification_logs"

    RETENTION_DAYS = 7
    STATUSES = %w[pending sent failed].freeze

    belongs_to :user
    belongs_to :fcm_token, class_name: "DiscourseFcmNotifications::FcmToken", optional: true

    validates :user_id, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :recent, -> { order(created_at: :desc).limit(100) }
    scope :failed, -> { where(status: "failed") }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :since, ->(time) { where("created_at > ?", time) }

    def self.log_attempt(user:, fcm_token:, notification_type:, payload:)
      create!(
        user_id: user.id,
        fcm_token_id: fcm_token&.id,
        notification_type: notification_type.to_s,
        status: "pending",
        payload_summary: summarize_payload(payload),
      )
    end

    def mark_sent!(response_code:, response_body: nil)
      update!(
        status: response_code == 200 ? "sent" : "failed",
        response_code: response_code,
        response_body: response_body.to_s.truncate(1000),
        sent_at: Time.current,
      )
    end

    def mark_failed!(error_message)
      update!(
        status: "failed",
        error_message: error_message.to_s.truncate(500),
        sent_at: Time.current,
      )
    end

    def self.summarize_payload(payload)
      return nil unless payload.is_a?(Hash)

      {
        type: payload[:notification_type],
        topic: payload[:topic_title]&.truncate(50),
        username: payload[:username],
      }.to_json
    rescue StandardError
      nil
    end

    def self.cleanup_old_logs
      where("created_at < ?", RETENTION_DAYS.days.ago).delete_all
    end
  end
end
