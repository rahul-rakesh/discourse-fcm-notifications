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

    # Every category a member can turn off: the ones above, then any a plugin offers for its own
    # notification rows through the fcm_notifications_plugin_categories modifier.
    def self.categories
      CATEGORIES.merge(plugin_categories)
    end

    def self.category_keys
      categories.keys
    end

    # A plugin category never takes a key above, and never holds a type above or one core pushes
    # itself (PostAlerter::NOTIFIABLE_TYPES): those already reach the phone through core's push,
    # and pushing them as rows too would send them twice. This is what can be checked here; a
    # plugin must not offer a type that some other code pushes through core's path.
    def self.plugin_categories
      offered = DiscoursePluginRegistry.apply_modifier(:fcm_notifications_plugin_categories, {})
      return {} unless offered.respond_to?(:each_pair)

      taken = core_type_ids
      categories = {}
      offered.each_pair do |key, type_ids|
        key = key.to_s
        next if key.blank? || CATEGORIES.key?(key)

        ids = Array(type_ids).map(&:to_i).select(&:positive?).uniq - taken
        categories[key] = ids if ids.any?
      end
      categories
    end

    # The notification types that are pushed as rows: every type a plugin category holds.
    def self.plugin_type_ids
      plugin_categories.values.flatten.uniq
    end

    def self.core_type_ids
      CATEGORIES.values.flatten | PostAlerter::NOTIFIABLE_TYPES
    end

    def muted_categories_list(keys = self.class.category_keys)
      return [] if muted_categories.blank?
      JSON.parse(muted_categories).select { |c| keys.include?(c) }
    rescue JSON::ParserError
      []
    end

    def muted_categories_list=(list)
      self.muted_categories = (list & self.class.category_keys).to_json
    end

    # category: a category a plugin filed this push under (the fcm_notifications_push_category
    # modifier). It adds a mute and never lifts one, so a member who muted the type's own
    # category, perhaps on a build that cannot show the plugin's, still gets no such push.
    def muted?(notification_type_id, category: nil)
      categories = self.class.categories
      muted = muted_categories_list(categories.keys)
      return true if category.present? && muted.include?(category.to_s)

      type_id = notification_type_id.to_i
      muted.any? { |category_key| categories[category_key]&.include?(type_id) }
    end

    # Returns hash of category => enabled (true/false)
    def categories_hash
      keys = self.class.category_keys
      muted = muted_categories_list(keys)
      keys.each_with_object({}) { |key, hash| hash[key] = !muted.include?(key) }
    end
  end
end
