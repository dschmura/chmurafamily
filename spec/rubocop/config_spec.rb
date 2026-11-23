# frozen_string_literal: true

require "rubocop"

RSpec.describe "The RuboCop config" do
  it "skips the gitignored docs/ folder, so a scratch file there can't block a push" do
    root = File.expand_path("../..", __dir__)
    config = Dir.chdir(root) { RuboCop::ConfigStore.new.for_pwd }

    expect(config.file_to_exclude?(File.join(root, "docs/scratch.rb"))).to be(true)
    expect(config.file_to_exclude?(File.join(root, "app/models/user.rb"))).to be(false)
  end
end
