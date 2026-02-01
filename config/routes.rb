# frozen_string_literal: true

DiscourseFcmNotifications::Engine.routes.draw do
  # User endpoints
  post "/automatic_subscribe" => "push#automatic_subscribe"
  post "/subscribe" => "push#subscribe"
  post "/unsubscribe" => "push#unsubscribe"
  get "/status" => "push#status"
  get "/preferences" => "push#preferences"
  put "/preferences" => "push#update_preferences"

  # Admin endpoints
  scope "/admin", defaults: { format: :json } do
    get "/" => "admin/status#index"
    get "/logs" => "admin/status#logs"
    get "/user/:username" => "admin/status#user_tokens"
    post "/test/:username" => "admin/status#test_push"
    delete "/token/:id" => "admin/status#delete_token"
    post "/cleanup" => "admin/status#cleanup_stale"
  end
end

Discourse::Application.routes.draw do
  mount ::DiscourseFcmNotifications::Engine, at: "/fcm_notifications"
end
