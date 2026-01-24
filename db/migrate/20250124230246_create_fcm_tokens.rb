# frozen_string_literal: true

class CreateFcmTokens < ActiveRecord::Migration[7.0]
  def change
    create_table :fcm_tokens do |t|
      t.bigint :user_id, null: false
      t.string :token, null: false, limit: 512
      t.string :platform, limit: 20
      t.string :device_name, limit: 100
      t.datetime :last_used_at
      t.datetime :last_success_at
      t.datetime :last_failure_at
      t.integer :failure_count, default: 0, null: false
      t.string :last_error, limit: 500
      t.timestamps
    end

    add_index :fcm_tokens, :user_id
    add_index :fcm_tokens, :token, unique: true
    add_index :fcm_tokens, %i[user_id platform]
  end
end
