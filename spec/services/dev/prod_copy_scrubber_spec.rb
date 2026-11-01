# frozen_string_literal: true

require "rails_helper"

# Seeding dev from production (Tim, 2026-11-01): the kept logins stay,
# nobody else is reachable, nothing can move money or sign in.
RSpec.describe Dev::ProdCopyScrubber do
  let(:conn) { ActiveRecord::Base.connection }
  let!(:tim) { create(:user, email_address: "boisvert@gmail.com", password: "TimsPassword1!") }
  let!(:other) { create(:user, email_address: "dana@example.com", password: "DanasPassword1!") }
  let!(:org) { create(:organization, owner: tim, stripe_account_id: "acct_real") }
  let!(:person) { create(:person, email: "fox@example.com", name: "Fox Mulder") }

  def scrub = described_class.new(keep_emails: %w[boisvert@gmail.com dev-manager@cocoscout.test], copied_on: Date.new(2026, 11, 1), allow_test: true).run!

  it "keeps one login, locks the rest out, and rewrites every email" do
    tim_digest = tim.password_digest
    Session.create!(user: other, ip_address: "1.2.3.4", user_agent: "x") if defined?(Session)

    scrub

    expect(tim.reload.password_digest).to eq(tim_digest)
    expect(tim.email_address).to eq("boisvert@gmail.com")
    other.reload
    expect(other.email_address).to eq("user-#{other.id}@prodcopy.test")
    expect(other.authenticate("DanasPassword1!")).to be(false)
    expect(person.reload.email).to eq("people-#{person.id}@prodcopy.test")
    expect(person.name).to eq("Fox Mulder")
    expect(org.reload.stripe_account_id).to be_nil
    expect(Session.count).to eq(0) if defined?(Session)
    expect(conn.select_value("SELECT value FROM ar_internal_metadata WHERE key = 'seeded_from_production_on'")).to eq("2026-11-01")
  end

  it "refuses outside development, and without a login to keep" do
    expect { described_class.new(keep_emails: [ "boisvert@gmail.com" ]).run! }.to raise_error(described_class::Refused, /only in development/)
    expect { described_class.new(keep_emails: [], allow_test: true).run! }.to raise_error(described_class::Refused, /lock yourself out/)
  end

  # Every column whose name looks secret must be cleared by the rules, or be
  # listed here as safe with the reason. A new token column fails this until
  # someone decides.
  it "covers every secret-looking column in the schema" do
    safe = {
      "content_templates.token_list" => "template variable names",
      "users.password_digest" => "handled on its own: everyone but the kept login",
      "w9_submissions.tin_type" => "says SSN or EIN, not the number",
      "rpush_apps.password" => "rpush tables are emptied whole"
    }
    suspicious = /token|secret|password|credential|api_key|\Atin|_tin\z|\Aein\z|ssn/
    missed = conn.tables.flat_map do |table|
      conn.columns(table).filter_map do |col|
        key = "#{table}.#{col.name}"
        next unless col.name.match?(suspicious)
        next if col.type == :boolean || col.type == :datetime || col.type == :date
        next if col.name.match?(described_class::SECRET_COLUMN) || safe.key?(key)
        next if table.start_with?("rpush_", "solid_queue_") || described_class::EMPTIED_TABLES.include?(table)

        key
      end
    end
    expect(missed).to eq([]), "secret-looking columns the scrubber would leave in a copy: #{missed.join(', ')}"
  end
end
