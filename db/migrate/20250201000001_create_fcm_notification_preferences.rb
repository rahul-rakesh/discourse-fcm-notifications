# frozen_string_literal: true

class CreateFcmNotificationPreferences < ActiveRecord::Migration[7.0]
  def change
    create_table :fcm_notification_preferences do |t|
      t.bigint :user_id, null: false
      t.text :muted_categories # JSON array of category keys
      t.timestamps
    end

    add_index :fcm_notification_preferences, :user_id, unique: true
  end
end
