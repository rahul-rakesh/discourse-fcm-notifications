# frozen_string_literal: true

module DiscourseFcmNotifications
  class PushController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    layout false
    before_action :ensure_logged_in
    skip_before_action :preload_json

    def automatic_subscribe
      params.require(:token)

      token = params[:token]
      platform = params[:platform]
      device_name = params[:device_name]

      if token == "REMOVE"
        Pusher.unsubscribe(user: current_user)
        render json: success_json
        return
      end

      fcm_token =
        Pusher.subscribe(
          user: current_user,
          token: token,
          platform: platform,
          device_name: device_name,
        )

      unless fcm_token
        render json: {
                 failed: "FAILED",
                 error: "Failed to register token",
               },
               status: :unprocessable_entity
        return
      end

      if Pusher.confirm_subscribe(current_user, fcm_token)
        render json: { success: "SUCCESS", token_status: "verified", token_id: fcm_token.id }
      else
        render json: {
                 success: "SUCCESS",
                 token_status: "unverified",
                 token_id: fcm_token.id,
                 warning: "Token saved but confirmation push may have failed",
               }
      end
    end

    def subscribe
      params.require(:subscription)

      params[:token] = params[:subscription]
      automatic_subscribe
    end

    def unsubscribe
      token = params[:token]
      Pusher.unsubscribe(user: current_user, token: token)
      render json: success_json
    end

    def status
      tokens = FcmToken.for_user(current_user.id)

      render json: {
               token_count: tokens.count,
               tokens:
                 tokens.map do |t|
                   {
                     id: t.id,
                     platform: t.platform,
                     device_name: t.device_name,
                     last_used_at: t.last_used_at,
                     last_success_at: t.last_success_at,
                     failure_count: t.failure_count,
                     active: t.active?,
                   }
                 end,
             }
    end
  end
end
