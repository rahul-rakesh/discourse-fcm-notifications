# frozen_string_literal: true

module DiscourseFcmNotifications
  class FcmToken < ActiveRecord::Base
    self.table_name = "fcm_tokens"

    MAX_TOKENS_PER_USER = 10
    MAX_FAILURE_COUNT = 3
    STALE_TOKEN_DAYS = 90
    VALID_PLATFORMS = %w[ios android web].freeze

    belongs_to :user

    validates :user_id, presence: true
    validates :token, presence: true, uniqueness: true
    validates :platform, inclusion: { in: VALID_PLATFORMS, allow_nil: true }

    scope :active, -> { where("failure_count < ?", MAX_FAILURE_COUNT) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :by_platform, ->(platform) { where(platform: platform) }
    scope :stale, -> { where("last_used_at < ?", STALE_TOKEN_DAYS.days.ago) }

    def self.register(user:, token:, platform: nil, device_name: nil)
      existing = find_by(token: token)
      existing.destroy if existing && existing.user_id != user.id

      record = find_or_initialize_by(token: token)
      record.user_id = user.id
      record.platform = platform if platform.present?
      record.device_name = device_name if device_name.present?
      record.last_used_at = Time.current
      record.failure_count = 0 if record.failure_count >= MAX_FAILURE_COUNT
      record.save!

      prune_old_tokens(user.id)

      record
    end

    def self.unregister(user:, token: nil)
      if token.present?
        where(user_id: user.id, token: token).destroy_all
      else
        where(user_id: user.id).destroy_all
      end
    end

    def self.prune_old_tokens(user_id)
      tokens = where(user_id: user_id).order(last_used_at: :desc)
      tokens.offset(MAX_TOKENS_PER_USER).destroy_all if tokens.count > MAX_TOKENS_PER_USER
    end

    def self.cleanup_stale_tokens
      stale.delete_all + where("failure_count >= ?", MAX_FAILURE_COUNT).delete_all
    end

    def mark_success!
      update!(
        last_success_at: Time.current,
        last_used_at: Time.current,
        failure_count: 0,
        last_error: nil,
      )
    end

    def mark_failure!(error_message)
      new_count = failure_count + 1
      update!(
        last_failure_at: Time.current,
        failure_count: new_count,
        last_error: error_message.to_s.truncate(500),
      )

      destroy if new_count >= MAX_FAILURE_COUNT
    end

    def stale?
      return true if failure_count >= MAX_FAILURE_COUNT
      return true if last_used_at && last_used_at < STALE_TOKEN_DAYS.days.ago
      false
    end

    def active?
      failure_count < MAX_FAILURE_COUNT
    end
  end
end
