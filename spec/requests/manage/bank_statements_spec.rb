# frozen_string_literal: true

require "rails_helper"

# Books → Bank (V1.3, plan D3 and §9.13): a statement file read once and
# never kept; its lines matched to the books in a job (the person is told
# when it's done), then each one recorded or ignored.
RSpec.describe "Manage::BankStatements", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def upload(text, name)
    file = Tempfile.new([ "statement", File.extname(name) ])
    file.write(text)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: name)
  end

  # The books can't know what's in the bank until a statement says so: the
  # first visit is only the way in (Tim, 2026-11-02).
  it "first visit: no balances, just the way to bring a statement in" do
    get manage_money_bank_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("What happens to your file", "never stored", "Bring your first statement in", "Read the file")
    expect(response.body).not_to include("Bank, per your books", "To deal with")

    get manage_money_books_path
    expect(response.body).not_to include("Bank, per your books")
  end

  it "shows the books' bank balance beside the statement once one is in" do
    org.bank_statement_imports.create!(imported_by: owner, filename: "october.csv", format: "csv", lines_count: 0)
    get manage_money_bank_path
    expect(response.body).to include("Bank, per your books", "To deal with", "Statements brought in")
    get manage_money_books_path
    expect(response.body).to include("Bank, per your books")
  end

  it "reads a CSV, matches what the books already have in the background, tells you, and leaves the rest to deal with; the file is not kept" do
    org.money_records.create!(kind: "in", on: Date.new(2026, 10, 3), amount_cents: 90_000, category_key: "sponsorship", counterparty: "Logan Square Chamber", via: "bank", recorded_by: owner)
    csv = <<~CSV
      Date,Description,Amount
      10/03/2026,DEPOSIT LOGAN SQ CHAMBER,"900.00"
      10/05/2026,CHICAGO LUMBER CO,-240.00
      10/06/2026,TRANSFER TO SAVINGS,-500.00
    CSV

    expect { post manage_money_bank_import_path, params: { file: upload(csv, "october.csv") } }.not_to change(ActiveStorage::Attachment, :count)
    expect(response).to redirect_to(manage_money_bank_path)
    expect(flash[:notice]).to include("3 lines read", "matching them to the books now", "notification", "The file is gone")
    import = org.bank_statement_imports.last
    expect(import.format).to eq("csv")
    expect(import.filename).to eq("october.csv")
    expect(import.lines_count).to eq(3)
    expect(import).to be_matching
    expect(org.bank_statement_lines.where(state: "open").count).to eq(3)

    # Until the job runs, the page says so and refreshes itself.
    get manage_money_bank_path
    expect(response.body).to include("Matching the statement to the books", "auto-refresh")

    expect { perform_enqueued_jobs(only: BankStatementMatchJob) }.to change { owner.notifications.count }.by(1)
    expect(import.reload.status).to eq("ready")
    expect(import.matched_count).to eq(1)
    expect(org.bank_statement_lines.where(state: "matched").count).to eq(1)
    expect(org.bank_statement_lines.to_deal_with.count).to eq(2)
    notice = owner.notifications.last
    expect(notice.category).to eq("books")
    expect(notice.title).to include("October 2026", "1 matched", "2 to deal with")
    expect(notice.path).to eq(manage_money_bank_path)

    get manage_money_bank_path
    expect(response.body).to include("CHICAGO LUMBER CO", "TRANSFER TO SAVINGS", "Record it", "Ignore", "October 2026", "Bring a statement in", "Remove")
    # Newest first, the way the bank lists them (Tim, 2026-11-02).
    expect(response.body.index("TRANSFER TO SAVINGS")).to be < response.body.index("CHICAGO LUMBER CO")
    expect(response.body).not_to include("Looks like", "Matching the statement")

    # The same file again adds nothing.
    post manage_money_bank_import_path, params: { file: upload(csv, "october.csv") }
    expect(flash[:notice]).to include("3 already in")
    expect(org.bank_statement_lines.count).to eq(3)
  end

  it "records a line as money by hand and ignores another, and either can be undone" do
    csv = "Date,Description,Debit,Credit\n10/05/2026,CHICAGO LUMBER CO,240.00,\n10/06/2026,TRANSFER TO SAVINGS,500.00,\n"
    perform_enqueued_jobs { post manage_money_bank_import_path, params: { file: upload(csv, "oct.csv") } }
    lumber = org.bank_statement_lines.find_by!(description: "CHICAGO LUMBER CO")
    savings = org.bank_statement_lines.find_by!(description: "TRANSFER TO SAVINGS")
    expect(lumber.amount_cents).to eq(-24_000)

    get manage_new_money_record_path(kind: "out", amount: "240.00", on: "2026-10-05", memo: "CHICAGO LUMBER CO", bank_line: lumber.id)
    expect(response.body).to include("CHICAGO LUMBER CO", %(name="bank_line"))
    expect(response.body).to include(%(value="#{lumber.id}"))
    post manage_money_records_path, params: { bank_line: lumber.id, money_record: { kind: "out", on: "2026-10-05", amount: "240.00", category_key: "production", counterparty: "Chicago Lumber Co.", via: "bank", memo: "Set lumber" } }
    expect(response).to redirect_to(manage_money_bank_path)
    expect(lumber.reload.state).to eq("recorded")
    expect(lumber.money_record).to be_present
    expect(lumber.journal_line.ledger_account.key).to eq("bank")

    post manage_ignore_money_bank_line_path(savings)
    expect(savings.reload.state).to eq("ignored")
    get manage_money_bank_path
    expect(response.body).to include("Every line is dealt with.", "Dealt with", "Recorded", "Ignored")

    post manage_reopen_money_bank_line_path(savings)
    expect(savings.reload.state).to eq("open")
  end

  it "suggests a near match for confirming, and reads an OFX closing balance" do
    org.money_records.create!(kind: "out", on: Date.new(2026, 10, 8), amount_cents: 12_500, category_key: "marketing", counterparty: "Facebook", via: "bank", recorded_by: owner)
    ofx = <<~OFX
      OFXHEADER:100
      <OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS>
      <BANKTRANLIST>
      <STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20261010120000<TRNAMT>-125.00<FITID>abc123<NAME>FACEBK ADS<MEMO>Card 4411</STMTTRN>
      </BANKTRANLIST>
      <LEDGERBAL><BALAMT>1875.00<DTASOF>20261031</LEDGERBAL>
      </STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
    OFX
    perform_enqueued_jobs { post manage_money_bank_import_path, params: { file: upload(ofx, "october.ofx") } }
    line = org.bank_statement_lines.last
    expect(line.state).to eq("suggested")
    expect(line.description).to eq("FACEBK ADS · Card 4411")
    expect(org.bank_statement_imports.last.closing_balance_cents).to eq(187_500)

    get manage_money_bank_path
    expect(response.body).to include("Looks like", "Facebook", "Bank, per the statement", "$1,875.00", "Difference", "Yes to all 1 suggestion")

    post manage_match_money_bank_line_path(line)
    expect(line.reload.state).to eq("matched")
  end

  it "offers what was recorded last time for the same payee, confirms every suggestion at once, filters by month, and removes a statement" do
    org.money_records.create!(kind: "out", on: Date.new(2026, 9, 8), amount_cents: 12_500, category_key: "marketing", counterparty: "Facebook", via: "bank", recorded_by: owner)
    csv = <<~CSV
      Date,Description,Amount
      09/08/2026,FACEBK ADS 4411,-125.00
      09/20/2026,CHICAGO LUMBER CO 7781,-240.00
      10/18/2026,CHICAGO LUMBER CO 9920,-310.00
    CSV
    perform_enqueued_jobs { post manage_money_bank_import_path, params: { file: upload(csv, "fall.csv") } }
    september = org.bank_statement_lines.find_by!(description: "CHICAGO LUMBER CO 7781")
    october = org.bank_statement_lines.find_by!(description: "CHICAGO LUMBER CO 9920")
    expect(september.description_key).to eq(october.description_key)
    expect(org.bank_statement_lines.find_by!(description: "FACEBK ADS 4411").state).to eq("matched")

    post manage_money_records_path, params: { bank_line: september.id, money_record: { kind: "out", on: "2026-09-20", amount: "240.00", category_key: "production", counterparty: "Chicago Lumber Co.", via: "bank" } }
    get manage_money_bank_path
    expect(response.body).to include("Last time:", "Chicago Lumber Co.", %(data-bank-record-counterparty-param="Chicago Lumber Co."), %(data-bank-record-category-param="production"))

    get manage_money_bank_path(month: "2026-09")
    expect(response.body).not_to include("CHICAGO LUMBER CO 9920")
    get manage_money_bank_path(month: "2026-10")
    expect(response.body).to include("CHICAGO LUMBER CO 9920")

    # Two days off and nothing in the name to go on: a suggestion, not a match.
    org.money_records.create!(kind: "out", on: Date.new(2026, 10, 16), amount_cents: 31_000, category_key: "production", counterparty: "Hardware store", via: "bank", recorded_by: owner)
    perform_enqueued_jobs { post manage_money_bank_import_path, params: { file: upload(csv, "fall.csv") } }
    expect(october.reload.state).to eq("suggested")
    post manage_match_all_money_bank_lines_path
    expect(october.reload.state).to eq("matched")

    import = org.bank_statement_imports.order(:id).first
    delete manage_money_bank_statement_path(import)
    expect(response).to redirect_to(manage_money_bank_path)
    expect(BankStatementImport.exists?(import.id)).to be(false)
    expect(org.bank_statement_lines.count).to eq(0)
    expect(org.money_records.count).to eq(3)
  end

  # Nothing bounces to another page (Tim, 2026-11-02): an action on a line
  # answers with a Turbo Stream that swaps its row, and Record it is a modal
  # on the page whose save does the same.
  it "answers an action on a line with its row swapped in place, and records a line from the modal without leaving" do
    org.money_records.create!(kind: "out", on: Date.new(2026, 10, 8), amount_cents: 12_500, category_key: "marketing", counterparty: "Facebook", via: "bank", recorded_by: owner)
    csv = "Date,Description,Amount\n10/10/2026,FACEBK ADS,-125.00\n10/05/2026,CHICAGO LUMBER CO,-240.00\n"
    perform_enqueued_jobs { post manage_money_bank_import_path, params: { file: upload(csv, "oct.csv") } }
    ads = org.bank_statement_lines.find_by!(description: "FACEBK ADS")
    lumber = org.bank_statement_lines.find_by!(description: "CHICAGO LUMBER CO")
    expect(ads.state).to eq("suggested")

    get manage_money_bank_path
    expect(response.body).to include("bank-record-modal", "Record this line", "bank-record#open", %(data-bank-record-line-param="#{lumber.id}"), "Yes to all 1 suggestion")

    stream = { "Accept" => "text/vnd.turbo-stream.html" }
    post manage_match_money_bank_line_path(ads), headers: stream
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="bank_statement_line_#{ads.id}"), "Matched", "Undo", "bank-line-#{ads.id}-actions", %(target="bank-tiles"), %(target="bank-open-count"), "1 line", %(target="bank-yes-to-all"))
    expect(response.body).not_to include("Yes to all")
    expect(ads.reload.state).to eq("matched")

    post manage_money_records_path, headers: stream, params: { bank_line: lumber.id, money_record: { kind: "out", on: "2026-10-05", amount: "240.00", category_key: "", counterparty: "Chicago Lumber Co.", via: "bank" } }
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="bank-record-modal"), "Chicago Lumber Co.", %(value="#{lumber.id}"))
    expect(response.body).not_to include(%(id="bank-record-modal"\n     class="hidden))
    expect(lumber.reload.state).to eq("open")

    post manage_money_records_path, headers: stream, params: { bank_line: lumber.id, money_record: { kind: "out", on: "2026-10-05", amount: "240.00", category_key: "production", counterparty: "Chicago Lumber Co.", via: "bank" } }
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="bank_statement_line_#{lumber.id}"), "Recorded", %(target="bank-record-modal"), "Nothing")
    expect(lumber.reload.state).to eq("recorded")

    post manage_reopen_money_bank_line_path(lumber), headers: stream
    expect(response.body).to include("Record it", "Ignore")
    expect(lumber.reload.state).to eq("open")
  end

  it "says so when the file cannot be read" do
    post manage_money_bank_import_path, params: { file: upload("just some words\nno columns here\n", "notes.csv") }
    expect(response).to redirect_to(manage_money_bank_path)
    expect(flash[:alert]).to include("find the columns")
  end
end
