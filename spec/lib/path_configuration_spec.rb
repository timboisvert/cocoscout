# frozen_string_literal: true

require "rails_helper"
require "digest"

# The apps' page rules (public/hotwire-native), shared by iOS and Android:
# V1 installs read path-configuration.json and that file never changes; V1.1
# builds read nav-2/path-configuration.json (V1.1 plan §0a, §4 "Path
# configuration"). The Android app bundles the whole folder as assets.
RSpec.describe "The apps' page rules" do
  let(:root) { Rails.root.join("public/hotwire-native") }
  let(:v1) { JSON.parse(root.join("path-configuration.json").read) }
  let(:nav2) { JSON.parse(root.join("nav-2/path-configuration.json").read) }

  def rule(config, pattern)
    config["rules"].find { |r| r["patterns"].include?(pattern) }
  end

  it "never changes V1's rules" do
    expect(Digest::MD5.hexdigest(root.join("path-configuration.json").read)).to eq("5f94b0b59976831d6e6dac3f33224a40")
    expect(v1["settings"]).to eq({})
  end

  it "marks nav-2 as generation 2 and keeps Manage in the app" do
    expect(nav2.dig("settings", "nav")).to eq(2)
    expect(nav2["rules"].flat_map { |r| r["patterns"] }).not_to include("^/manage", "^/select/")
  end

  it "keeps a wizard's later steps in the modal, and the tabbed edit pages out of one" do
    modal = rule(nav2, "/new$")
    expect(modal["patterns"]).to include("/new/", "/edit$", "/edit/")
    expect(modal.dig("properties", "context")).to eq("modal")

    pages = rule(nav2, "/staffing/staff/[0-9]+/edit$")
    expect(pages["patterns"]).to include("/ticketing/shows/[0-9]+/edit/", "/casting/tables/[0-9]+/edit/")
    expect(pages.dig("properties", "context")).to eq("default")
    # Later rules win, so this one must follow the modal rule.
    expect(nav2["rules"].index(pages)).to be > nav2["rules"].index(modal)
  end

  it "hands files to the phone's viewer: tax forms, invoices, calendars, and the CSV exports" do
    documents = rule(nav2, "^/rails/active_storage/")
    expect(documents.dig("properties", "open_in")).to eq("document")
    expect(documents["patterns"]).to include("/manage/reports/[^/]+\\.csv$", "/staffing/taxes/1099s\\.csv$", "/courses/[0-9]+/roster\\.csv$",
                                             "/tax-forms/[0-9]+/w9/copy$", "/tax-forms/[0-9]+/1099/[0-9]+$")
  end

  it "is what the Android app bundles" do
    gradle = Rails.root.join("android/app/build.gradle.kts").read
    expect(gradle).to include('assets.srcDir("../../public/hotwire-native")')
    expect(Rails.root.join("android/app/src/main/java/com/cocoscout/app/AppConfig.kt").read)
      .to include('PATH_CONFIGURATION_ASSET = "nav-$NAV_GENERATION/path-configuration.json"')
  end
end
