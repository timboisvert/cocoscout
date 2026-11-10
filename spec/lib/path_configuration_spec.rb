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

  # From the organization menu's sheet, Create another organization opens as
  # a page of its own, not inside the sheet (Tim, 2026-11-09).
  it "opens a new organization as a page, after the rule that makes every /new a modal" do
    page = rule(nav2, "^/manage/organizations/new$")
    expect(page.dig("properties", "context")).to eq("default")
    expect(nav2["rules"].index(page)).to be > nav2["rules"].index(rule(nav2, "/new$"))
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

  # A sheet from the bottom, not a page pushed in from the side (Tim, 2026-11-01).
  # Android builds without the sheet screen fall back to the plain page.
  it "slides the organization menu up as a half-height sheet" do
    sheet = rule(nav2, "^/select/organization/menu$")["properties"]
    expect(sheet).to include("context" => "modal", "modal_style" => "medium",
                             "uri" => "hotwire://fragment/web/modal/sheet", "fallback_uri" => "hotwire://fragment/web")
  end

  it "hands files to the phone's viewer: tax forms, invoices, calendars, and the CSV exports" do
    documents = rule(nav2, "^/rails/active_storage/")
    expect(documents.dig("properties", "open_in")).to eq("document")
    expect(documents["patterns"]).to include("/manage/reports/[^/]+\\.csv$", "/staffing/taxes/1099s\\.csv$", "/courses/[0-9]+/roster\\.csv$",
                                             "/tax-forms/[0-9]+/w9/copy$", "/tax-forms/[0-9]+/1099/[0-9]+$")
  end

  # Books' files (Tim, 2026-11-09): a link the rules don't name is tried as a
  # web page, which a PDF or a CSV isn't. Checked against the addresses the
  # pages really link to, format and query included.
  it "hands Books' files to the phone's viewer too" do
    documents = rule(nav2, "^/rails/active_storage/")["patterns"].map { |pattern| Regexp.new(pattern) }
    routes = Rails.application.routes.url_helpers
    files = [
      routes.manage_money_statements_path(format: :pdf, kind: "pnl", period: "this_month"),
      routes.manage_money_statements_path(format: :csv, kind: "pnl", period: "this_month"),
      routes.manage_money_taxes_path(format: :csv, year: 2026),
      routes.manage_ticket_taxes_path(format: :csv, period: "this_month"),
      routes.manage_pdf_money_invoice_path(12, format: :pdf),
      routes.manage_money_file_path(34, download: 1),
      routes.manage_export_money_bank_rules_path,
      routes.pay_invoice_pdf_path(token: "abc", format: :pdf),
      routes.pay_contract_invoice_path(token: "abc", format: :pdf)
    ]
    files.each do |address|
      with_query, path_only = address, address.split("?").first
      expect(documents.any? { |pattern| pattern.match?(with_query) && pattern.match?(path_only) }).to be(true), "no document rule for #{address}"
    end
    pages = [ routes.manage_money_statements_path(kind: "pnl"), routes.manage_money_taxes_path, routes.manage_ticket_taxes_path,
              routes.manage_money_bank_rules_path, "/manage/money/invoices/12", "/pay/invoice/abc" ]
    pages.each { |address| expect(documents.none? { |pattern| pattern.match?(address) }).to be(true), "#{address} is a page, not a file" }
  end

  it "is what the Android app bundles" do
    gradle = Rails.root.join("android/app/build.gradle.kts").read
    expect(gradle).to include('assets.srcDir("../../public/hotwire-native")')
    expect(Rails.root.join("android/app/src/main/java/com/cocoscout/app/AppConfig.kt").read)
      .to include('PATH_CONFIGURATION_ASSET = "nav-$NAV_GENERATION/path-configuration.json"')
  end
end
