# frozen_string_literal: true

# What would stop production booting, or a first deploy finishing, found on the deploying machine.
# Reads config/deploy.yml and the destination's credentials, never the network: /docs/developer/deployment.
class DeployCheck
  PLACEHOLDER_SERVERS = %w[192.168.0.1 192.168.0.2].freeze
  FROM_SECRETS = "set in .kamal/secrets"

  def initialize(root:, destination: nil)
    @root = Pathname(root)
    @destination = destination.presence
  end

  def refusals
    @refusals ||= begin
      boot = RequiredProductionConfig.problems(env, credentials || assumed_credentials, {})
      [ (unreadable_credentials unless credentials), *boot, proxy_refusal, owner_refusal ].compact
    end
  end

  def warnings
    @warnings ||= [ backups_warning, servers_warning, workspace_creation_warning ].compact
  end

  def run(output = $stdout)
    output.puts "Checking #{deploy_files.join(' with ')} and #{relative(credentials_path)}"
    refusals.each { |refusal| output.puts "", refusal }
    warnings.each { |warning| output.puts "", "Warning: #{warning}" }
    output.puts "", refusals.empty? ? "Nothing here stops a deploy." : "#{refusals.size} #{refusals.one? ? 'problem stops' : 'problems stop'} a deploy."
    refusals.empty? ? 0 : 1
  end

  private

  def config
    @config ||= deploy_files.map { |file| YAML.load_file(@root.join(file)) || {} }.reduce { |base, layer| base.deep_merge(layer) }
  end

  def deploy_files = [ "config/deploy.yml", (@destination && "config/deploy.#{@destination}.yml") ].compact

  # Kamal's env is either flat or split into clear and secret; a secret's value lives elsewhere, so its name counts as set.
  def env
    @env ||= begin
      settings = config["env"] || {}
      split = settings.key?("clear") || settings.key?("secret")
      clear = (split ? settings["clear"] || {} : settings).transform_values(&:to_s)
      Array(split ? settings["secret"] : nil).to_h { |name| [ name, FROM_SECRETS ] }.merge(clear)
    end
  end

  def credentials_name = env.fetch("RAILS_CREDENTIALS_ENV", "production")
  def credentials_path = @root.join("config/credentials/#{credentials_name}.yml.enc")
  def key_path = @root.join("config/credentials/#{credentials_name}.key")
  def relative(path) = path.relative_path_from(@root).to_s

  def credentials
    return @credentials if defined?(@credentials)

    @credentials = credentials_path.exist? ? read_credentials : nil
  rescue ActiveSupport::EncryptedFile::MissingKeyError, ActiveSupport::MessageEncryptor::InvalidMessage => e
    @credentials_error = e
    @credentials = nil
  end

  # Stands in for credentials it can't read, so the settings in config/deploy.yml still get checked.
  def assumed_credentials
    { smtp: { user_name: "assumed", password: "assumed" },
      active_record_encryption: RequiredProductionConfig::ENCRYPTION_KEYS.index_with("assumed"),
      object_storage: { access_key_id: "assumed", secret_access_key: "assumed" } }
  end

  def read_credentials
    ActiveSupport::EncryptedConfiguration.new(
      config_path: credentials_path, key_path:, env_key: "RAILS_MASTER_KEY", raise_if_missing_key: true
    ).config
  end

  def unreadable_credentials
    reason =
      if !credentials_path.exist?
        "#{relative(credentials_path)} doesn't exist. bin/mail-setup creates it, with the mail login production needs."
      elsif @credentials_error.is_a?(ActiveSupport::EncryptedFile::MissingKeyError)
        "No key opens #{relative(credentials_path)}. Put it in #{relative(key_path)}, or set RAILS_MASTER_KEY."
      else
        "The key doesn't open #{relative(credentials_path)}. If RAILS_MASTER_KEY is set in this shell, " \
          "run `unset RAILS_MASTER_KEY`; otherwise get #{relative(key_path)} from whoever set this fork up."
      end
    "Deploy check failed: #{reason}\n\nThe settings stored in credentials can't be checked until it opens."
  end

  def proxy_refusal
    return unless forces_ssl?

    proxy = config["proxy"]
    return if proxy.is_a?(Hash) && proxy["ssl"] == true

    <<~MSG
      Deploy check failed: config/deploy.yml has no proxy with ssl: true, but production forces HTTPS.

      config.force_ssl in config/environments/production.rb redirects every request to HTTPS,
      and without kamal-proxy's certificate nothing answers there: /up passes, the app is unreachable.

      Fix: uncomment proxy: in config/deploy.yml, with ssl: true and host: your domain.
      Details: /docs/developer/deployment (SSL configuration section).
    MSG
  end

  def forces_ssl?
    production = @root.join("config/environments/production.rb")
    production.exist? && production.read.match?(/^\s*config\.force_ssl\s*=\s*true\b/)
  end

  def shared? = ForkConfig.tenancy_env(@root, env:, test: false)["WORKSPACE_ON_SIGNUP"] == "shared"

  def owner_refusal
    return unless shared? && env["TENANCY_OWNER_EMAIL"].to_s.strip.empty?

    <<~MSG
      Deploy check failed: the shared preset needs TENANCY_OWNER_EMAIL.

      The first deploy seeds the shared workspace and its first owner, and the seeds stop without
      that owner's address, so the container never starts.

      Fix: set TENANCY_OWNER_EMAIL under env.clear in config/deploy.yml.
      Details: /docs/developer/presets-single-tenant
    MSG
  end

  def backups_warning
    return unless RequiredProductionConfig.backups_off?(env)

    "Backups are off. Set BACKUP_PATH (a folder) or OBJECT_STORAGE_BUCKET (a bucket) under env.clear: " \
      "/docs/developer/deployment (Back up the database section)."
  end

  def servers_warning
    placeholders = hosts_in(config["servers"]) & PLACEHOLDER_SERVERS
    return if placeholders.empty?

    "servers: still lists the template's #{placeholders.join(' and ')}. Put your server's address there."
  end

  def hosts_in(value)
    case value
    when String then [ value ]
    when Array then value.flat_map { |entry| hosts_in(entry) }
    when Hash then value.key?("hosts") ? hosts_in(value["hosts"]) : value.values.flat_map { |entry| hosts_in(entry) }
    else []
    end
  end

  def workspace_creation_warning
    return unless shared? && env["TENANCY_WORKSPACE_CREATION"] != "disabled"

    "The shared preset usually turns off creating more workspaces: TENANCY_WORKSPACE_CREATION: disabled " \
      "under env.clear. /docs/developer/presets-single-tenant"
  end
end
