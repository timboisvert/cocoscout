# frozen_string_literal: true

require "rails_helper"

# The dev indicator (Tim, 2026-11-01): dev must never look like production.
RSpec.describe Dev::EnvironmentLabel do
  before { described_class.remove_instance_variable(:@prod_copy_from) if described_class.instance_variable_defined?(:@prod_copy_from) }
  after { described_class.remove_instance_variable(:@prod_copy_from) if described_class.instance_variable_defined?(:@prod_copy_from) }

  it "says nothing outside development, so production renders no indicator" do
    expect(described_class.text).to be_nil
    expect(described_class.title_prefix).to eq("")
    expect(ApplicationController.render(partial: "shared/dev_indicator").strip).not_to include("amber")
  end

  it "names dev, and a production copy with the day it was taken" do
    allow(Rails.env).to receive(:development?).and_return(true)
    expect(described_class.text).to eq("Dev")
    expect(described_class.title_prefix).to eq("[DEV] ")

    described_class.remove_instance_variable(:@prod_copy_from)
    ActiveRecord::Base.connection.execute("INSERT INTO ar_internal_metadata (key, value, created_at, updated_at) VALUES ('prod_copy_from', '2026-11-01', now(), now()) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value")
    expect(described_class.text).to eq("Dev · production copy Nov 1")
    expect(described_class.title_prefix).to eq("[DEV COPY] ")
    expect(ApplicationController.render(partial: "shared/dev_indicator")).to include("bg-amber-400", "Dev · production copy Nov 1")
  end
end
