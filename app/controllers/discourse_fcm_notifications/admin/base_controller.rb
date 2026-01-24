# frozen_string_literal: true

module DiscourseFcmNotifications
  module Admin
    class BaseController < ::Admin::AdminController
      requires_plugin PLUGIN_NAME
    end
  end
end
