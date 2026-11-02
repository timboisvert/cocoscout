# frozen_string_literal: true

require "rails_helper"

# Books → Bank rules (V1.3, plan D3; Tim, 2026-11-02): "RESTAURANT DEPOT
# is bar purchases", "SQUARE paying us is bar sales", made from the bank
# page, run over the lines waiting and over every statement brought in later.
RSpec.describe "Manage::BankRules", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:import) { org.bank_statement_imports.create!(imported_by: owner, filename: "oct.csv", format: "csv", lines_count: 0) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def line(on, cents, description)
    import.bank_statement_lines.create!(organization: org, on: on, amount_cents: cents, description: description)
  end

  it "previews, records every line the phrase fits, ignores by another rule, edits, and removes" do
    depot1 = line(Date.new(2026, 10, 3), -18_250, "RESTAURANT DEPOT #0612 CHICAGO IL")
    depot2 = line(Date.new(2026, 10, 17), -9_900, "RESTAURANT DEP 0612")
    square_in = line(Date.new(2026, 10, 4), 41_200, "SQUARE INC DES:251004P2 ID:L2")
    square_fee = line(Date.new(2026, 10, 5), -1_200, "SQUARE INC FEES")
    savings = line(Date.new(2026, 10, 6), -50_000, "ONLINE TRANSFER TO SAVINGS")

    get manage_money_bank_path
    expect(response.body).to include("bank-rules-modal", "bank-rule-modal", "No rules yet", "Make a rule", %(data-bank-rule-contains-param="RESTAURANT DEPOT CHICAGO IL"))

    get manage_preview_money_bank_rules_path(contains: "restaurant depot, restaurant dep", direction: "out"), headers: { "Accept" => "application/json" }
    expect(response.parsed_body).to eq("count" => 2, "samples" => [ "RESTAURANT DEP 0612", "RESTAURANT DEPOT #0612 CHICAGO IL" ])

    post manage_money_bank_rules_path, params: { bank_rule: { contains: "restaurant depot, restaurant dep", direction: "out", action: "record", category_key: "production", counterparty: "Restaurant Depot", on_import: "1" } }
    expect(response).to redirect_to(manage_money_bank_path)
    expect(flash[:notice]).to include("Rule saved.", "2 lines dealt with", "2 recorded")
    expect(depot1.reload.state).to eq("recorded")
    expect(depot2.reload.state).to eq("recorded")
    record = depot1.money_record
    expect(record.kind).to eq("out")
    expect(record.amount_cents).to eq(18_250)
    expect(record.counterparty).to eq("Restaurant Depot")
    expect(record.memo).to eq("RESTAURANT DEPOT #0612 CHICAGO IL")
    expect(record.via).to eq("bank")
    rule = org.bank_rules.last
    expect(rule.contains).to eq("restaurant depot, restaurant dep")
    expect(rule.applied_count).to eq(2)

    # Square paying us is bar sales; Square charging us is not touched by that rule.
    post manage_money_bank_rules_path, params: { bank_rule: { contains: "SQUARE INC", direction: "in", action: "record", category_key: "sponsorship", counterparty: "Square" } }
    expect(square_in.reload.state).to eq("recorded")
    expect(square_fee.reload.state).to eq("open")

    post manage_money_bank_rules_path, params: { bank_rule: { contains: "TRANSFER TO SAVINGS", direction: "any", action: "ignore" } }
    expect(savings.reload.state).to eq("ignored")

    # Recording needs to know income from spending.
    post manage_money_bank_rules_path, params: { bank_rule: { contains: "FLOOD BROTHERS", direction: "any", action: "record", category_key: "production" } }
    expect(flash[:alert]).to include("money in or money out")

    get manage_money_bank_path
    expect(response.body).to include("“restaurant depot” or “restaurant dep”", "Record as", "Restaurant Depot", "2 lines so far", "Ignore", "remove-rule-#{rule.id}")

    patch manage_money_bank_rule_path(rule), params: { bank_rule: { contains: "RESTAURANT DEPOT", direction: "out", action: "record", category_key: "production", counterparty: "Restaurant Depot, Inc." } }
    expect(rule.reload.counterparty).to eq("Restaurant Depot, Inc.")
    expect(flash[:notice]).to include("Rule changed.", "fits none")

    delete manage_money_bank_rule_path(rule)
    expect(BankRule.exists?(rule.id)).to be(false)
    expect(depot1.reload.state).to eq("recorded")
  end

  it "runs the rules on a statement brought in later, after the matching" do
    org.bank_rules.create!(contains: "FLOOD BROTHERS", direction: "out", action: "record", category_key: "production", counterparty: "Flood Brothers", created_by: owner)
    org.bank_rules.create!(contains: "OLD RULE", direction: "out", action: "ignore", on_import: false)
    csv = "Date,Description,Amount\n10/12/2026,FLOOD BROTHERS DISPOSAL,-310.00\n10/13/2026,OLD RULE THING,-5.00\n10/14/2026,SOMETHING ELSE,-7.00\n"
    file = Tempfile.new([ "statement", ".csv" ])
    file.write(csv)
    file.rewind
    perform_enqueued_jobs { post manage_money_bank_import_path, params: { file: Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "oct.csv") } }
    expect(org.bank_statement_lines.find_by!(description: "FLOOD BROTHERS DISPOSAL").state).to eq("recorded")
    expect(org.bank_statement_lines.find_by!(description: "OLD RULE THING").state).to eq("open")
    expect(org.bank_statement_lines.find_by!(description: "SOMETHING ELSE").state).to eq("open")
    # The notification counts what's left after the rules ran.
    expect(owner.notifications.last.title).to include("2 to deal with")
  end

  it "sends a big run to the background and tells you when it's done" do
    40.times { |i| line(Date.new(2026, 10, 1) + i, -1_000 - i, "SQ *BAR SUPPLY #{i}") }
    post manage_money_bank_rules_path, params: { bank_rule: { contains: "SQ *BAR SUPPLY", direction: "out", action: "record", category_key: "production", counterparty: "Bar supply" } }
    expect(flash[:notice]).to include("40 lines fit", "background")
    expect(org.bank_statement_lines.to_deal_with.count).to eq(40)
    expect { perform_enqueued_jobs(only: BankRulesApplyJob) }.to change { owner.notifications.count }.by(1)
    expect(org.bank_statement_lines.to_deal_with.count).to eq(0)
    expect(owner.notifications.last.title).to include("40 lines", "0 left")
  end

  # Suggested rules (Tim, 2026-11-02): from this organization's own lines
  # and what was done with them; yes makes and runs the rule, no hides it.
  it "suggests rules from payees seen more than once, with what was done before and how many lines they catch" do
    a = line(Date.new(2026, 10, 3), -18_250, "POS DEBIT RESTAURANT DEPOT CHICAGO IL")
    b = line(Date.new(2026, 10, 10), -9_900, "POS DEBIT RESTAURANT DEPOT CHICAGO IL")
    line(Date.new(2026, 10, 17), -7_700, "POS DEBIT RESTAURANT DEPOT CHICAGO IL")
    line(Date.new(2026, 10, 4), 41_200, "ORIG CO NAME:ChgTheatres334CR ORIG ID:3630393341 DESC DATE:251004")
    line(Date.new(2026, 10, 11), 39_100, "ORIG CO NAME:ChgTheatres334CR ORIG ID:3630393341 DESC DATE:251011")
    once = line(Date.new(2026, 10, 5), -1_200, "ONLY ONCE LLC")
    savings1 = line(Date.new(2026, 10, 6), -50_000, "Online Transfer to SAV ...9921 transaction#: 1")
    savings2 = line(Date.new(2026, 10, 20), -50_000, "Online Transfer to SAV ...9921 transaction#: 2")
    [ a, b ].each do |l|
      post manage_money_records_path, params: { bank_line: l.id, money_record: { kind: "out", on: l.on.iso8601, amount: format("%.2f", l.amount_cents.abs / 100.0), category_key: "production", counterparty: "Restaurant Depot", via: "bank" } }
    end
    post manage_ignore_money_bank_line_path(savings1)

    suggestions = BankRuleSuggestions.for(org)
    depot = suggestions.find { |sg| sg.phrase == "RESTAURANT DEPOT" }
    expect(depot).to have_attributes(direction: "out", action: "record", category_key: "production", counterparty: "Restaurant Depot", waiting_count: 1, seen_count: 3, times: 2)
    theatres = suggestions.find { |sg| sg.phrase == "CHGTHEATRES" }
    expect(theatres).to have_attributes(direction: "in", action: nil, waiting_count: 2, seen_count: 2)
    # A transfer ignored by hand once suggests ignoring the rest; a payee seen once suggests nothing.
    expect(suggestions.find { |sg| sg.phrase == "SAV" }).to have_attributes(direction: "out", action: "ignore", times: 1, waiting_count: 1)
    expect(suggestions.map(&:phrase)).not_to include("ONLY ONCE")
    expect(once.reload.state).to eq("open")

    get manage_money_bank_path
    expect(response.body).to include("Suggested from your statements", "Has “RESTAURANT DEPOT”", "what you did 2 times", "Catches 1 line waiting", "seen 3 times",
                                     "Has “CHGTHEATRES”", "Needs a category", "Yes, choose a category", "bank-rule-suggestion-#{depot.key}")

    stream = { "Accept" => "text/vnd.turbo-stream.html" }
    post manage_accept_money_bank_rule_suggestion_path(key: depot.key, contains: depot.phrase, direction: "out", rule_action: "record", category_key: "production", counterparty: "Restaurant Depot"), headers: stream
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="bank-rule-suggestion-#{depot.key}"), "1 line dealt with", "data-bank-rules-changed")
    rule = org.bank_rules.reload.last
    expect(rule.contains).to eq("RESTAURANT DEPOT")
    expect(org.bank_statement_lines.where(description_key: a.description_key).pluck(:state).uniq).to eq([ "recorded" ])
    expect(BankRuleSuggestions.for(org).map(&:phrase)).not_to include("RESTAURANT DEPOT")

    post manage_dismiss_money_bank_rule_suggestion_path(key: theatres.key, phrase: theatres.phrase, direction: "in"), headers: stream
    expect(response.body).to include(%(target="bank-rule-suggestion-#{theatres.key}"))
    expect(response.body).not_to include("data-bank-rules-changed")
    expect(org.bank_rule_dismissals.pluck(:phrase, :direction)).to eq([ [ "CHGTHEATRES", "in" ] ])
    expect(BankRuleSuggestions.for(org).map(&:phrase)).not_to include("CHGTHEATRES")

    # A rule says how many lines waiting it would catch now, and can be applied by itself.
    savings2.reopen! if savings2.reload.state != "open"
    org.bank_rules.create!(contains: "Transfer to SAV", direction: "out", action: "ignore")
    get manage_money_bank_path
    expect(response.body).to include("Catches 1 line waiting · not used yet", ">Apply<")
    post manage_apply_money_bank_rules_path(id: org.bank_rules.reload.last.id)
    expect(savings2.reload.state).to eq("ignored")
  end

  it "keeps the bank page read-only for someone without manage on Books" do
    viewer = create(:user, password: password)
    create(:organization_role, user: viewer, organization: org, company_role: "viewer").update!(module_grants: { "books" => "view" })
    post handle_signin_path, params: { email_address: viewer.email_address, password: password }
    post manage_money_bank_rules_path, params: { bank_rule: { contains: "X", direction: "out", action: "ignore" } }
    expect(response).to redirect_to(manage_money_bank_path)
    expect(org.bank_rules.count).to eq(0)
  end
end
