# frozen_string_literal: true

class MigrateCustomFieldsToFcmTokens < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL
      INSERT INTO fcm_tokens (user_id, token, created_at, updated_at, last_used_at, failure_count)
      SELECT
        ucf.user_id,
        ucf.value,
        ucf.created_at,
        ucf.updated_at,
        ucf.updated_at,
        0
      FROM user_custom_fields ucf
      WHERE ucf.name = 'discourse-fcm-notifications'
        AND ucf.value IS NOT NULL
        AND ucf.value != ''
        AND LENGTH(ucf.value) > 10
      ON CONFLICT (token) DO NOTHING
    SQL
  end

  def down
  end
end
