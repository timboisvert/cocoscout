# frozen_string_literal: true

require "rails_helper"

# The dev indicator (Tim, 2026-11-01): dev must never look like production.
RSpec.describe Dev::EnvironmentLabel do
  before { described_class.remove_instance_variable(:@seeded_on) if described_class.instance_variable_defined?(:@seeded_on) }
  after { described_class.remove_instance_variable(:@seeded_on) if described_class.instance_variable_defined?(:@seeded_on) }

  it "says nothing outside development, so production renders no indicator" do
    expect(described_class.text).to be_nil
    expect(described_class.title_prefix).to eq("")
    expect(ApplicationController.render(partial: "shared/dev_indicator").strip).not_to include("amber")
  end

  it "names dev, and says when dev holds production's data, and from which day" do
    allow(Rails.env).to receive(:development?).and_return(true)
    expect(described_class.text).to eq("Dev")
    expect(described_class.title_prefix).to eq("[DEV] ")

    described_class.remove_instance_variable(:@seeded_on)
    ActiveRecord::Base.connection.execute("INSERT INTO ar_internal_metadata (key, value, created_at, updated_at) VALUES ('seeded_from_production_on', '2026-11-01', now(), now()) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value")
    expect(described_class.text).to eq("Dev · production data from Nov 1")
    expect(described_class.title_prefix).to eq("[DEV] ")
    expect(ApplicationController.render(partial: "shared/dev_indicator")).to include("bg-amber-400", "Dev · production data from Nov 1")
  end

  # The app's top bar has little room for a title, and the dev ribbon sits
  # right under it (Tim, 2026-11-09).
  it "leaves the title alone in the app, and marks it in a browser" do
    allow(Rails.env).to receive(:development?).and_return(true)
    helper = Class.new do
      include NativeAppHelper
      attr_accessor :app
      def turbo_native_app? = app
    end.new

    helper.app = true
    expect(helper.dev_title_prefix).to eq("")
    helper.app = false
    expect(helper.dev_title_prefix).to eq("[DEV] ")
  end
end
