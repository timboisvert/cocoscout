# frozen_string_literal: true

module Manage
  # Money → Books → Bank (plan D3, §9.13): bring a statement in as a file and
  # deal with every line: it matches something on the books, you record it,
  # or you ignore it. The file is read once, here, and never kept. Books
  # access, by the grid; changing needs manage.
  class BankStatementsController < Manage::ManageController
    before_action :require_change!, only: %i[create match ignore reopen]
    before_action :set_line, only: %i[match ignore reopen]

    def show
      org = Current.organization
      @imports = org.bank_statement_imports.order(created_at: :desc).limit(12).to_a
      @last = @imports.first
      @to_deal_with = org.bank_statement_lines.to_deal_with.includes(journal_line: :journal_entry).to_a
      @recent_done = org.bank_statement_lines.done.order(updated_at: :desc).limit(8).includes(:money_record, journal_line: :journal_entry).to_a
      @done_count = org.bank_statement_lines.done.count
      @books_bank_cents = ChartOfAccounts.account(org, :bank).natural_balance_cents
      @books_bank_on_closing_cents = @last&.closing_on ? ChartOfAccounts.account(org, :bank).natural_balance_cents(basis: :cash, as_of: @last.closing_on) : nil
      @candidates = {}
      @to_deal_with.each { |line| @candidates[line.id] = line.journal_line ? describe(line.journal_line) : nil }
    end

    # The upload. The file's text is read out of the request and parsed
    # while you wait; the temp file Rack made goes with the request.
    def create
      upload = params[:file]
      return redirect_to manage_money_bank_path, alert: "Choose the file first." if upload.blank? || !upload.respond_to?(:read)
      return redirect_to manage_money_bank_path, alert: "That file is too large. A month from the bank is well under 5 MB." if upload.size.to_i > 5.megabytes

      text = upload.read
      result = BankStatementParser.parse(text, filename: upload.original_filename)
      import = nil
      added = 0
      BankStatementImport.transaction do
        import = Current.organization.bank_statement_imports.create!(imported_by: Current.user, filename: File.basename(upload.original_filename.to_s), format: result.format,
                                                                      from_on: result.lines.map { |l| l[:on] }.min, to_on: result.lines.map { |l| l[:on] }.max, lines_count: result.lines.size,
                                                                      closing_balance_cents: result.closing_balance_cents, closing_on: result.closing_on)
        result.lines.each do |l|
          fingerprint = l[:fitid].present? ? "fitid:#{l[:fitid]}"[0, 60] : BankStatementLine.fingerprint_for(l[:on], l[:amount_cents], l[:description])
          next if Current.organization.bank_statement_lines.exists?(fingerprint: fingerprint)

          import.bank_statement_lines.create!(organization: Current.organization, on: l[:on], amount_cents: l[:amount_cents], description: l[:description].to_s[0, 255], fingerprint: fingerprint)
          added += 1
        end
        import.update!(new_lines_count: added)
      end
      BankStatementMatcher.run!(Current.organization, import.bank_statement_lines.where(state: "open"))
      matched = import.bank_statement_lines.where(state: "matched").count
      left = import.bank_statement_lines.where(state: %w[open suggested]).count
      redirect_to manage_money_bank_path, notice: "#{pluralize_lines(result.lines.size)} read#{added < result.lines.size ? ", #{result.lines.size - added} already in" : ''}. #{matched} matched the books by themselves; #{left} to deal with. The file is gone."
    rescue BankStatementParser::Unreadable => e
      redirect_to manage_money_bank_path, alert: e.message
    rescue CSV::MalformedCSVError
      redirect_to manage_money_bank_path, alert: "Couldn't read that as a CSV. Download the statement again from your bank as CSV or OFX."
    ensure
      tempfile = upload.respond_to?(:tempfile) ? upload.tempfile : nil
      if tempfile
        tempfile.close unless tempfile.closed?
        tempfile.unlink
      end
    end

    def match
      line = params[:journal_line_id].present? ? JournalLine.find_by(id: params[:journal_line_id], organization: Current.organization) : @line.journal_line
      return redirect_to manage_money_bank_path, alert: "Pick the line on the books it matches." unless line

      @line.match!(line)
      redirect_to manage_money_bank_path, notice: "Matched."
    end

    def ignore
      @line.ignore!
      redirect_to manage_money_bank_path, notice: "Ignored. It stays in the list of what you have dealt with."
    end

    def reopen
      @line.reopen!
      redirect_to manage_money_bank_path, notice: "Back in the list."
    end

    private

    def set_line
      @line = Current.organization.bank_statement_lines.find(params[:id])
    end

    def require_change!
      return if OrganizationAccess.allows?(Current.user, Current.organization, :books, :manage)

      redirect_to manage_money_bank_path, alert: "You can look at the bank page but not change it."
    end

    def pluralize_lines(n) = "#{n} #{n == 1 ? 'line' : 'lines'}"

    # A line on the books, in words: what it is, from which entry.
    def describe(journal_line)
      entry = journal_line.journal_entry
      { on: entry.cash_date || entry.entry_date, memo: entry.memo.presence || BooksReport::KIND_LABELS.fetch(entry.kind, entry.kind.humanize), kind: BooksReport::KIND_LABELS.fetch(entry.kind, entry.kind.humanize) }
    end
  end
end
