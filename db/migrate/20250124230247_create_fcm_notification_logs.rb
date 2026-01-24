# frozen_string_literal: true

class CreateFcmNotificationLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :fcm_notification_logs do |t|
      t.bigint :user_id, null: false
      t.bigint :fcm_token_id
      t.string :notification_type, limit: 50
      t.string :status, limit: 20, default: "pending", null: false
      t.text :payload_summary
      t.text :response_body
      t.integer :response_code
      t.string :error_message, limit: 500
      t.datetime :sent_at
      t.timestamps
    end

    add_index :fcm_notification_logs, :user_id
    add_index :fcm_notification_logs, :fcm_token_id
    add_index :fcm_notification_logs, :status
    add_index :fcm_notification_logs, :created_at
  end
end
