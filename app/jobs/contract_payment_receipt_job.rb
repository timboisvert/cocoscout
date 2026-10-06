# frozen_string_literal: true

# A receipt to whoever paid a contract payment, online or recorded by hand:
# their invoice marked PAID, attached. Sent once (ContractInvoice
# #receipt_emailed_at); a payer with no email gets none.
class ContractPaymentReceiptJob < ApplicationJob
  queue_as :default

  def perform(contract_payment_id)
    payment = ContractPayment.find_by(id: contract_payment_id)
    return unless payment&.status_paid? && payment.invoiceable?

    ContractInvoiceDelivery.send_receipt!(ContractInvoice.for!(payment))
  end
end
