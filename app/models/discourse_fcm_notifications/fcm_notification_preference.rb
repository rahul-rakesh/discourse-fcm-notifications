# frozen_string_literal: true

module DiscourseFcmNotifications
  class FcmNotificationPreference < ActiveRecord::Base
    self.table_name = "fcm_notification_preferences"

    belongs_to :user

    validates :user_id, presence: true, uniqueness: true

    # Maps user-facing category keys to Discourse notification type IDs
    CATEGORIES = {
      "replies" => [2],
      "mentions" => [1, 15],
      "quotes" => [3],
      "likes" => [5, 25],
      "private_messages" => [6, 7],
      "chat" => [29, 30, 31, 32, 33],
      "following" => [800, 801, 802],
      "watching" => [9, 17, 36],
      "badges" => [12],
      "bookmarks" => [18, 24],
      "linked" => [11, 39],
    }.freeze

    CATEGORY_KEYS = CATEGORIES.keys.freeze

    def self.for_user(user_id)
      find_or_initialize_by(user_id: user_id)
    end

    def muted_categories_list
      return [] if muted_categories.blank?
      JSON.parse(muted_categories).select { |c| CATEGORY_KEYS.include?(c) }
    rescue JSON::ParserError
      []
    end

    def muted_categories_list=(list)
      self.muted_categories = (list & CATEGORY_KEYS).to_json
    end

    def muted?(notification_type_id)
      type_id = notification_type_id.to_i
      muted_categories_list.any? do |category_key|
        CATEGORIES[category_key]&.include?(type_id)
      end
    end

    # Returns hash of category => enabled (true/false)
    def categories_hash
      muted = muted_categories_list
      CATEGORY_KEYS.each_with_object({}) do |key, hash|
        hash[key] = !muted.include?(key)
      end
    end
  end
end
