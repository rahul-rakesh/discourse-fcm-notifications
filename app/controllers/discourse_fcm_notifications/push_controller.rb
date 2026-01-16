# FILE: app/controllers/discourse_fcm_notifications/push_controller.rb

module ::DiscourseFcmNotifications
  class PushController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    layout false
    before_action :ensure_logged_in
    skip_before_action :preload_json

    def automatic_subscribe
      params.require(:token)

      if params[:token] == "REMOVE"
        DiscourseFcmNotifications::Pusher.unsubscribe(current_user)
        render json: success_json
      else
        # Update the user's token
        DiscourseFcmNotifications::Pusher.subscribe(current_user, params[:token])

        # Send a silent confirmation push to verify the link
        if DiscourseFcmNotifications::Pusher.confirm_subscribe(current_user)
          render json: { success: 'SUCCESS', token_status: 'verified' }
        else
          render json: { failed: 'FAILED', error: "Token accepted but verification push failed." }
        end
      end
    end

    def subscribe
      if current_user.custom_fields[DiscourseFcmNotifications::PLUGIN_NAME] != params[:subscription]
        DiscourseFcmNotifications::Pusher.subscribe(current_user, params[:subscription])
        if DiscourseFcmNotifications::Pusher.confirm_subscribe(current_user)
          render json: success_json
        else
          render json: { failed: 'FAILED', error: I18n.t("discourse_fcm_notifications.subscribe_error") }
        end
      else
        render json: { failed: 'FAILED', error: I18n.t("discourse_fcm_notifications.the_same") }
      end
    end

    def unsubscribe
      DiscourseFcmNotifications::Pusher.unsubscribe(current_user)
      render json: success_json
    end

  end
end
