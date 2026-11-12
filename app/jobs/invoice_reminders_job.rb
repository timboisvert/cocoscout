# frozen_string_literal: true

# Every morning: the reminders an invoice was set to send by itself
# (Invoice::REMINDERS, chosen when it's written): three days before it's
# due, and once when it's overdue. Until 2026-11-09 the choice was offered
# and shown on the invoice and nothing sent them.
#
# Which invoice is owed one today is Invoice#reminder_due?, read in the
# organization's own time zone: only one that was emailed to them, is still
# open, and hasn't been sent since the reminder's day came (a manager's own
# Send counts as the reminder). An invoice written by the organization
# only; a contract payment's is sent by hand from Money → Incoming.
class InvoiceRemindersJob < ApplicationJob
  queue_as :default

  def perform
    Organization.where(id: candidates.select(:organization_id)).find_each do |organization|
      TimeZones.use(organization.time_zone) do
        today = Date.current
        candidates.where(organization: organization).find_each { |invoice| remind(invoice, today) }
      end
    end
  end

  private

  # A day of slack either side of the two windows, for the zones.
  def candidates
    Invoice.standalone.open.where.not(reminders: "none").where("sent_count > 0")
           .where(due_on: (Date.current - Invoice::REMIND_OVERDUE_WITHIN - 1)..(Date.current + Invoice::REMIND_BEFORE + 1))
  end

  def remind(invoice, today)
    invoice.with_lock do
      InvoiceDelivery.send_invoice!(invoice) if invoice.reminder_due?(today)
    end
  rescue StandardError => e
    Rails.logger.error("[InvoiceRemindersJob] invoice #{invoice.id}: #{e.class}: #{e.message}")
  end
end
