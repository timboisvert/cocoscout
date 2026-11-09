# frozen_string_literal: true

# A receipt to whoever paid a contract payment, online or recorded by hand:
# their invoice marked PAID, attached. Sent once (Invoice
# #receipt_emailed_at); a payer with no email gets none.
class ContractPaymentReceiptJob < ApplicationJob
  queue_as :default

  def perform(contract_payment_id)
    payment = ContractPayment.find_by(id: contract_payment_id)
    return unless payment&.status_paid? && payment.invoiceable?

    InvoiceDelivery.send_receipt!(Invoice.for!(payment))
  end
end
