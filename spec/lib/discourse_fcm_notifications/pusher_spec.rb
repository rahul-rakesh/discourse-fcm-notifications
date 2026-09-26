# frozen_string_literal: true

# What a push carries to the phone. The FCM client is replaced by one that keeps each message
# it is given, so every example reads back exactly what would have been sent.
RSpec.describe DiscourseFcmNotifications::Pusher do
  fab!(:user)

  let(:sent) { [] }
  let!(:token) do
    DiscourseFcmNotifications::FcmToken.create!(
      user: user,
      token: "device-token-#{user.id}",
      platform: "android",
    )
  end

  before do
    SiteSetting.fcm_notifications_enabled = true
    messages = sent
    client =
      Class.new do
        define_method(:send_v1) do |message|
          messages << message
          { response: "success" }
        end
      end
    described_class.stubs(:get_fcm_client).returns(client.new)
  end

  # The shape core gives a private-message push (PostAlerter.create_notification_alert).
  def private_message_payload(**overrides)
    {
      notification_type: Notification.types[:private_message],
      post_number: 3,
      topic_title: "Inquiry about: RTX 3080",
      topic_id: 456,
      post_id: 789,
      excerpt: "Is it still available?",
      username: "alice",
      post_url: "/t/inquiry-about-rtx-3080/456/3",
    }.merge(overrides)
  end

  def data
    sent.last[:data]
  end

  it "sends a private message push with its type, topic and post number, as strings, beside the link" do
    expect(described_class.push(user, private_message_payload)).to eq(true)

    expect(data).to eq(
      "linked_obj_type" => "link",
      "linked_obj_data" => "#{Discourse.base_url}/t/inquiry-about-rtx-3080/456/3",
      "notification_type" => Notification.types[:private_message].to_s,
      "topic_id" => "456",
      "post_number" => "3",
    )
  end

  it "links the post with one slash after the site address" do
    described_class.push(user, private_message_payload)

    expect(data["linked_obj_data"]).to eq("#{Discourse.base_url}/t/inquiry-about-rtx-3080/456/3")
    expect(data["linked_obj_data"].delete_prefix(Discourse.base_url)).to start_with("/t/")
  end

  it "sends no routing key a push does not have" do
    described_class.push(
      user,
      private_message_payload(topic_id: nil, post_number: nil, post_url: "/chat/c/general/1"),
    )

    expect(data.keys).to contain_exactly("linked_obj_type", "linked_obj_data", "notification_type")
  end

  it "adds a plugin's own keys without replacing its link or its routing keys" do
    described_class.push(
      user,
      private_message_payload(
        push_data: {
          "url" => "/market/buying",
          "item_id" => 42,
          "topic_id" => 999,
          "linked_obj_data" => "https://example.com/elsewhere",
          "empty" => "",
        },
      ),
    )

    expect(data).to include(
      "url" => "/market/buying",
      "item_id" => "42",
      "topic_id" => "456",
      "linked_obj_data" => "#{Discourse.base_url}/t/inquiry-about-rtx-3080/456/3",
    )
    expect(data).not_to have_key("empty")
  end

  # Core's payload reaches the job through JSON, so its keys arrive as strings.
  it "reads a push given with string keys as one given with symbols" do
    described_class.push(user, private_message_payload.deep_stringify_keys)

    expect(data).to include("notification_type" => "6", "topic_id" => "456", "post_number" => "3")
    expect(sent.last[:notification][:body]).to eq("Is it still available?")
  end

  it "sends the confirmation push with no routing keys" do
    described_class.confirm_subscribe(user, token)

    expect(data).to eq("linked_obj_type" => "link", "linked_obj_data" => Discourse.base_url)
  end
end
