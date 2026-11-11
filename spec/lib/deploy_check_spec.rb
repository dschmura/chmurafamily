require "rails_helper"
require "tmpdir"

# Every fixture lives in a temp root, and every key is generated here: the check never meets a real one.
RSpec.describe DeployCheck do
  around do |example|
    inherited = ENV.delete("RAILS_MASTER_KEY")
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      example.run
    end
  ensure
    ENV["RAILS_MASTER_KEY"] = inherited
  end

  let(:ready_env) { { "RAILS_HOST" => "app.acme.test", "SMTP_ADDRESS" => "smtp.postmarkapp.com", "BACKUP_PATH" => "/backups" } }
  let(:ready_credentials) do
    { "smtp" => { "user_name" => "token", "password" => "token" },
      "active_record_encryption" => { "primary_key" => "p", "deterministic_key" => "d", "key_derivation_salt" => "s" } }
  end

  def write(path, content) = @root.join(path).tap { |file| file.dirname.mkpath }.write(content)

  def deploy(env: ready_env, proxy: { "ssl" => true, "host" => "app.acme.test" }, hosts: [ "203.0.113.10" ], secret: [ "RAILS_MASTER_KEY" ])
    config = { "servers" => { "web" => { "hosts" => hosts } }, "env" => { "clear" => env, "secret" => secret } }
    config["proxy"] = proxy if proxy
    write("config/deploy.yml", config.to_yaml)
  end

  def credentials(content = ready_credentials, name: "production")
    key = ActiveSupport::EncryptedFile.generate_key
    write("config/credentials/#{name}.key", key)
    ActiveSupport::EncryptedConfiguration.new(
      config_path: @root.join("config/credentials/#{name}.yml.enc"), key_path: @root.join("config/credentials/#{name}.key"),
      env_key: "RAILS_MASTER_KEY", raise_if_missing_key: true
    ).write(content.to_yaml)
    key
  end

  def force_ssl(on) = write("config/environments/production.rb", "Rails.application.configure do\n  config.force_ssl = #{on}\nend\n")

  def check(destination = nil) = described_class.new(root: @root, destination:)

  before { force_ssl(true) }

  it "passes a configuration production boots on" do
    deploy
    credentials

    expect(check.refusals).to be_empty
    expect(check.warnings).to be_empty
  end

  it "lists every boot-guard refusal at once" do
    deploy(env: { "OBJECT_STORAGE_BUCKET" => "app-backups" })
    credentials({})

    expect(check.refusals.map { |refusal| refusal.lines.first })
      .to match([ /RAILS_HOST is unset/, /SMTP_ADDRESS is unset/, /encryption keys are missing/, /OBJECT_STORAGE_REGION is unset/ ])
  end

  it "counts a variable listed under env.secret as set" do
    deploy(env: ready_env.except("RAILS_HOST"), secret: %w[RAILS_MASTER_KEY RAILS_HOST])
    credentials

    expect(check.refusals).to be_empty
  end

  describe "credentials it can't read" do
    before { deploy }

    it "says when the credentials file doesn't exist" do
      expect(check.refusals.join).to include("config/credentials/production.yml.enc doesn't exist", "bin/mail-setup")
    end

    it "still checks the settings in config/deploy.yml, and only those" do
      deploy(env: ready_env.except("RAILS_HOST"))

      expect(check.refusals.map { |refusal| refusal.lines.first })
        .to match([ /production.yml.enc doesn't exist/, /RAILS_HOST is unset/ ])
    end

    it "says where the key goes when there is none" do
      credentials
      @root.join("config/credentials/production.key").delete

      expect(check.refusals.join).to include("config/credentials/production.key", "RAILS_MASTER_KEY")
    end

    it "suspects an exported RAILS_MASTER_KEY when the key is wrong" do
      credentials
      ENV["RAILS_MASTER_KEY"] = ActiveSupport::EncryptedFile.generate_key

      expect(check.refusals.join).to include("doesn't open", "unset RAILS_MASTER_KEY")
    end
  end

  describe "HTTPS" do
    before { credentials }

    it "refuses a deploy with no SSL proxy while production forces HTTPS" do
      deploy(proxy: nil)

      expect(check.refusals.join).to include("proxy", "ssl: true", "force_ssl")
    end

    it "refuses a proxy whose ssl isn't on" do
      deploy(proxy: { "host" => "app.acme.test" })

      expect(check.refusals.join).to include("ssl: true")
    end

    it "leaves the proxy alone when production doesn't force HTTPS" do
      force_ssl(false)
      deploy(proxy: nil)

      expect(check.refusals).to be_empty
    end
  end

  describe "the shared preset" do
    before do
      write(".fork.yml", "name: acme\npreset: shared\n")
      credentials
    end

    it "refuses a first deploy that can't seed the shared workspace's owner" do
      deploy

      expect(check.refusals.join).to include("TENANCY_OWNER_EMAIL")
    end

    it "warns while workspace creation is still on" do
      deploy(env: ready_env.merge("TENANCY_OWNER_EMAIL" => "owner@acme.test"))

      expect(check.refusals).to be_empty
      expect(check.warnings.join).to include("TENANCY_WORKSPACE_CREATION")
    end
  end

  it "warns about the template's placeholder server and backups being off" do
    deploy(env: ready_env.except("BACKUP_PATH"), hosts: [ "192.168.0.1" ])
    credentials

    expect(check.warnings.join).to include("192.168.0.1", "Backups are off")
  end

  it "checks a destination with its merged settings and its own credentials" do
    deploy
    credentials({}, name: "production")
    write("config/deploy.staging.yml", { "env" => { "clear" => { "RAILS_CREDENTIALS_ENV" => "staging" } } }.to_yaml)
    credentials(name: "staging")

    expect(check("staging").refusals).to be_empty
  end

  describe "#run" do
    it "prints each refusal and fails" do
      deploy(env: ready_env.except("RAILS_HOST"))
      credentials
      output = StringIO.new

      expect(check.run(output)).to eq(1)
      expect(output.string).to include("RAILS_HOST is unset")
    end

    it "prints warnings and passes when nothing is refused" do
      deploy(hosts: [ "192.168.0.1" ])
      credentials
      output = StringIO.new

      expect(check.run(output)).to eq(0)
      expect(output.string).to include("192.168.0.1")
    end
  end

  it "runs as bin/rails deploy:check" do
    RakeTasks.load_once

    expect(Rake::Task["deploy:check"].prerequisites).to include("environment")
  end
end
