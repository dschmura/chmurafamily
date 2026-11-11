require "rails_helper"
require "yaml"

RSpec.describe "the CI workflow" do
  let(:workflow) { YAML.safe_load_file(Rails.root.join(".github/workflows/ci.yml"), aliases: true) }
  let(:triggers) { workflow[true] || workflow["on"] }

  it "checks every pull request, and next and main again after every merge" do
    expect(triggers.keys).to contain_exactly("pull_request", "push")
    expect(triggers.dig("push", "branches")).to contain_exactly("next", "main")
  end

  it "gives every push its own run, so each merge keeps its own result" do
    expect(workflow.dig("concurrency", "group")).to eq("ci-${{ github.workflow }}-${{ github.head_ref || github.sha }}")
    expect(workflow.dig("concurrency", "cancel-in-progress")).to eq("${{ github.event_name == 'pull_request' }}")
  end

  describe "system packages" do
    let(:steps) { workflow["jobs"].values.flat_map { |job| job["steps"].to_a } }
    let(:package_steps) { steps.select { |step| step["uses"] == "./.github/actions/apt-packages" } }
    let(:action) { YAML.safe_load_file(Rails.root.join(".github/actions/apt-packages/action.yml")) }
    let(:action_steps) { action.dig("runs", "steps") }

    it "come through the cached action, so an Ubuntu mirror outage doesn't fail every job" do
      expect(steps.map { |step| step["run"].to_s }.grep(/apt-get/)).to be_empty
      expect(package_steps.map { |step| step.dig("with", "packages") }).to contain_exactly(
        "libvips42t64", "libvips42t64 libheif-plugin-libde265"
      )
      expect(package_steps.map { |step| step["timeout-minutes"] }).to all(eq(5))
    end

    it "are restored before the mirror is asked, under a key that changes with the runner image" do
      uses = action_steps.map { |step| step["uses"].to_s.split("@").first }
      key = action_steps.find { |step| step["id"] == "key" }["run"]

      expect(uses.index("actions/cache/restore")).to be < action_steps.index { |step| step["run"].to_s.include?("apt-get update") }
      expect(key).to include("$ImageOS", "$ImageVersion", "$PACKAGES")
    end

    it "are saved only when the mirror supplied them" do
      save = action_steps.find { |step| step["uses"].to_s.start_with?("actions/cache/save@") }

      expect(save["if"]).to eq("steps.install.outputs.fetched == 'true'")
    end
  end
end
