# frozen_string_literal: true

# A plugin's own notification rows: core never pushes them, so this plugin does, for the types
# a plugin has put in a push category, with the words that plugin gives. The spec plays the
# plugin: its category holds core's `custom` type, which core never pushes itself.
RSpec.describe "Pushing a plugin's notification rows" do # rubocop:disable RSpec/DescribeClass
  fab!(:user)
  fab!(:topic) { Fabricate(:topic, title: "An RTX 3080 and a monitor stand") }

  let(:plugin_instance) { Plugin::Instance.new }
  let(:custom_type) { Notification.types[:custom] }
  # What the pretend plugin does, changed by an example rather than by re-registering.
  let(:plugin_state) { { offers_category: true, gives_words: true, words_asked_for: [] } }
  let(:categories_modifier) do
    state = plugin_state
    type_id = custom_type
    Proc.new do |categories|
      state[:offers_category] ? categories.merge("spec_plugin" => [type_id]) : categories
    end
  end
  let(:words_modifier) do
    state = plugin_state
    path = "/t/#{topic.slug}/#{topic.id}/1"
    Proc.new do |payload, notification|
      state[:words_asked_for] << notification.id
      next payload if payload || !state[:gives_words]

      {
        translated_title: "An RTX 3080 and a monitor stand",
        excerpt: "alice says they sold you RTX 3080, confirm or change the lines",
        topic_title: "An RTX 3080 and a monitor stand",
        post_url: path,
        push_data: {
          "url" => "/market/buying",
          "item_id" => 42,
        },
        tag: "spec-trade-7",
      }
    end
  end
  let(:sent) { [] }

  before do
    SiteSetting.fcm_notifications_enabled = true
    plugin_instance.register_modifier(:fcm_notifications_plugin_categories, &categories_modifier)
    plugin_instance.register_modifier(:fcm_notifications_row_payload, &words_modifier)

    messages = sent
    client =
      Class.new do
        define_method(:send_v1) do |message|
          messages << message
          { response: "success" }
        end
      end
    DiscourseFcmNotifications::Pusher.stubs(:get_fcm_client).returns(client.new)
  end

  after do
    DiscoursePluginRegistry.unregister_modifier(
      plugin_instance,
      :fcm_notifications_plugin_categories,
      &categories_modifier
    )
    DiscoursePluginRegistry.unregister_modifier(
      plugin_instance,
      :fcm_notifications_row_payload,
      &words_modifier
    )
  end

  def give_token(member = user)
    DiscourseFcmNotifications::FcmToken.create!(
      user: member,
      token: "device-token-#{member.id}",
      platform: "android",
    )
  end

  def row(type: custom_type, member: user)
    Notification.create!(
      notification_type: type,
      user_id: member.id,
      topic_id: topic.id,
      post_number: 1,
      data: { message: "spec" }.to_json,
    )
  end

  def run_job(notification)
    Jobs::SendFcmNotificationRow.new.execute(notification_id: notification.id)
  end

  it "queues a push a minute after a row whose type a plugin's category holds, and none for any other" do
    created = row

    expect_job_enqueued(job: :send_fcm_notification_row, args: { notification_id: created.id })
    expect(Jobs::SendFcmNotificationRow.jobs.last["at"]).to be_within(5).of(
      DiscourseFcmNotifications::Pusher::ROW_PUSH_DELAY.from_now.to_f,
    )

    expect_not_enqueued_with(job: :send_fcm_notification_row) do
      row(type: Notification.types[:liked])
    end
  end

  it "queues nothing while app notifications are off" do
    SiteSetting.fcm_notifications_enabled = false

    expect_not_enqueued_with(job: :send_fcm_notification_row) { row }
  end

  it "writes the row even when the push cannot be queued" do
    DiscourseFcmNotifications::FcmNotificationPreference.stubs(:plugin_type_ids).raises(
      StandardError,
      "down",
    )

    expect { row }.to change { Notification.where(user_id: user.id).count }.by(1)
  end

  it "pushes the row with the plugin's words and the row's own type, topic and post" do
    give_token

    run_job(row)

    message = sent.last
    expect(message[:notification]).to eq(
      title: "An RTX 3080 and a monitor stand",
      body: "alice says they sold you RTX 3080, confirm or change the lines",
    )
    expect(message[:data]).to eq(
      "linked_obj_type" => "link",
      "linked_obj_data" => "#{Discourse.base_url}/t/#{topic.slug}/#{topic.id}/1",
      "notification_type" => custom_type.to_s,
      "topic_id" => topic.id.to_s,
      "post_number" => "1",
      "url" => "/market/buying",
      "item_id" => "42",
    )
  end

  it "tags the push, so a newer push about the same subject replaces it on the phone" do
    give_token

    run_job(row)

    expect(sent.last[:android]).to eq(priority: "high", notification: { tag: "spec-trade-7" })
    expect(sent.last[:apns][:headers]).to include("apns-collapse-id": "spec-trade-7")
  end

  it "leaves a push without a tag as it was" do
    give_token
    DiscourseFcmNotifications::Pusher.push(
      user,
      notification_type: Notification.types[:replied],
      topic_id: topic.id,
      post_number: 2,
      topic_title: topic.title,
      excerpt: "A reply",
      username: "alice",
      post_url: "/t/#{topic.slug}/#{topic.id}/2",
    )

    expect(sent.last[:android]).to eq(priority: "high")
    expect(sent.last[:apns][:headers]).not_to have_key(:"apns-collapse-id")
  end

  it "pushes nothing for a row deleted or read before the job ran" do
    give_token
    withdrawn = row
    read = row
    withdrawn.destroy!
    read.update!(read: true)

    run_job(withdrawn)
    run_job(read)

    expect(sent).to be_empty
  end

  it "pushes nothing when no plugin gives words" do
    give_token
    plugin_state[:gives_words] = false

    run_job(row)

    expect(sent).to be_empty
  end

  it "pushes nothing once the row's type is in no plugin category" do
    give_token
    notification = row
    plugin_state[:offers_category] = false

    run_job(notification)

    expect(sent).to be_empty
    expect(plugin_state[:words_asked_for]).to be_empty
  end

  it "pushes nothing to a member in do-not-disturb, or suspended" do
    give_token
    user.do_not_disturb_timings.create!(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

    run_job(row)
    expect(sent).to be_empty

    user.do_not_disturb_timings.destroy_all
    user.update!(suspended_till: 1.day.from_now, suspended_at: Time.zone.now)

    run_job(row)
    expect(sent).to be_empty
  end

  it "asks for no words for a member with no app token" do
    expect(DiscourseFcmNotifications::Pusher.push_row(row)).to eq(false)

    expect(plugin_state[:words_asked_for]).to be_empty
    expect(sent).to be_empty
  end

  it "does not send a push whose plugin category the member muted" do
    give_token
    preference = DiscourseFcmNotifications::FcmNotificationPreference.for_user(user.id)
    preference.muted_categories_list = ["spec_plugin"]
    preference.save!

    run_job(row)

    expect(sent).to be_empty
  end

  describe "a push core sends, filed under a plugin's category" do
    let(:category_modifier) do
      topic_id = topic.id
      Proc.new do |category, payload, _user|
        category || (payload[:topic_id].to_i == topic_id ? "spec_plugin" : nil)
      end
    end

    before do
      give_token
      plugin_instance.register_modifier(:fcm_notifications_push_category, &category_modifier)
    end

    after do
      DiscoursePluginRegistry.unregister_modifier(
        plugin_instance,
        :fcm_notifications_push_category,
        &category_modifier
      )
    end

    def mute(*keys)
      preference = DiscourseFcmNotifications::FcmNotificationPreference.for_user(user.id)
      preference.muted_categories_list = keys
      preference.save!
    end

    # Core's payload reaches the job through JSON, so its keys are strings.
    def push_message
      DiscourseFcmNotifications::Pusher.push(
        user,
        "notification_type" => Notification.types[:private_message],
        "topic_id" => topic.id,
        "post_number" => 1,
        "topic_title" => topic.title,
        "excerpt" => "Price drop on an RTX 3080",
        "username" => "system",
        "post_url" => "/t/#{topic.slug}/#{topic.id}/1",
      )
    end

    it "stops when the plugin's switch or the private messages switch is off" do
      expect(push_message).to eq(true)

      mute("spec_plugin")
      expect(push_message).to eq(false)

      mute("private_messages")
      expect(push_message).to eq(false)

      mute("likes")
      expect(push_message).to eq(true)
    end
  end
end
