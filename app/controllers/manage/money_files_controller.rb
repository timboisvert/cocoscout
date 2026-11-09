# frozen_string_literal: true

module Manage
  # A money document (a bill, a receipt, a W-9, a statement) served only to
  # someone the organization's access grid lets in: the link checks who is
  # asking, then hands over a short-lived address for the file itself.
  # Headshots and posters are shown publicly on purpose and don't come here.
  class MoneyFilesController < Manage::ManageController
    RECORDS = {
      "Bill" => :bills_invoices, "MoneyRecord" => :books, "ExpenseItem" => :settle_up, "W9Submission" => :staffing, "OrgStatement" => :books, "BooksDownload" => :books
    }.freeze

    def show
      # Attachments aren't scoped by organization; the record they hang off
      # is, and the next line refuses one from another organization.
      attachment = ActiveStorage::Attachment.find(params[:id]) # rubocop:disable CocoScout/UnscopedFind
      record = attachment.record
      module_key = RECORDS[attachment.record_type]
      return head :not_found unless module_key && record && organization_of(record)&.id == Current.organization.id
      return head :forbidden unless OrganizationAccess.allows?(Current.user, Current.organization, module_key, :view)

      blob = attachment.blob
      ActiveStorage::Current.url_options = { host: request.host, port: request.optional_port, protocol: request.protocol }
      if params[:variant].present? && blob.image?
        redirect_to blob.variant(resize_to_limit: [ 800, 800 ]).processed.url(expires_in: 5.minutes), allow_other_host: true
      else
        redirect_to blob.url(expires_in: 5.minutes, disposition: (params[:download] == "1" ? "attachment" : "inline")), allow_other_host: true
      end
    end

    private

    def organization_of(record)
      return record.organization if record.respond_to?(:organization)

      record.show_financials&.show&.production&.organization if record.is_a?(ExpenseItem)
    end
  end
end
