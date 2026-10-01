# frozen_string_literal: true

module Manage
  # Ticketing's home: what needs doing before (and while) the theater sells.
  class TicketingController < Manage::TicketingBaseController
    def index
      @tax = TicketTaxSetting.current(Current.organization)
    end
  end
end
