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

    # The bank page points to the Rules page; a line's menu opens the rule page with its payee filled in.
    get manage_money_bank_path
    expect(response.body).to include(manage_money_bank_rules_path, manage_money_bank_sort_path, "Make a rule", ERB::Util.html_escape(manage_new_money_bank_rule_path(contains: "RESTAURANT DEPOT", direction: "out")))
    expect(response.body).not_to include("bank-rules-modal", "bank-rule-modal")
    get manage_money_bank_rules_path
    expect(response.body).to include("Rules are what make the bank easy", "No rules yet", "Start sorting, 5 lines", "Export rules", "Import rules")
    get manage_new_money_bank_rule_path(contains: "RESTAURANT DEPOT", direction: "out")
    expect(response.body).to include("New rule", %(value="RESTAURANT DEPOT"), "What it catches", "Save and apply")

    get manage_preview_money_bank_rules_path(contains: "restaurant depot, restaurant dep", direction: "out"), headers: { "Accept" => "application/json" }
    expect(response.parsed_body).to include("count" => 2, "samples" => [ "RESTAURANT DEP 0612", "RESTAURANT DEPOT #0612 CHICAGO IL" ], "total_cents" => -28_150, "from" => "Oct 3, 2026", "to" => "Oct 17, 2026", "agree" => 0, "disagree" => 0)
    expect(response.parsed_body["lines"].map { |l| l["amount_cents"] }).to eq([ -9_900, -18_250 ])

    post manage_money_bank_rules_path, params: { bank_rule: { contains: "restaurant depot, restaurant dep", direction: "out", action: "record", category_key: "production", counterparty: "Restaurant Depot", on_import: "1" } }
    expect(response).to redirect_to(manage_money_bank_rules_path)
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

    # Recording needs to know income from spending: the page comes back with the mistake.
    post manage_money_bank_rules_path, params: { bank_rule: { contains: "FLOOD BROTHERS", direction: "any", action: "record", category_key: "production" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("money in or money out")

    # The lines already dealt with say whether a rule as typed agrees with them.
    get manage_preview_money_bank_rules_path(contains: "restaurant depot", direction: "out", rule_action: "record", category_key: "marketing"), headers: { "Accept" => "application/json" }
    expect(response.parsed_body).to include("count" => 0, "agree" => 0, "disagree" => 1)
    get manage_preview_money_bank_rules_path(contains: "restaurant depot", direction: "out", rule_action: "record", category_key: "production"), headers: { "Accept" => "application/json" }
    expect(response.parsed_body).to include("agree" => 1, "disagree" => 0)

    get manage_money_bank_rules_path
    expect(response.body).to include("“restaurant depot” or “restaurant dep”", "Record as", "Restaurant Depot", "2 lines so far", "Ignore", "remove-rule-#{rule.id}", manage_edit_money_bank_rule_path(rule))
    get manage_edit_money_bank_rule_path(rule)
    expect(response.body).to include("Change this rule", %(value="restaurant depot, restaurant dep"), "Restaurant Depot")

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

  # The payees without a rule (BankPayees, Tim 2026-11-03): grouped by what
  # the bank says, most lines first; "it varies" takes one off the list.
  it "lists the payees without a rule, grouped the bank's way, and takes one off for good" do
    3.times { |i| line(Date.new(2026, 10, 3 + i), -18_250, "FACEBK *UDRM#{i}VHTS2 650-5434800 DE 10/0#{3 + i}") }
    line(Date.new(2026, 10, 9), -4_400, "FACEBK *QUW2CBWZB4 650-5434800 CA 10/09")
    line(Date.new(2026, 10, 4), 41_200, "ORIG CO NAME:ChgTheatres334CR ORIG ID:3630393341 DESC DATE:251004")
    line(Date.new(2026, 10, 11), 39_100, "ORIG CO NAME:ChgTheatres334CR ORIG ID:3630393341 DESC DATE:251011")
    line(Date.new(2026, 10, 5), -1_200, "ONLY ONCE LLC")
    line(Date.new(2026, 10, 6), -50_000, "Online Transfer to SAV ...9921 transaction#: 1")
    line(Date.new(2026, 10, 20), 50_000, "Online Transfer from SAV ...9921 transaction#: 2")
    line(Date.new(2026, 10, 7), -12_500, "Zelle payment to Jaki Torres Cleaner JPM99cpv028k")
    line(Date.new(2026, 10, 14), -12_500, "Zelle payment to Jaki Torres Cleaner JPM99clkdxub")
    line(Date.new(2026, 10, 15), -32_400, "CHECK 143")
    line(Date.new(2026, 10, 16), -10_000, "CHECK 144")

    payees = BankSort.payees(org)
    expect(payees.map { |g| [ g.name, g.kind, g.direction, g.count ] }).to eq([
      [ "Facebook", "card", "out", 4 ], [ "Your own accounts", "transfer", "any", 2 ], [ "ChgTheatres334CR", "draft", "in", 2 ],
      [ "Jaki Torres Cleaner", "zelle_to", "out", 2 ], [ "Checks", "check", "out", 2 ]
    ])
    expect(payees.first.phrases).to eq([ "FACEBK" ])
    expect(payees.find { |g| g.kind == "transfer" }.phrases).to eq([ "Online Transfer" ])
    expect(payees.find { |g| g.kind == "zelle_to" }.phrases).to eq([ "to Jaki Torres Cleaner" ])
    expect(payees.last.rule?).to be(false)

    get manage_money_bank_rules_path
    expect(response.body).to include("Payees without a rule", ">5<", "Facebook", "Card purchase", "FACEBK", "Your own accounts", "Transfers between your own accounts", "Jaki Torres Cleaner", "Checks", "Record each one")
    expect(response.body).not_to include("Only Once")

    post manage_dismiss_money_bank_payee_path(key: payees.first.key, direction: "out")
    expect(org.bank_rule_dismissals.pluck(:phrase, :direction)).to eq([ [ payees.first.key, "out" ] ])
    expect(BankSort.payees(org).map(&:name)).not_to include("Facebook")

    # A rule that fits a payee's lines takes it off the list too, and says how many it catches.
    org.bank_rules.create!(contains: "Online Transfer", direction: "any", action: "ignore")
    get manage_money_bank_rules_path
    expect(response.body).to include("Catches 2 lines waiting · not used yet", ">Apply<")
    expect(response.body).not_to include("Your own accounts")
    post manage_apply_money_bank_rules_path(id: org.bank_rules.last.id)
    expect(response).to redirect_to(manage_money_bank_rules_path)
    expect(org.bank_statement_lines.where(state: "ignored").count).to eq(2)
  end

  # Rules as a file (Tim, 2026-11-03): made in development, carried to production.
  it "exports the rules to a file and imports them, skipping the ones already there" do
    production = create(:production, organization: org, name: "Dracula")
    org.bank_rules.create!(contains: "RESTAURANT DEPOT, RESTAURANT DEP", direction: "out", action: "record", category_key: "production", counterparty: "Restaurant Depot", production: production)
    org.bank_rules.create!(contains: "Online Transfer", direction: "any", action: "ignore", on_import: false)
    get manage_export_money_bank_rules_path
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Content-Disposition"]).to include("cocoscout-bank-rules-")
    file = response.body
    data = JSON.parse(file)
    expect(data["rules"]).to eq([
      { "contains" => "RESTAURANT DEPOT, RESTAURANT DEP", "direction" => "out", "action" => "record", "category_key" => "production", "counterparty" => "Restaurant Depot", "production" => "Dracula", "on_import" => true },
      { "contains" => "Online Transfer", "direction" => "any", "action" => "ignore", "category_key" => nil, "counterparty" => nil, "production" => nil, "on_import" => false }
    ])

    other = create(:organization, :pro, owner: owner)
    create(:organization_role, :manager, user: owner, organization: other)
    other.bank_rules.create!(contains: "online transfer", direction: "any", action: "ignore")
    extra = JSON.parse(file)
    extra["rules"] << { "contains" => "NOPE", "direction" => "out", "action" => "record", "category_key" => "not_a_category" }
    extra["rules"] << { "contains" => "", "direction" => "out", "action" => "ignore" }
    result = BankRulesFile.import!(other, JSON.generate(extra), by: owner)
    expect(result.to_h).to eq(added: 1, already: 1, skipped: 2)
    added = other.bank_rules.order(:id).last
    expect(added).to have_attributes(contains: "RESTAURANT DEPOT, RESTAURANT DEP", direction: "out", category_key: "production", counterparty: "Restaurant Depot", production: nil, on_import: true, created_by: owner)

    upload = Rack::Test::UploadedFile.new(StringIO.new(file), "application/json", original_filename: "rules.json")
    post manage_import_money_bank_rules_path, params: { file: upload }
    expect(response).to redirect_to(manage_money_bank_rules_path)
    expect(flash[:notice]).to include("0 rules added", "2 already here")
    post manage_import_money_bank_rules_path, params: { file: Rack::Test::UploadedFile.new(StringIO.new("{\"nope\": true}"), "application/json", original_filename: "x.json") }
    expect(flash[:alert]).to include("isn't a CocoScout rules file")
  end

  it "keeps the bank page read-only for someone without manage on Books" do
    viewer = create(:user, password: password)
    create(:organization_role, user: viewer, organization: org, company_role: "viewer").update!(module_grants: { "books" => "view" })
    post handle_signin_path, params: { email_address: viewer.email_address, password: password }
    post manage_money_bank_rules_path, params: { bank_rule: { contains: "X", direction: "out", action: "ignore" } }
    # The module gate turns a viewer's POST away (bank rules are Books).
    expect(response).to have_http_status(:redirect)
    expect(org.bank_rules.count).to eq(0)
    get manage_money_bank_sort_path
    expect(response).to redirect_to(manage_money_bank_path)
  end
end
