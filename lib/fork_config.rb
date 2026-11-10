# frozen_string_literal: true

require "yaml"

# The decisions bin/fork recorded in .fork.yml. Stdlib only: bin/ scripts load it before bundle install.
class ForkConfig
  FILE = ".fork.yml"
  PRESETS = %w[personal shared none].freeze

  TENANCY_VARIABLES = %w[WORKSPACE_ON_SIGNUP TENANCY_SHARED_WORKSPACE_SLUG].freeze

  def self.tenancy_env(root, env:, test:)
    recorded = test ? {} : read(root).tenancy_defaults
    recorded.merge(env.to_h.slice(*TENANCY_VARIABLES))
  end

  def self.read(root)
    path = File.join(root, FILE)
    new(File.exist?(path) ? YAML.safe_load_file(path) || {} : {})
  end

  def initialize(data)
    @data = data
  end

  def recorded? = @data.any?
  def preset = @data["preset"]
  def name = @data["name"]
  def template_url = @data["template_url"]

  def tenancy_defaults
    return {} unless preset

    defaults = { "WORKSPACE_ON_SIGNUP" => preset }
    defaults["TENANCY_SHARED_WORKSPACE_SLUG"] = name if preset == "shared"
    defaults
  end
end
