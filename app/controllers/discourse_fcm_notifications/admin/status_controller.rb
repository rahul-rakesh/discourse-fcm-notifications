# frozen_string_literal: true

module DiscourseFcmNotifications
  module Admin
    class StatusController < BaseController
      def index
        render json: {
                 total_tokens: FcmToken.count,
                 active_tokens: FcmToken.active.count,
                 users_with_tokens: FcmToken.select(:user_id).distinct.count,
                 tokens_by_platform: FcmToken.group(:platform).count,
                 recent_failures: FcmNotificationLog.failed.since(24.hours.ago).count,
                 total_logs_24h: FcmNotificationLog.since(24.hours.ago).count,
                 last_error: PluginStore.get(PLUGIN_NAME, "last_error"),
                 last_log: PluginStore.get(PLUGIN_NAME, "last_log"),
               }
      end

      def logs
        page = params[:page].to_i
        per_page = 50

        logs =
          FcmNotificationLog
            .includes(:user)
            .order(created_at: :desc)
            .offset(page * per_page)
            .limit(per_page)

        render json: {
                 logs:
                   logs.map do |log|
                     {
                       id: log.id,
                       user: log.user&.username,
                       user_id: log.user_id,
                       notification_type: log.notification_type,
                       status: log.status,
                       response_code: log.response_code,
                       error_message: log.error_message,
                       payload_summary: log.payload_summary,
                       created_at: log.created_at,
                       sent_at: log.sent_at,
                     }
                   end,
                 total: FcmNotificationLog.count,
                 page: page,
                 per_page: per_page,
               }
      end

      def user_tokens
        user = User.find_by(username: params[:username])
        return render json: { error: "User not found" }, status: :not_found unless user

        tokens = FcmToken.for_user(user.id)

        render json: {
                 user: user.username,
                 user_id: user.id,
                 tokens:
                   tokens.map do |t|
                     {
                       id: t.id,
                       token_preview: "#{t.token[0..20]}...",
                       platform: t.platform,
                       device_name: t.device_name,
                       last_used_at: t.last_used_at,
                       last_success_at: t.last_success_at,
                       last_failure_at: t.last_failure_at,
                       failure_count: t.failure_count,
                       last_error: t.last_error,
                       active: t.active?,
                       created_at: t.created_at,
                     }
                   end,
               }
      end

      def test_push
        user = User.find_by(username: params[:username])
        return render json: { error: "User not found" }, status: :not_found unless user

        tokens = FcmToken.active.for_user(user.id)
        if tokens.empty?
          return render json: { error: "User has no active tokens" }, status: :unprocessable_entity
        end

        results =
          tokens.map do |fcm_token|
            success = Pusher.confirm_subscribe(user, fcm_token)
            { token_id: fcm_token.id, platform: fcm_token.platform, success: success }
          end

        render json: { user: user.username, results: results }
      end

      def delete_token
        token = FcmToken.find_by(id: params[:id])
        return render json: { error: "Token not found" }, status: :not_found unless token

        token.destroy
        render json: success_json
      end

      def cleanup_stale
        deleted_tokens = FcmToken.cleanup_stale_tokens
        deleted_logs = FcmNotificationLog.cleanup_old_logs

        render json: { deleted_tokens: deleted_tokens, deleted_logs: deleted_logs }
      end
    end
  end
end
