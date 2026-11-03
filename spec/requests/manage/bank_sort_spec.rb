# frozen_string_literal: true

require "rails_helper"

# Books → Bank → Sort (Tim, 2026-11-03): a year of bank lines, one payee at
# a time and then one line at a time, every answer done as it's given.
RSpec.describe "Manage::BankSort", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:import) { org.bank_statement_imports.create!(imported_by: owner, filename: "year.csv", format: "csv", lines_count: 0) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def line(on, cents, description)
    import.bank_statement_lines.create!(organization: org, on: on, amount_cents: cents, description: description)
  end

  it "takes the payees first, biggest first, writes a rule from each answer, then the rest one line at a time" do
    facebook = 3.times.map { |i| line(Date.new(2026, 10, 3 + i), -2_500, "FACEBK *UDRM#{i}VHTS2 650-5434800 DE 10/0#{3 + i}") }
    jaki = 2.times.map { |i| line(Date.new(2026, 10, 7 + i * 7), -12_500, "Zelle payment to Jaki Torres Cleaner JPM99c#{i}") }
    transfers = [ line(Date.new(2026, 10, 6), -50_000, "Online Transfer to SAV ...9921 transaction#: 1"), line(Date.new(2026, 10, 20), 50_000, "Online Transfer from SAV ...9921 transaction#: 2") ]
    tim = [ line(Date.new(2026, 10, 2), -4_000, "Zelle payment to TIMOTHY BOISVERT 1"), line(Date.new(2026, 10, 9), -4_000, "Zelle payment to TIMOTHY BOISVERT 2") ]
    tim_short = line(Date.new(2026, 10, 16), -1_200, "Zelle payment to Tim Boisvert 3")
    checks = [ line(Date.new(2026, 10, 15), -32_400, "CHECK 143"), line(Date.new(2026, 10, 16), -10_000, "CHECK 144") ]
    swap = line(Date.new(2026, 10, 21), 2_000, "Zelle payment from Sekile Nzinga-Johnson 2JM0K6IGMNPF")
    adam = line(Date.new(2026, 10, 22), -50_000, "Zelle payment to Adam Black 27656061916")

    # Part 1 opens on the biggest payee.
    get manage_money_bank_sort_path
    expect(response.body).to include("Sorting · payee 1 of 5", "Part 1 of 2", "0 of 14 sorted", "0 rules made", "Facebook", "Card purchase", "3 · money out", "FACEBK",
                                     "Record it, every time", "Ignore it, every time", "It varies, no rule", "Save the rule, 3 lines, and go on", "Skip, ask me later", "Stop for now")
    expect(BankSortPass.find_by!(organization: org, user: owner).total).to eq(14)

    post manage_money_bank_sort_payee_path, params: { key: BankPayees.group_key_for(facebook.first), answer: "record", category_key: "marketing", counterparty: "Facebook", on_import: "1" }
    expect(response).to redirect_to(manage_money_bank_sort_path)
    expect(flash[:notice]).to include("Rule saved. 3 lines recorded")
    rule = org.bank_rules.last
    expect(rule).to have_attributes(contains: "FACEBK", direction: "out", action: "record", category_key: "marketing", counterparty: "Facebook", on_import: true, applied_count: 3)
    expect(facebook.map { |l| l.reload.state }.uniq).to eq([ "recorded" ])

    # The transfers: an ignore rule, either way.
    get manage_money_bank_sort_path
    expect(response.body).to include("Sorting · payee 1 of 4", "3 of 14 sorted", "1 rule made", "Your own accounts", "Transfers between your own accounts", "money either way")
    post manage_money_bank_sort_payee_path, params: { key: "transfer", answer: "ignore" }
    expect(org.bank_rules.last).to have_attributes(contains: "Online Transfer", direction: "any", action: "ignore")
    expect(transfers.map { |l| l.reload.state }.uniq).to eq([ "ignored" ])

    # Jaki: two lines, too few to call steady, so no guess; skipped for now.
    get manage_money_bank_sort_path
    expect(response.body).to include("Jaki Torres Cleaner", "Zelle to a person")
    expect(response.body).not_to include("We guessed")
    post manage_money_bank_sort_payee_path, params: { key: BankPayees.group_key_for(jaki.first), answer: "skip" }

    # Timothy with Tim offered beside him: both spellings on one rule.
    get manage_money_bank_sort_path
    expect(response.body).to include("Timothy Boisvert", "Also these?", "Tim Boisvert", %(name="also[]"))
    post manage_money_bank_sort_payee_path, params: { key: BankPayees.group_key_for(tim.first), also: [ BankPayees.group_key_for(tim_short) ], answer: "record", category_key: "staff_pay", counterparty: "Tim Boisvert" }
    expect(org.bank_rules.last.contains).to eq("to TIMOTHY BOISVERT, to Tim Boisvert")
    expect((tim + [ tim_short ]).map { |l| l.reload.state }.uniq).to eq([ "recorded" ])
    expect(tim_short.money_record.counterparty).to eq("Tim Boisvert")

    # Checks have nothing for a rule; the skipped come back once, then part 2.
    get manage_money_bank_sort_path
    expect(response.body).to include("Checks", "No rule to make here", "Ignore every check", "Leave them, go on")
    post manage_money_bank_sort_payee_path, params: { key: BankPayees.group_key_for(checks.first), answer: "skip" }
    get manage_money_bank_sort_path
    expect(response.body).to include("Jaki Torres Cleaner")
    post manage_money_bank_sort_payee_path, params: { key: BankPayees.group_key_for(jaki.first), answer: "varies" }
    expect(org.bank_rule_dismissals.pluck(:phrase)).to eq([ BankPayees.group_key_for(jaki.first) ])
    expect(jaki.map { |l| l.reload.state }.uniq).to eq([ "open" ])
    get manage_money_bank_sort_path
    expect(response.body).to include("Checks")
    post manage_money_bank_sort_payee_path, params: { key: BankPayees.group_key_for(checks.first), answer: "skip" }

    # Part 2: newest first, the usual answers as chips, ignore with a note and no rule.
    get manage_money_bank_sort_path
    expect(response.body).to include("Part 2 of 2", "6 lines left", "Adam Black", "Zelle to a person", "−$500.00", "Your usual answers", "Marketing", "Staff pay", ">Ignore<", "Something else…",
                                     "Every time to Adam Black, make it a rule", "Record it and go on", %(name="counterparty" value="Adam Black"))
    post manage_money_bank_sort_line_path, params: { line_id: adam.id, answer: "record", category_key: "performer_pay", counterparty: "Adam Black", make_rule: "1" }
    expect(flash[:notice]).to include("Recorded as Performer pay, Adam Black.", "Rule saved for Adam Black")
    expect(adam.reload.state).to eq("recorded")
    expect(adam.money_record).to have_attributes(kind: "out", amount_cents: 50_000, category_key: "performer_pay", via: "bank", memo: "Zelle payment to Adam Black 27656061916")
    expect(org.bank_rules.last).to have_attributes(contains: "to Adam Black", direction: "out", action: "record", category_key: "performer_pay")

    get manage_money_bank_sort_path
    expect(response.body).to include("Sekile Nzinga-Johnson", "+$20.00", "Zelle from a person")
    post manage_money_bank_sort_line_path, params: { line_id: swap.id, answer: "ignore", note: "Swapped a $20 bill for $20 on Zelle" }
    expect(swap.reload).to have_attributes(state: "ignored", note: "Swapped a $20 bill for $20 on Zelle")
    expect(org.bank_rules.count).to eq(4)

    # Skipped lines come back at the end; checks are recorded one by one.
    post manage_money_bank_sort_line_path, params: { line_id: checks.last.id, answer: "skip" }
    get manage_money_bank_sort_path
    expect(response.body).to include("CHECK 143")
    post manage_money_bank_sort_line_path, params: { line_id: checks.first.id, answer: "record", category_key: "production", counterparty: "Lumber yard" }
    expect(checks.first.reload.state).to eq("recorded")
    [ checks.last, *jaki ].each { |l| post manage_money_bank_sort_line_path, params: { line_id: l.id, answer: "record", category_key: "production" } }
    get manage_money_bank_sort_path
    expect(response.body).to include("Every line is dealt with")
    expect(BankSortPass.where(organization: org)).to be_empty

    # The note shows on the bank page's Dealt with list.
    get manage_money_bank_path
    expect(response.body).to include("Swapped a $20 bill for $20 on Zelle")
  end

  it "offers the match the matcher found, holds matched-looking lines back from a payee's rule, and stops keeping what's done" do
    org.money_records.create!(kind: "in", on: Date.new(2026, 10, 7), amount_cents: 124_000, category_key: "tickets", counterparty: "Door", via: "bank", recorded_by: owner)
    deposit = line(Date.new(2026, 10, 8), 124_000, "DEPOSIT ID NUMBER 95665")
    other = line(Date.new(2026, 10, 1), 30_000, "ATM CASH DEPOSIT 10/01 1130 S CANAL ST CHICAGO IL")
    BankStatementMatcher.run!(org)
    expect(deposit.reload.state).to eq("suggested")

    get manage_money_bank_sort_path
    expect(response.body).to include("Deposits you made", "Cash and checks you took to the bank", "1 of these looks like something already on the books")
    post manage_money_bank_sort_payee_path, params: { key: "deposit:in", answer: "record", category_key: "bar" }
    expect(flash[:notice]).to include("1 line recorded; 1 that look like something on the books come up one by one")
    expect(other.reload.state).to eq("recorded")
    expect(deposit.reload.state).to eq("suggested")

    get manage_money_bank_sort_path
    expect(response.body).to include("Looks like", "Yes, that&#39;s it", "Or, what is it?")
    post manage_money_bank_sort_line_path, params: { line_id: deposit.id, answer: "match" }
    expect(deposit.reload.state).to eq("matched")

    expect(BankSortPass.where(organization: org).count).to eq(1)
    delete manage_money_bank_sort_path
    expect(BankSortPass.where(organization: org)).to be_empty
    expect(response).to redirect_to(manage_money_bank_path)
    expect(flash[:notice]).to include("Everything you answered is done")
  end

  it "points the bank page at sorting when a lot is waiting" do
    get manage_money_bank_path
    expect(response.body).not_to include("A lot to sort")
    50.times { |i| line(Date.new(2026, 1, 1) + i, -1_000, "FACEBK *X#{i} 650-5434800 DE") }
    get manage_money_bank_path
    expect(response.body).to include("A lot to sort", "50 lines waiting · 1 payees you see again and again", "Sort them with me", manage_money_bank_sort_path)
  end
end
