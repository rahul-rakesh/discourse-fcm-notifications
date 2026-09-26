# frozen_string_literal: true

RSpec.describe DiscourseFcmNotifications::FcmNotificationPreference do
  fab!(:user)

  let(:plugin_instance) { Plugin::Instance.new }
  let(:custom_type) { Notification.types[:custom] }
  let(:offered) { { "spec_plugin" => [custom_type] } }
  let(:categories_modifier) do
    categories_offered = offered
    Proc.new { |categories| categories.merge(categories_offered) }
  end

  before do
    plugin_instance.register_modifier(:fcm_notifications_plugin_categories, &categories_modifier)
  end

  after do
    DiscoursePluginRegistry.unregister_modifier(
      plugin_instance,
      :fcm_notifications_plugin_categories,
      &categories_modifier
    )
  end

  def preference_muting(*keys)
    described_class
      .for_user(user.id)
      .tap do |preference|
        preference.muted_categories_list = keys
        preference.save!
      end
  end

  it "offers a plugin's category beside core's, on by default" do
    hash = described_class.for_user(user.id).categories_hash

    expect(hash.keys).to include(*described_class::CATEGORY_KEYS, "spec_plugin")
    expect(hash["spec_plugin"]).to eq(true)
    expect(described_class.plugin_type_ids).to include(custom_type)
  end

  it "mutes every type in a plugin's category, and nothing else" do
    preference = preference_muting("spec_plugin")

    expect(preference.muted?(custom_type)).to eq(true)
    expect(preference.muted?(Notification.types[:private_message])).to eq(false)
    expect(preference.categories_hash["spec_plugin"]).to eq(false)
  end

  describe "what a plugin category may not take" do
    let(:offered) do
      {
        "replies" => [custom_type],
        "spec_plugin" => [
          custom_type,
          Notification.types[:private_message],
          Notification.types[:posted],
        ],
        "spec_empty" => [Notification.types[:replied]],
      }
    end

    it "never lets a plugin take a core key, or a type core pushes" do
      expect(described_class.categories["replies"]).to eq([Notification.types[:replied]])
      expect(described_class.categories["spec_plugin"]).to eq([custom_type])
      expect(described_class.categories).not_to have_key("spec_empty")
      expect(described_class.plugin_type_ids).not_to include(
        Notification.types[:private_message],
        Notification.types[:posted],
        Notification.types[:replied],
      )
    end
  end

  it "drops a muted key no category holds" do
    preference = described_class.for_user(user.id)
    preference.update!(muted_categories: %w[spec_plugin gone_away likes].to_json)

    expect(preference.muted_categories_list).to contain_exactly("spec_plugin", "likes")

    preference.muted_categories_list = %w[gone_away likes]
    expect(JSON.parse(preference.muted_categories)).to eq(["likes"])
  end

  it "mutes a push filed under a plugin's category when that category is muted" do
    preference = preference_muting("spec_plugin")
    private_message = Notification.types[:private_message]

    expect(preference.muted?(private_message)).to eq(false)
    expect(preference.muted?(private_message, category: "spec_plugin")).to eq(true)
  end

  # An installed app that cannot show the plugin's category must not lose the mute it has.
  it "keeps a push filed under a plugin's category muted by its type's own category" do
    private_message = Notification.types[:private_message]

    preference = preference_muting("private_messages")
    expect(preference.muted?(private_message, category: "spec_plugin")).to eq(true)

    preference = preference_muting("likes")
    expect(preference.muted?(private_message, category: "spec_plugin")).to eq(false)
  end

  it "ignores a category nothing offers and falls back to the type" do
    preference = preference_muting("private_messages")
    private_message = Notification.types[:private_message]

    expect(preference.muted?(private_message, category: "gone_away")).to eq(true)
  end
end
