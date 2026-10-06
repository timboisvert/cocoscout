# frozen_string_literal: true

module Manage
  # Products sold with tickets (TicketProduct): the organization's list, each
  # with a standard price. Which productions upsell them, and at what price,
  # is set on each production's ticketing (its Products tab).
  class TicketProductsController < Manage::TicketingBaseController
    before_action :set_product, only: %i[edit update destroy]

    def index
      @products = Current.organization.ticket_products.active.ordered.to_a
      @offered_by = ProductionTicketingProduct.joins(:production_ticketing)
                                              .where(ticket_product_id: @products.map(&:id))
                                              .group(:ticket_product_id).count
    end

    def new
      @product = Current.organization.ticket_products.new(taxable: true)
    end

    def create
      @product = Current.organization.ticket_products.new(product_params)
      @product.position = (Current.organization.ticket_products.maximum(:position) || 0) + 1
      if @product.save
        redirect_to manage_ticket_products_path, notice: "Added #{@product.name}. Pick it on a production's Products tab to sell it."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      if @product.update(product_params)
        redirect_to manage_ticket_products_path, notice: "Saved #{@product.name}."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      name = @product.name
      @product.retire!
      redirect_to manage_ticket_products_path, notice: "#{name} removed. Orders that bought it keep it."
    end

    private

    # Scoped to the org: a bare find here would reach another theater's product.
    def set_product
      @product = Current.organization.ticket_products.active.find(params[:id])
    end

    # The price is typed as dollars.
    def product_params
      permitted = params.require(:ticket_product).permit(:name, :description, :price, :counts_toward_ticket_revenue, :taxable)
      price = permitted.delete(:price).to_s.delete("$,").strip
      permitted[:price_cents] = price.empty? ? 0 : (BigDecimal(price) * 100).round.to_i
      permitted[:description] = permitted[:description].presence
      permitted
    rescue ArgumentError
      raise ActionController::BadRequest, "Prices must be numbers"
    end
  end
end
