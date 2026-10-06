# frozen_string_literal: true

module Manage
  # The wizard that creates and edits a deal on another show (TicketOffer),
  # built the way the contract and payout calculation wizards are: one page a
  # step, each saving and moving on, a review page to finish.
  #
  # Steps: buying (who it's offered to) → offer (what they get) → deal (how
  # much off) → review (the name, on/off, when it runs; save). State lives in
  # Rails.cache per user and organization, like the payout calculation wizard.
  # Edit re-enters the same wizard seeded from the record and opens on Review.
  class TicketOfferWizardController < Manage::TicketingBaseController
    STEPS = %w[buying offer deal review].freeze
    STEP_NAMES = { "buying" => "Who it's for", "offer" => "What they get", "deal" => "The deal", "review" => "Review" }.freeze

    before_action :load_state
    before_action :require_state, except: :start

    # GET deals/new, or deals/:id/edit (scoped to the organization).
    def start
      offer = params[:id].present? ? Current.organization.ticket_offers.find(params[:id]) : nil
      reset_state(from: offer)
      save_state
      redirect_to wizard_step_link(offer ? :review : :buying)
    end

    def buying; end

    def save_buying
      scope = params[:trigger_scope].to_s.presence_in(TicketOffer::TRIGGER_SCOPES) || "production"
      @state.merge!(trigger_scope: scope,
                    trigger_production_id: (params[:trigger_production_id].presence if scope == "production"),
                    trigger_listing_id: (params[:trigger_listing_id].presence if scope == "listing"))
      save_state
      redirect_to wizard_step_link(:offer)
    end

    def offer; end

    def save_offer
      scope = params[:target_scope].to_s.presence_in(TicketOffer::TARGET_SCOPES) || "same_night"
      @state.merge!(target_scope: scope,
                    target_production_id: (params[:target_production_id].presence if scope == "same_night"),
                    target_tier_name: (params[:target_tier_name].to_s.squish.presence if scope == "same_night"),
                    target_tier_id: (params[:target_tier_id].presence if scope == "listing"))
      save_state
      redirect_to wizard_step_link(:deal)
    end

    def deal; end

    def save_deal
      kind = params[:deal_kind].to_s.presence_in(TicketOffer::DEAL_KINDS) || "amount_off"
      @state.merge!(deal_kind: kind, amount: params[:amount].to_s.strip, percent: params[:percent].to_s.strip, price: params[:price].to_s.strip,
                    max_per_order: params[:max_per_order].to_s.strip, max_uses: params[:max_uses].to_s.strip)
      save_state
      redirect_to wizard_step_link(:review)
    end

    def review
      @offer = build_offer
      @offer.name = @offer.suggested_name if @offer.name.blank?
    end

    # The review page's own fields finish it; the record is made or changed
    # here and nowhere else.
    def save
      @state.merge!(name: params[:name].to_s.squish, active: params.fetch(:active, "1") == "1",
                    starts_at: params[:starts_at].to_s, ends_at: params[:ends_at].to_s,
                    after_purchase_days: params[:after_purchase_days].to_s)
      save_state
      @offer = build_offer
      if @offer.save
        clear_state
        redirect_to manage_ticket_offers_path, notice: "Saved #{@offer.name}#{' and on' if @offer.active?}."
      else
        render :review, status: :unprocessable_content
      end
    end

    def cancel
      clear_state
      redirect_to manage_ticket_offers_path, notice: "Nothing saved."
    end

    private

    # ---- the deal, from the state --------------------------------------------

    # The TicketOffer the state describes: the record being edited, or a new
    # one. The model checks every id is the organization's own.
    def build_offer
      offer = @state[:editing_id] ? Current.organization.ticket_offers.find(@state[:editing_id]) : Current.organization.ticket_offers.new
      offer.assign_attributes(
        trigger_scope: @state[:trigger_scope] || "production", trigger_production_id: @state[:trigger_production_id].presence,
        trigger_listing_id: @state[:trigger_listing_id].presence,
        target_scope: @state[:target_scope] || "same_night", target_production_id: @state[:target_production_id].presence,
        target_tier_name: @state[:target_tier_name].presence, target_tier_id: @state[:target_tier_id].presence,
        deal_kind: @state[:deal_kind] || "amount_off", amount_cents: dollars_to_cents(@state[:amount]),
        percent: @state[:percent].presence, price_cents: dollars_to_cents(@state[:price]),
        max_per_order: @state[:max_per_order].presence, max_uses: @state[:max_uses].presence
      )
      if @state.key?(:name)
        offer.assign_attributes(name: @state[:name], active: @state[:active], starts_at: @state[:starts_at].presence,
                                ends_at: @state[:ends_at].presence, after_purchase_days: @state[:after_purchase_days].presence || 2)
      end
      offer
    end
    helper_method :build_offer

    def dollars_to_cents(text)
      cleaned = text.to_s.delete("$,").strip
      cleaned.empty? ? nil : (BigDecimal(cleaned) * 100).round.to_i
    rescue ArgumentError
      nil
    end

    def wizard_step_link(step)
      public_send("manage_ticket_offer_wizard_#{step}_path")
    end
    helper_method :wizard_step_link

    # ---- state ---------------------------------------------------------------

    def load_state
      @state = (Rails.cache.read(cache_key) || {}).with_indifferent_access
    end
    helper_method :wizard_state

    def wizard_state
      @state
    end

    def require_state
      redirect_to wizard_step_link(:start) unless @state[:started]
    end

    def save_state
      Rails.cache.write(cache_key, @state.to_h, expires_in: 24.hours)
    end

    def clear_state
      Rails.cache.delete(cache_key)
    end

    def cache_key
      "ticket_offer_wizard:#{Current.user.id}:#{Current.organization.id}"
    end

    def reset_state(from: nil)
      @state = { started: true }.with_indifferent_access
      return unless from

      dollars = ->(cents) { cents.nil? ? "" : format("%.2f", cents / 100.0) }
      @state.merge!(editing_id: from.id, trigger_scope: from.trigger_scope, trigger_production_id: from.trigger_production_id,
                    trigger_listing_id: from.trigger_listing_id, target_scope: from.target_scope, target_production_id: from.target_production_id,
                    target_tier_name: from.target_tier_name, target_tier_id: from.target_tier_id, deal_kind: from.deal_kind,
                    amount: dollars.call(from.amount_cents), percent: from.percent.to_s, price: dollars.call(from.price_cents),
                    max_per_order: from.max_per_order.to_s, max_uses: from.max_uses.to_s, name: from.name, active: from.active,
                    starts_at: from.starts_at&.strftime("%Y-%m-%dT%H:%M").to_s, ends_at: from.ends_at&.strftime("%Y-%m-%dT%H:%M").to_s,
                    after_purchase_days: from.after_purchase_days.to_s)
    end
  end
end
