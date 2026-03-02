# frozen_string_literal: true

class CourseOfferingStripeService
  class StripeError < StandardError; end

  def initialize(course_offering)
    @offering = course_offering
  end

  # Create or update Stripe product and price(s) for the course offering
  # Called when an offering is published (status → open)
  def ensure_stripe_resources!
    create_or_update_product!
    create_or_update_prices!
  end

  private

  def create_or_update_product!
    if @offering.stripe_product_id.present?
      # Update existing product
      Stripe::Product.update(@offering.stripe_product_id, product_params)
    else
      # Create new product
      product = Stripe::Product.create(product_params.merge(
        metadata: {
          course_offering_id: @offering.id,
          production_id: @offering.production_id
        }
      ))
      @offering.update!(stripe_product_id: product.id)
    end
  rescue Stripe::StripeError => e
    raise StripeError, "Failed to create/update Stripe product: #{e.message}"
  end

  def create_or_update_prices!
    # Regular price — Stripe prices are immutable, so create new one if price changed
    if @offering.stripe_price_id.blank? || price_changed?(:regular)
      # Archive old price if it exists
      archive_price(@offering.stripe_price_id) if @offering.stripe_price_id.present?

      price = Stripe::Price.create(
        product: @offering.stripe_product_id,
        unit_amount: @offering.price_cents,
        currency: @offering.currency,
        metadata: { type: "regular" }
      )
      @offering.update!(stripe_price_id: price.id)
    end

    # Early bird price
    if @offering.early_bird_price_cents.present?
      if @offering.stripe_early_bird_price_id.blank? || price_changed?(:early_bird)
        archive_price(@offering.stripe_early_bird_price_id) if @offering.stripe_early_bird_price_id.present?

        early_bird_price = Stripe::Price.create(
          product: @offering.stripe_product_id,
          unit_amount: @offering.early_bird_price_cents,
          currency: @offering.currency,
          metadata: { type: "early_bird" }
        )
        @offering.update!(stripe_early_bird_price_id: early_bird_price.id)
      end
    end
  rescue Stripe::StripeError => e
    raise StripeError, "Failed to create/update Stripe prices: #{e.message}"
  end

  def product_params
    {
      name: @offering.title,
      description: "Course: #{@offering.title} — #{@offering.production.organization.name}"
    }
  end

  def archive_price(price_id)
    Stripe::Price.update(price_id, active: false)
  rescue Stripe::StripeError
    # Non-critical — old price can stay active
  end

  def price_changed?(type)
    # Compare current offering price with what Stripe has
    price_id = type == :regular ? @offering.stripe_price_id : @offering.stripe_early_bird_price_id
    return true if price_id.blank?

    begin
      stripe_price = Stripe::Price.retrieve(price_id)
      expected = type == :regular ? @offering.price_cents : @offering.early_bird_price_cents
      stripe_price.unit_amount != expected || stripe_price.currency != @offering.currency
    rescue Stripe::StripeError
      true
    end
  end
end
