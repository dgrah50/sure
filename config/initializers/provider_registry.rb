# Provider::Registry configuration initializer
# This initializer sets up the global Provider::Registry instance with
# configuration loaded from ENV and Setting. This allows the Registry to be
# testable by injecting mock configurations.
#
# To use a custom configuration in tests:
#   Provider::Registry.configure(Provider::Registry::Config.new(
#     stripe_secret_key: "test_key",
#     # ... other config values
#   ))
#
# To reset to default configuration:
#   Provider::Registry.reset_instance!
Rails.application.config.after_initialize do
  Provider::Registry.reset_instance!
end
