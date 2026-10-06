# frozen_string_literal: true

module Manage
  # Passes (TicketPass): several shows sold together, the organization's list,
  # an editor (the shows, the ticket type at each, the price and how it splits
  # between them) and a page per pass with its sales.
  class TicketPassesController < Manage::TicketingBaseController
    before_action :set_pass, only: %i[show edit update destroy]

    def index
      @passes = Current.organization.ticket_passes.order(created_at: :desc).to_a
    end

    def new
      @pass = Current.organization.ticket_passes.new(split: "regular_price")
      2.times { @pass.pass_shows.build }
    end

    def create
      @pass = Current.organization.ticket_passes.new(pass_params)
      if @pass.save
        redirect_to manage_ticket_pass_path(@pass), notice: "#{@pass.name} saved#{' and on sale' if @pass.status == 'on_sale'}."
      else
        @pass.pass_shows.build while @pass.pass_shows.size < 2
        render :new, status: :unprocessable_content
      end
    end

    def show
      @rows = @pass.rows
      @shares = @pass.shares(@rows)
      @sold = @pass.sold_count(@rows)
      @remaining = @pass.remaining(@rows)
      @money_by_listing = @pass.tickets.where(status: Ticket::SOLD_STATUSES).group(:ticket_listing_id)
                               .sum("tickets.price_cents - tickets.discount_cents")
    end

    def edit
      @pass.pass_shows.build if @pass.pass_shows.size < 2
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
      if @pass.tickets.exists?
        @pass.update_columns(status: "closed", updated_at: Time.current)
        redirect_to manage_ticket_passes_path, notice: "#{name} is closed. Its buyers keep their tickets."
      else
        @pass.destroy!
        redirect_to manage_ticket_passes_path, notice: "#{name} deleted."
      end
    end

    private

    # The ticket types a pass can include, grouped by production: every
    # upcoming date's plain types ("Fri Oct 10, 7:30 PM · General, $20.00").
    def tier_choices
      listings = Current.organization.ticket_listings.joins(:show).includes(:production, :show, :ticket_tiers)
                        .where.not(status: %w[canceled closed]).where(shows: { canceled: false })
                        .where("shows.date_and_time > ?", Time.current).order("shows.date_and_time")
      listings.group_by { |listing| listing.production&.name || "Other" }.map do |production, dates|
        options = dates.flat_map do |listing|
          listing.ticket_tiers.select { |tier| tier.archived_at.nil? && !tier.bundle? }.map do |tier|
            [ "#{listing.show.date_and_time.strftime('%a %b %-d, %-l:%M %p')} · #{tier.name}, #{helpers.number_to_currency(tier.price_cents / 100.0)}", tier.id ]
          end
        end
        [ production, options ]
      end
    end
    helper_method :tier_choices

    # Scoped to the org: a bare find here would reach another theater's pass.
    def set_pass
      @pass = Current.organization.ticket_passes.find(params[:id])
    end

    # Prices and shares are typed as dollars; a show can only be one of this
    # organization's own ticket types.
    def pass_params
      permitted = params.require(:ticket_pass).permit(:name, :slug, :description, :price, :split, :status, :max_sold, :max_per_order,
                                                      :sales_end_at, :wide_image,
                                                      pass_shows_attributes: %i[id ticket_tier_id share _destroy])
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
