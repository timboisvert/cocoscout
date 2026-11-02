# frozen_string_literal: true

module Manage
  # Money → Books → Bank (plan D3, §9.13): the transactions as the bank knows
  # them, each one matched to something on the books, recorded, or ignored
  # in place: an action on a line answers with a Turbo Stream that swaps its
  # row (BankStatementStreams), and Record it fills a modal on the page.
  # A statement comes in as a file from the modal; it is read once, here,
  # never kept, and its lines are matched in BankStatementMatchJob, which
  # tells the person when it's done. Books access, by the grid; changing
  # needs manage.
  class BankStatementsController < Manage::ManageController
    include BooksCategoriesGate
    include BankStatementStreams

    PER_PAGE = 100

    before_action :require_change!, only: %i[create match match_all ignore reopen destroy]
    before_action :set_line, only: %i[match ignore reopen]

    def show
      org = Current.organization
      @summary = BankStatementSummary.new(org)
      @month = params[:month].to_s[/\A\d{4}-\d{2}\z/]
      @kind = params[:kind].presence_in(%w[in out])
      scope = org.bank_statement_lines.to_deal_with
      scope = scope.where(on: Date.parse("#{@month}-01").all_month) if @month
      scope = scope.where(@kind == "in" ? "amount_cents > 0" : "amount_cents < 0") if @kind
      @pagy, @lines = pagy(scope, limit: PER_PAGE)
      @candidates = BankStatementSummary.candidates_for(org, @lines)
      @hints = BankStatementSummary.hints_for(org, @lines)
      @recent_done = org.bank_statement_lines.done.order(updated_at: :desc).limit(8).includes(:money_record).to_a
      @done_count = org.bank_statement_lines.done.count
      @rules = org.bank_rules.includes(:production).order(:id).to_a
      return unless OrganizationAccess.allows?(Current.user, org, :books, :manage)

      @modal = bank_record_modal_locals
      # What each rule would catch now, and the rules the lines suggest.
      waiting = org.bank_statement_lines.to_deal_with.to_a
      @rule_catches = @rules.to_h { |rule| [ rule.id, waiting.count { |line| rule.matches?(line) } ] }
      @suggestions = BankRuleSuggestions.for(org)
    end

    # The upload. The file's text is read out of the request and parsed
    # while you wait, its lines are saved, and the matching runs in a job.
    # The temp file Rack made goes with the request.
    def create
      upload = params[:file]
      return redirect_to manage_money_bank_path, alert: "Choose the file first." if upload.blank? || !upload.respond_to?(:read)
      return redirect_to manage_money_bank_path, alert: "That file is too large. A month from the bank is well under 5 MB." if upload.size.to_i > 5.megabytes

      org = Current.organization
      result = BankStatementParser.parse(upload.read, filename: upload.original_filename)
      rows = result.lines.map do |l|
        fingerprint = l[:fitid].present? ? "fitid:#{l[:fitid]}"[0, 60] : BankStatementLine.fingerprint_for(l[:on], l[:amount_cents], l[:description], l[:seq])
        { organization_id: org.id, on: l[:on], amount_cents: l[:amount_cents], description: l[:description].to_s[0, 255], fingerprint: fingerprint,
          description_key: BankStatementLine.description_key_for(l[:description]) }
      end
      already = org.bank_statement_lines.where(fingerprint: rows.map { |r| r[:fingerprint] }).pluck(:fingerprint).to_set
      rows.reject! { |r| already.include?(r[:fingerprint]) }
      import = nil
      BankStatementImport.transaction do
        import = org.bank_statement_imports.create!(imported_by: Current.user, filename: File.basename(upload.original_filename.to_s), format: result.format,
                                                    from_on: result.lines.map { |l| l[:on] }.min, to_on: result.lines.map { |l| l[:on] }.max,
                                                    lines_count: result.lines.size, new_lines_count: rows.size, status: "matching",
                                                    closing_balance_cents: result.closing_balance_cents, closing_on: result.closing_on,
                                                    opening_balance_cents: result.opening_balance_cents, opening_on: result.opening_on)
        BankStatementLine.insert_all(rows.map { |r| r.merge(bank_statement_import_id: import.id) }) if rows.any?
      end
      BankStatementMatchJob.perform_later(import.id)
      skipped = result.lines.size - rows.size
      redirect_to manage_money_bank_path, notice: "#{pluralize_lines(result.lines.size)} read#{skipped.positive? ? ", #{skipped} already in" : ''}. " \
                                                  "We're matching them to the books now; you'll get a notification when it's done. The file is gone."
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
      lines = if params[:journal_line_id].present?
        JournalLine.where(id: params[:journal_line_id], organization: Current.organization).to_a
      else
        @line.journal_lines.to_a
      end
      return redirect_to back_path, alert: "Pick the line on the books it matches." if lines.empty?

      @line.match!(lines)
      answer "Matched."
    end

    # Every suggestion confirmed at once.
    def match_all
      lines = Current.organization.bank_statement_lines.where(state: "suggested").to_a
      lines.each { |line| line.match!(line.journal_lines.to_a) }
      redirect_to back_path, notice: "#{pluralize_lines(lines.size)} matched."
    end

    def ignore
      @line.ignore!
      answer "Ignored. It stays in the list of what you have dealt with."
    end

    def reopen
      @line.reopen!
      answer "Back in the list."
    end

    # A statement and its lines, gone. Money recorded from its lines stays
    # on the books; the lines were only the bank's side of it.
    def destroy
      import = Current.organization.bank_statement_imports.find(params[:id])
      title = import.title
      import.destroy!
      redirect_to manage_money_bank_path, notice: "#{title} removed. Money you recorded from it stays on the books."
    end

    private

    def set_line
      @line = Current.organization.bank_statement_lines.find(params[:id])
    end

    def require_change!
      return if OrganizationAccess.allows?(Current.user, Current.organization, :books, :manage)

      redirect_to manage_money_bank_path, alert: "You can look at the bank page but not change it."
    end

    # After an action on a line: the row swaps in place (Turbo), or the page
    # comes back with its filters.
    def answer(notice)
      respond_to do |format|
        format.turbo_stream { bank_line_streams(@line) }
        format.html { redirect_to back_path, notice: notice }
      end
    end

    def back_path
      manage_money_bank_path(bank_filters)
    end

    def pluralize_lines(n) = "#{n} #{n == 1 ? 'line' : 'lines'}"
  end
end
