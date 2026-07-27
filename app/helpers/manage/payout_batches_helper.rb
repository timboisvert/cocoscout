# frozen_string_literal: true

module Manage
  module PayoutBatchesHelper
    # Trace a payout contribution back to the record that created it, so a manager
    # can click a line inside a run and land on the show / advance / contract /
    # course it came from — and keep tracing from there. Returns nil when the
    # source can't be linked (the caller renders plain text in that case).
    def payout_contribution_source_path(contribution)
      source = contribution.source
      return nil if source.nil?

      case source
      when ShowPayoutLineItem
        show = source.show_payout&.show
        show && manage_money_show_payout_path(show)
      when PersonAdvance
        source.production && manage_money_advance_path(source.production, source)
      when ContractPayment
        source.contract && manage_contract_path(source.contract)
      when CourseOfferingPayout
        manage_course_offering_payout_path(source.course_offering)
      when CourseOfferingPayoutLineItem
        source.course_offering && manage_course_offering_payout_path(source.course_offering)
      end
    end
  end
end
