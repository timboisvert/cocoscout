# frozen_string_literal: true

module Manage
  # Money recorded by hand (Money → Books → Record money): one sheet with
  # three tabs (in, out, moved), a page per recorded entry, change and
  # remove. Books access, by the grid; changing needs manage.
  class MoneyRecordsController < Manage::ManageController
    include BankStatementStreams

    before_action :set_record, only: %i[show edit update destroy]
    before_action :require_change!, only: %i[new create edit update destroy]
    before_action :load_choices, only: %i[new create edit update]

    def new
      @kind = params[:kind].presence_in(MoneyRecord::KINDS) || "out"
      @records = { "in" => blank("in"), "out" => blank("out"), "move" => blank("move") }
      @records[@kind].assign_attributes(prefill)
    end

    def create
      @record = Current.organization.money_records.new(record_params.merge(recorded_by: Current.user))
      if @record.save
        if (line = bank_line)
          line.recorded!(@record)
          return respond_to do |format|
            # The bank page's Record this line modal: the row swaps, the modal resets.
            format.turbo_stream { bank_line_streams(line, reset_modal: true) }
            format.html { redirect_to manage_money_bank_path, notice: "Recorded. #{@record.kind_label}: #{helpers.number_to_currency(@record.amount)}, and the bank line is dealt with." }
          end
        end
        notice = "Recorded. #{@record.kind_label}: #{helpers.number_to_currency(@record.amount)}."
        return redirect_to safe_return_to, notice: notice if safe_return_to

        redirect_to manage_money_record_path(@record), notice: notice
      else
        @kind = @record.kind.presence_in(MoneyRecord::KINDS) || "out"
        if bank_line && request.format.turbo_stream?
          # Back into the bank page's modal, open, with what was typed.
          return render turbo_stream: turbo_stream.replace("bank-record-modal", partial: "manage/bank_statements/record_modal",
                                                           locals: bank_record_modal_locals(records: { @kind => @record }).merge(open_kind: @kind, bank_line: bank_line.id))
        end
        @records = { "in" => blank("in"), "out" => blank("out"), "move" => blank("move") }
        @records[@kind] = @record
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @entries = @record.journal_entries.includes(journal_lines: :ledger_account)
      @entry = @entries.find { |e| e.reversed_at.nil? && e.reversal_of_id.nil? }
    end

    def edit; end

    def update
      if @record.update(record_params.except(:kind))
        redirect_to manage_money_record_path(@record), notice: "Changed. The earlier entry was reversed, not edited."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @record.destroy!
      redirect_to manage_money_books_section_path(section: "entries"), notice: "Removed. The entry was reversed on the books."
    end

    private

    def set_record
      @record = Current.organization.money_records.find(params[:id])
    end

    def require_change!
      return if OrganizationAccess.allows?(Current.user, Current.organization, :books, :manage)

      redirect_to manage_money_books_path, alert: "You can look at the books but not change them."
    end

    def load_choices
      @productions = Current.organization.productions.active.order(:name)
      @shows = Show.where(production_id: @productions.map(&:id), canceled: false)
                      .order(date_and_time: :desc).limit(400).select(:id, :production_id, :date_and_time, :secondary_name)
    end

    def blank(kind)
      MoneyRecord.blank_for(Current.organization, kind)
    end

    # The bank line this record settles, when it comes from the bank page.
    def bank_line
      return @bank_line if defined?(@bank_line)

      @bank_line = params[:bank_line].present? ? Current.organization.bank_statement_lines.find_by(id: params[:bank_line]) : nil
    end

    # The Record money modal sends the page it was opened on; only a Books
    # page of ours, never another site.
    def safe_return_to
      path = params[:return_to].to_s
      path if path.start_with?("/manage/money/books") && !path.start_with?("//")
    end

    # A link from elsewhere (the bank page's "Record it") can bring the
    # amount, date and memo along.
    def prefill
      params.permit(:amount, :on, :memo, :counterparty, :category_key, :production_id, :show_id).to_h.compact_blank
    end

    def record_params
      params.require(:money_record).permit(:kind, :on, :amount, :category_key, :counterparty, :production_id, :show_id,
                                           :via, :from_account, :to_account, :memo, :receipt)
    end
  end
end
