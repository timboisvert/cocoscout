# frozen_string_literal: true

module Manage
  # Passes (TicketPass): several shows sold together, the organization's list,
  # an editor (the shows, the ticket type at each, the price and how it splits
  # between them) and a page per pass with its sales.
  class TicketPassesController < Manage::TicketingBaseController
    before_action :set_pass, only: %i[show edit update destroy refund_holding]

    def index
      @passes = Current.organization.ticket_passes.order(created_at: :desc).to_a
    end

    def new
      @pass = Current.organization.ticket_passes.new(split: "regular_price", kind: "dated")
      2.times { @pass.pass_shows.build }
      @pass.coverages.build
    end

    def create
      @pass = Current.organization.ticket_passes.new(pass_params)
      if @pass.save
        redirect_to manage_ticket_pass_path(@pass), notice: "#{@pass.name} saved#{' and on sale' if @pass.status == 'on_sale'}."
      else
        @pass.pass_shows.build while @pass.pass_shows.size < 2
        @pass.coverages.build if @pass.coverages.empty?
        render :new, status: :unprocessable_content
      end
    end

    def show
      if @pass.credit_kind?
        @holdings = @pass.holdings.where(status: %w[active ended canceled]).order(paid_at: :desc).to_a
        return render(:credits)
      end

      @rows = @pass.rows
      @shares = @pass.shares(@rows)
      @sold = @pass.sold_count(@rows)
      @remaining = @pass.remaining(@rows)
      @money_by_listing = @pass.tickets.where(status: Ticket::SOLD_STATUSES).group(:ticket_listing_id)
                               .sum("tickets.price_cents - tickets.discount_cents")
    end

    def edit
      @pass.pass_shows.build if @pass.pass_shows.size < 2
      @pass.coverages.build if @pass.coverages.empty?
    end

    def update
      if @pass.update(pass_params)
        redirect_to manage_ticket_pass_path(@pass), notice: "Saved #{@pass.name}."
      else
        render :edit, status: :unprocessable_content
      end
    end

    # A pass nobody bought is deleted; one that sold is closed, so its
    # buyers' tickets keep their pass.
    def destroy
      name = @pass.name
      if @pass.tickets.exists? || @pass.holdings.exists?
        @pass.update_columns(status: "closed", updated_at: Time.current)
        redirect_to manage_ticket_passes_path, notice: "#{name} is closed. Its buyers keep their tickets."
      else
        @pass.destroy!
        redirect_to manage_ticket_passes_path, notice: "#{name} deleted."
      end
    end

    # A credit pass nobody used yet, refunded in full (TicketPassCredits.refund!).
    def refund_holding
      holding = @pass.holdings.find(params[:holding_id])
      TicketPassCredits.refund!(holding, by: Current.user)
      redirect_to manage_ticket_pass_path(@pass), notice: "Refunded #{helpers.number_to_currency(holding.refunded_cents / 100.0)} to #{holding.holder_name.presence || 'the buyer'}."
    rescue TicketPassCredits::Error => e
      redirect_to manage_ticket_pass_path(@pass), alert: e.message
    end

    private

    # Scoped to the org: a bare find here would reach another theater's pass.
    def set_pass
      @pass = Current.organization.ticket_passes.find(params[:id])
    end

    # Prices and shares are typed as dollars; a show can only be one of this
    # organization's own ticket types.
    def pass_params
      permitted = params.require(:ticket_pass).permit(:name, :slug, :description, :price, :split, :status, :max_sold, :max_per_order,
                                                      :sales_end_at, :wide_image, :kind, :credits, :ends_on,
                                                      pass_shows_attributes: %i[id ticket_tier_id share _destroy],
                                                      coverages_attributes: %i[id production_id tier_name _destroy])
      permitted[:credits] = permitted[:credits].presence if permitted.key?(:credits)
      permitted[:ends_on] = permitted[:ends_on].presence if permitted.key?(:ends_on)
      own_productions = Current.organization.productions.select(:id)
      coverage_rows = permitted[:coverages_attributes]
      coverage_rows&.keys&.each do |key|
        row = coverage_rows[key]
        row[:production_id] = nil if row[:production_id].present? && !own_productions.exists?(id: row[:production_id])
      end
      permitted[:price_cents] = dollars_to_cents(permitted.delete(:price))
      permitted[:max_sold] = permitted[:max_sold].presence
      permitted[:max_per_order] = permitted[:max_per_order].presence
      permitted[:sales_end_at] = permitted[:sales_end_at].presence
      permitted[:description] = permitted[:description].presence
      own_tiers = TicketTier.joins(:ticket_listing).where(ticket_listings: { organization_id: Current.organization.id }).select(:id)
      rows = permitted[:pass_shows_attributes]
      rows&.keys&.each do |key|
        row = rows[key]
        row[:ticket_tier_id] = nil if row[:ticket_tier_id].present? && !own_tiers.exists?(id: row[:ticket_tier_id])
        share = row.delete(:share)
        row[:share_cents] = share.present? ? dollars_to_cents(share) : nil
      end
      permitted
    end

    def dollars_to_cents(text)
      cleaned = text.to_s.delete("$,").strip
      cleaned.empty? ? 0 : (BigDecimal(cleaned) * 100).round.to_i
    rescue ArgumentError
      raise ActionController::BadRequest, "Prices must be numbers"
    end
  end
end
