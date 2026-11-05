# frozen_string_literal: true

# Superadmin Finances, Costs: what CocoScout costs to run that never passes
# through Stripe (Amazon, Claude, anything else Coco Runs Everything pays
# for it). Bills are uploaded as PDFs and read (CompanyBillReader), checked
# against the PDF, then counted in Spent and Profit on the CocoScout page.
#
#   /superadmin/finances/costs            the year, month by month, and every bill
#   /superadmin/finances/costs/export     the year for the CPA (CSV)
#   /superadmin/finances/costs/receipts   the year's receipts in one zip
#
# CocoScout only: the company's other business is not on these pages.
module Superadmin
  class CostsController < FinancesController
    MAX_UPLOAD_BYTES = 15.megabytes
    UPLOAD_TYPES = %w[application/pdf image/png image/jpeg image/heic image/webp].freeze

    before_action :set_year, only: %i[index export receipts]
    before_action :set_expense, only: %i[update destroy document]

    def index
      @to_check = CompanyExpense.to_check.with_attached_documents.order(:created_at, :id).to_a
      @bills = CompanyExpense.confirmed.for_year(@year).with_attached_documents.newest_first.to_a
      @years = CompanyExpense.years
      @vendors = @bills.group_by(&:vendor).sort_by { |_, bills| -bills.sum(&:amount_cents) }.map(&:first)
      last = @year == Date.current.year ? Date.current.month : 12
      @months = (1..last).map { |month| Date.new(@year, month, 1) }
      @by_month = @bills.group_by(&:period_month)
      @missing = CompanyExpense.missing_months(@year)
      @known_vendors = CompanyExpense.distinct.order(:vendor).pluck(:vendor)
    end

    # Any number of PDFs at once. Each becomes a bill to check: what was read
    # off it is filled in, and it counts once it's confirmed.
    def upload
      files = Array(params[:files]).select { |file| file.respond_to?(:tempfile) }
      if files.empty?
        redirect_to finances_costs_path, alert: "Choose one or more bills to upload."
        return
      end

      read = []
      skipped = []
      files.each do |file|
        problem = upload_problem(file)
        next skipped << "#{file.original_filename} (#{problem})" if problem

        result = file.content_type == "application/pdf" ? CompanyBillReader.read(file.tempfile, filename: file.original_filename) :
                                                           CompanyBillReader.from_text("", filename: file.original_filename)
        attrs = result.attributes
        if attrs[:bill_number] && CompanyExpense.exists?(vendor: attrs[:vendor], bill_number: attrs[:bill_number])
          next skipped << "#{file.original_filename} (#{attrs[:vendor]} #{attrs[:bill_number]} is already here)"
        end

        expense = CompanyExpense.new(attrs.merge(paid_by: paid_by_param, share_percent: share_param))
        file.tempfile.rewind
        expense.documents.attach(io: file.tempfile, filename: file.original_filename, content_type: file.content_type)
        expense.save ? read << expense : skipped << "#{file.original_filename} (#{expense.errors.full_messages.to_sentence})"
      end

      notice = "Read #{helpers.pluralize(read.size, 'bill')}. Check #{read.one? ? 'it' : 'each'} against its PDF, then confirm." if read.any?
      alert = "Not added: #{skipped.join('; ')}." if skipped.any?
      redirect_to finances_costs_path, notice: notice, alert: alert
    end

    # A cost typed in by hand: counted straight away.
    def create
      expense = CompanyExpense.new(expense_params.merge(confirmed_at: Time.current))
      attach_documents(expense)
      if expense.save
        redirect_to finances_costs_path(year: expense.period_month.year), notice: "Added #{expense.vendor}, #{helpers.usd(expense.amount_cents)} for #{expense.period_month.strftime('%B %Y')}."
      else
        redirect_to finances_costs_path, alert: "That cost wasn't added: #{expense.errors.full_messages.to_sentence}."
      end
    end

    # Correct a bill; with confirm, it starts counting.
    def update
      @expense.assign_attributes(expense_params)
      @expense.confirmed_at ||= Time.current if params[:confirm].present?
      attach_documents(@expense)
      if @expense.save
        year = @expense.period_month&.year
        redirect_to finances_costs_path(year: (year unless year == Date.current.year)),
                    notice: params[:confirm].present? ? "Confirmed #{@expense.vendor}, #{helpers.usd(@expense.amount_cents)} for #{@expense.period_month.strftime('%B %Y')}. It now counts." : "Saved."
      else
        redirect_to finances_costs_path, alert: "#{@expense.vendor || 'That bill'} wasn't saved: #{@expense.errors.full_messages.to_sentence}."
      end
    end

    # Confirm every uploaded bill that has its amount and its month.
    def confirm_all
      ready, not_ready = CompanyExpense.to_check.partition { |expense| expense.bill_total_cents.positive? && expense.period_month }
      ready.each { |expense| expense.update!(confirmed_at: Time.current) }
      left = " #{helpers.pluralize(not_ready.size, 'bill')} still #{not_ready.one? ? 'needs' : 'need'} an amount or a month." if not_ready.any?
      redirect_to finances_costs_path, notice: "Confirmed #{helpers.pluralize(ready.size, 'bill')}, #{helpers.usd(ready.sum(&:amount_cents))} in all.#{left}"
    end

    def destroy
      @expense.destroy!
      redirect_to finances_costs_path, notice: "Removed #{@expense.vendor}#{" #{@expense.bill_number}" if @expense.bill_number}."
    end

    # One of a bill's files, behind the superadmin sign-in.
    def document
      attachment = @expense.documents.find { |doc| doc.id == params[:attachment_id].to_i }
      return head :not_found unless attachment

      send_data attachment.download, filename: attachment.filename.to_s, type: attachment.content_type, disposition: "inline"
    end

    def export
      send_data CompanyExpenseExport.csv(@year), filename: CompanyExpenseExport.basename(@year) + ".csv", type: "text/csv"
    end

    def receipts
      send_data CompanyExpenseExport.zip(@year), filename: CompanyExpenseExport.basename(@year) + " with receipts.zip", type: "application/zip"
    end

    private

    def set_year
      @year = params[:year].to_s.match?(/\A20\d\d\z/) ? params[:year].to_i : Date.current.year
    end

    def set_expense
      @expense = CompanyExpense.find(params[:id])
    end

    def upload_problem(file)
      return "not a PDF or an image" unless UPLOAD_TYPES.include?(file.content_type)
      return "over 15 MB" if file.size > MAX_UPLOAD_BYTES

      checksum = Digest::MD5.file(file.tempfile.path).base64digest
      "this file is already here" if ActiveStorage::Attachment.joins(:blob).where(record_type: "CompanyExpense", active_storage_blobs: { checksum: checksum }).exists?
    end

    def attach_documents(expense)
      Array(params[:files]).select { |file| file.respond_to?(:tempfile) }.each do |file|
        next if upload_problem(file)

        expense.documents.attach(io: file.tempfile, filename: file.original_filename, content_type: file.content_type)
      end
    end

    def paid_by_param
      CompanyExpense::PAID_BY.key?(params[:paid_by]) ? params[:paid_by] : "company"
    end

    def share_param
      share = params[:share_percent].to_s.delete("%").strip
      share.match?(/\A\d+(\.\d+)?\z/) ? share.to_d : 100
    end

    # The form's dollars and "2026-10" month, as the model keeps them.
    def expense_params
      raw = params.fetch(:company_expense, {}).permit(:vendor, :category, :description, :bill_number, :bill_total, :share_percent,
                                                      :period_month, :billed_on, :paid_on, :paid_by, :note)
      attrs = raw.slice(:vendor, :category, :description, :bill_number, :paid_by, :note).to_h
      attrs[:bill_total_cents] = (raw[:bill_total].to_s.delete("$, ").to_d * 100).round.to_i if raw.key?(:bill_total)
      attrs[:share_percent] = raw[:share_percent].to_s.delete("% ").presence&.to_d || 100 if raw.key?(:share_percent)
      attrs[:period_month] = parse_month(raw[:period_month]) if raw.key?(:period_month)
      attrs[:billed_on] = parse_day(raw[:billed_on]) if raw.key?(:billed_on)
      attrs[:paid_on] = parse_day(raw[:paid_on]) if raw.key?(:paid_on)
      attrs
    end

    def parse_month(value)
      value.to_s.match?(/\A\d{4}-\d{2}\z/) ? Date.strptime(value.to_s, "%Y-%m") : parse_day(value)&.beginning_of_month
    rescue Date::Error
      nil
    end

    def parse_day(value)
      value.present? ? Date.iso8601(value.to_s) : nil
    rescue Date::Error
      nil
    end
  end
end
