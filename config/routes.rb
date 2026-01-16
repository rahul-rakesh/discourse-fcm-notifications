# FILE: config/routes.rb

DiscourseFcmNotifications::Engine.routes.draw do
  # Changed from get to post for security
  post '/automatic_subscribe' => 'push#automatic_subscribe'
  post '/subscribe' => 'push#subscribe'
  post '/unsubscribe' => 'push#unsubscribe'
end

Discourse::Application.routes.draw do
  mount ::DiscourseFcmNotifications::Engine, at: '/fcm_notifications'
end
