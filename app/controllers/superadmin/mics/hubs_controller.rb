# frozen_string_literal: true

# Superadmin UI for managing city hubs and city captains.
#  * Promote/draft/archive a hub
#  * Rename, slug, intro copy
#  * Add/remove captains (CityHubMembership role=editor)
#  * One-click "roll up" — assign all venues in the hub's headline
#    city/state to this hub so the captain's authority covers them
module Superadmin
  module Mics
    class HubsController < ApplicationController
      before_action :require_superadmin
      before_action :hide_sidebar
      before_action :load_hub, except: [ :index, :create ]

      def hide_sidebar
        @show_my_sidebar = false
        @show_manage_sidebar = false
        @show_manage_header_only = false
        @show_group_sidebar = false
        @show_account_sidebar = false
      end

      def index
        @hubs = CityHub.order(:state, :name)
        @top_vote_cities = CityVote.tallies(limit: 20)
        @total_votes = CityVote.count
      end

      def create
        @hub = CityHub.new(hub_params)
        if @hub.save
          redirect_to mics_hub_path(@hub.slug), notice: "Hub created."
        else
          @hubs = CityHub.order(:state, :name)
          flash.now[:alert] = @hub.errors.full_messages.to_sentence
          render :index, status: :unprocessable_content
        end
      end

      def show
        @editors = @hub.memberships.where(role: CityHubMembership.roles[:editor])
                       .includes(:user).order("users.email_address")
        @mic_count = Mic.in_hub(@hub).count
        @active_count = Mic.active.in_hub(@hub).count
        @unclaimed_count = Mic.active.in_hub(@hub)
                              .where.not(id: MicOwner.select(:mic_id)).count
        @pending_mic_count = Mic.pending_moderation
                                .joins(:venue).where(venues: { city_hub_id: @hub.id }).count

        # Unassigned venues in the hub's state, grouped by city — every
        # row is a candidate suburb the superadmin can choose to roll up.
        # We expose all of them so the captain can pull in neighboring
        # towns that should belong to the metro (e.g. Speedway IN with
        # Indianapolis, Carmel IN with Indianapolis, etc.).
        candidates = Venue.where(state: @hub.state, city_hub_id: nil)
                          .where.not(city: [ nil, "" ])
                          .group(:city)
                          .order(Arel.sql("COUNT(*) DESC, city ASC"))
                          .count
        @rollup_candidate_cities = candidates.map { |city, n| [ city, n ] }
        @rollup_candidates       = candidates.values.sum
      end

      def update
        if @hub.update(hub_params)
          redirect_to mics_hub_path(@hub.slug), notice: "Saved."
        else
          flash.now[:alert] = @hub.errors.full_messages.to_sentence
          render :show, status: :unprocessable_content
        end
      end

      # JSON: does a CocoScout user already exist for this email, and are
      # they already a captain here? Used by the add-captain modal.
      def editor_lookup
        email = params[:email].to_s.strip.downcase
        if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
          render json: { found: false, valid: false }
          return
        end

        user = User.find_by("LOWER(email_address) = ?", email)
        if user
          already = @hub.memberships.exists?(user_id: user.id, role: CityHubMembership.roles[:editor])
          render json: { found: true, valid: true, email: user.email_address, name: user.person&.name.presence, already_on_mic: already }
        else
          render json: { found: false, valid: true }
        end
      end

      def add_editor
        email = params[:email].to_s.strip.downcase
        name  = params[:name].to_s.strip.presence

        unless ActiveModel::Type::Boolean.new.cast(params[:acknowledged_terms])
          redirect_to mics_hub_path(@hub.slug), alert: "Confirm the captain expectations checkbox before adding."
          return
        end

        unless email.match?(URI::MailTo::EMAIL_REGEXP)
          redirect_to mics_hub_path(@hub.slug), alert: "Please enter a valid email."
          return
        end

        user = User.find_by("LOWER(email_address) = ?", email)
        invited = false

        if user.blank?
          user = User.create!(email_address: email, password: User.generate_secure_password)
          user.people.create!(name: name.presence || email.split("@").first.titleize)
          token = user.generate_token_for(:password_reset)
          AuthMailer.password(user, token).deliver_later
          invited = true
        end

        @hub.memberships.find_or_create_by!(user_id: user.id) do |m|
          m.role = :editor
        end

        notice = if invited
          "Invited #{user.email_address} to CocoScout and made them a captain of #{@hub.name}."
        else
          "#{user.email_address} is now a captain of #{@hub.name}."
        end
        redirect_to mics_hub_path(@hub.slug), notice: notice
      end

      def remove_editor
        membership = @hub.memberships.find_by(user_id: params[:user_id])
        if membership
          email = membership.user.email_address
          membership.destroy
          redirect_to mics_hub_path(@hub.slug), notice: "Removed #{email} from #{@hub.name}."
        else
          redirect_to mics_hub_path(@hub.slug), alert: "That user isn't a captain here."
        end
      end

      def rollup_venues
        cities = Array(params[:cities]).map { |c| c.to_s.strip }.reject(&:blank?)
        if cities.empty?
          redirect_to mics_hub_path(@hub.slug),
                      alert: "Pick at least one city to roll up."
          return
        end

        count = Venue.where(state: @hub.state, city: cities, city_hub_id: nil)
                     .update_all(city_hub_id: @hub.id)
        redirect_to mics_hub_path(@hub.slug),
                    notice: "Rolled #{count} #{count == 1 ? "venue" : "venues"} into #{@hub.name} (#{cities.size} #{cities.size == 1 ? "city" : "cities"})."
      end

      private

      def load_hub
        @hub = CityHub.find_by!(slug: params[:slug])
      rescue ActiveRecord::RecordNotFound
        redirect_to mics_hubs_path, alert: "Hub not found."
      end

      def hub_params
        params.require(:city_hub).permit(:name, :state, :slug, :intro_markdown, :status,
                                         :default_radius_miles, :timezone, :lat, :lng)
      end
    end
  end
end
