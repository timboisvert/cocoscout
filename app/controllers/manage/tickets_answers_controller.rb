# frozen_string_literal: true

module Manage
  # The Tickets question (Round 9 §3): where people get tickets for a
  # production, answered once from its page (or the show page, or the
  # wizards) and applied by TicketsAnswer. A date can point somewhere else
  # than its production (ShowsController, Tickets tab). For the organization's
  # owners and managers on Pro (the tab is Pro's).
  class TicketsAnswersController < Manage::ManageController
    before_action :ensure_org_owner_or_manager
    before_action :set_production

    # PATCH /manage/productions/:id/tickets
    def update
      t = params.fetch(:tickets, {}).to_unsafe_h
      tiers = t["tiers"].is_a?(Hash) ? t["tiers"].values : Array(t["tiers"])
      result = TicketsAnswer.apply!(@production, mode: t["mode"], url: t["url"], tiers: tiers, fee_mode: t["fee_mode"],
                                    schedule_mode: t["schedule_mode"], opens_days_before: t["opens_days_before"])
      if result.needs_prices
        return redirect_to manage_edit_production_ticketing_path(@production, section: "tickets"),
                           notice: "#{@production.name} will sell on CocoScout. Set its ticket types and prices here, then turn it on."
      end

      notice = case result.mode
      when "cocoscout" then "#{@production.name} is on sale on CocoScout. Share cocoscout.com#{ShortLink.canonical_for!(@production).short_path}."
      when "elsewhere" then "Tickets for #{@production.name} are on #{result.site}."
      else "No tickets for #{@production.name}."
      end
      redirect_to back_path, notice: notice
    rescue TicketsAnswer::Error, ActiveRecord::RecordInvalid => e
      redirect_to back_path, alert: (e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : e.message)
    end

    private

    # Scoped to the organization: a bare find would reach another organization's production.
    def set_production
      @production = Current.organization.productions.find(params[:production_id] || params[:id])
    end

    # Back to the page the card was on, when it's one of ours.
    def back_path
      default = manage_production_path(@production)
      to = params[:return_to].to_s
      to.start_with?("/") && !to.start_with?("//") ? to : default
    end
  end
end
