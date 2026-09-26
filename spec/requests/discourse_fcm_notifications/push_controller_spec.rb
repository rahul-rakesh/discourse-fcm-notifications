# frozen_string_literal: true

RSpec.describe DiscourseFcmNotifications::PushController do
  fab!(:user)

  let(:plugin_instance) { Plugin::Instance.new }
  let(:categories_modifier) do
    type_id = Notification.types[:custom]
    Proc.new { |categories| categories.merge("spec_plugin" => [type_id]) }
  end

  before do
    SiteSetting.fcm_notifications_enabled = true
    plugin_instance.register_modifier(:fcm_notifications_plugin_categories, &categories_modifier)
    sign_in(user)
  end

  after do
    DiscoursePluginRegistry.unregister_modifier(
      plugin_instance,
      :fcm_notifications_plugin_categories,
      &categories_modifier
    )
  end

  describe "#preferences" do
    it "lists a plugin's category, on" do
      get "/fcm_notifications/preferences.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["categories"]).to include(
        "spec_plugin" => true,
        "replies" => true,
      )
    end
  end

  describe "#update_preferences" do
    it "stores a plugin category's mute and answers it off" do
      put "/fcm_notifications/preferences.json", params: { muted_categories: %w[spec_plugin likes] }

      expect(response.status).to eq(200)
      expect(response.parsed_body["categories"]).to include(
        "spec_plugin" => false,
        "likes" => false,
        "replies" => true,
      )
      preference = DiscourseFcmNotifications::FcmNotificationPreference.for_user(user.id)
      expect(preference.muted_categories_list).to contain_exactly("spec_plugin", "likes")
    end
  end
end
