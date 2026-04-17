require "test_helper"

class Provider::RegistryTest < ActiveSupport::TestCase
  test "providers filters out nil values when provider is not configured" do
    # Create registry with empty config to ensure OpenAI is not configured
    config = Provider::Registry::Config.new(
      openai_access_token: nil,
      openai_uri_base: nil,
      openai_model: nil
    )
    registry = Provider::Registry.new(:llm, config)

    # Should return empty array instead of [nil]
    assert_equal [], registry.providers
  end

  test "providers returns configured providers" do
    # Mock provider instance directly
    mock_provider = mock("openai_provider")
    registry = Provider::Registry.new(:llm, Provider::Registry::Config.new)
    registry.stubs(:openai).returns(mock_provider)

    assert_equal [ mock_provider ], registry.providers
  end

  test "get_provider raises error when provider not found for concept" do
    registry = Provider::Registry.new(:llm, Provider::Registry::Config.new)

    error = assert_raises(Provider::Registry::Error) do
      registry.get_provider(:nonexistent)
    end

    assert_match(/Provider 'nonexistent' not found for concept: llm/, error.message)
  end

  test "get_provider returns nil when provider not configured" do
    # Create registry with empty config
    config = Provider::Registry::Config.new(
      openai_access_token: nil,
      openai_uri_base: nil,
      openai_model: nil
    )
    registry = Provider::Registry.new(:llm, config)

    # Should return nil when provider method exists but returns nil
    assert_nil registry.get_provider(:openai)
  end

  test "openai provider falls back to Setting when ENV is empty string" do
    # Mock ENV to return empty string (common in Docker/env files)
    # Use stub_env helper which properly stubs ENV access
    ClimateControl.modify(
      "OPENAI_ACCESS_TOKEN" => "",
      "OPENAI_URI_BASE" => "",
      "OPENAI_MODEL" => ""
    ) do
      Setting.stubs(:openai_access_token).returns("test-token-from-setting")
      Setting.stubs(:openai_uri_base).returns(nil)
      Setting.stubs(:openai_model).returns(nil)

      # Uses global instance which loads from ENV/Setting
      Provider::Registry.reset_instance!
      provider = Provider::Registry.get_provider(:openai)

      # Should successfully create provider using Setting value
      assert_not_nil provider
      assert_instance_of Provider::Openai, provider
    end
  end

  test "allows configuration injection for testing without ENV" do
    config = Provider::Registry::Config.new(
      openai_access_token: "test-token",
      openai_model: "gpt-4"
    )
    registry = Provider::Registry.new(:llm, config)

    provider = registry.get_provider(:openai)

    assert_not_nil provider
    assert_instance_of Provider::Openai, provider
  end

  test "class-level configure method sets global instance with custom config" do
    config = Provider::Registry::Config.new(
      stripe_secret_key: "sk_test_123",
      stripe_webhook_secret: "whsec_123"
    )

    Provider::Registry.configure(config)

    provider = Provider::Registry.get_provider(:stripe)
    assert_not_nil provider
    assert_instance_of Provider::Stripe, provider
  ensure
    Provider::Registry.reset_instance!
  end

  test "class-level get_provider delegates to instance" do
    mock_provider = mock("twelve_data_provider")
    config = Provider::Registry::Config.new(twelve_data_api_key: "test_key")
    registry = Provider::Registry.new(nil, config)
    registry.stubs(:twelve_data).returns(mock_provider)

    # Direct registry.get_provider should work
    Provider::Registry.stubs(:instance).returns(registry)

    assert_equal mock_provider, Provider::Registry.get_provider(:twelve_data)
  end
end
