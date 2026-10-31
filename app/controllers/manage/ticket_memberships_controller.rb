# frozen_string_literal: true

module Manage
  # Memberships (advanced ticketing §2b): the organization's levels, each a
  # checklist of perks, and who's a member.
  class TicketMembershipsController < Manage::TicketingBaseController
    before_action :set_level, only: %i[edit update destroy]

    def index
      @levels = Current.organization.ticket_membership_levels.in_order.to_a
      @counts = Current.organization.ticket_memberships.live.group(:ticket_membership_level_id).count
      scope = Current.organization.ticket_memberships.where.not(status: "pending").includes(:level)
      @q = params[:q].to_s.squish
      scope = scope.where("holder_name ILIKE :q OR holder_email ILIKE :q", q: "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%") if @q.present?
      @memberships = scope.order(created_at: :desc).limit(200).to_a
      @members_url = tickets_members_url(org: TicketingProfile.for(Current.organization).slug)
    end

    def new
      @level = Current.organization.ticket_membership_levels.new(period_months: 12)
    end

    def create
      @level = Current.organization.ticket_membership_levels.new(level_params.merge(position: (Current.organization.ticket_membership_levels.maximum(:position) || 0) + 1))
      if @level.save
        redirect_to manage_ticket_memberships_path, notice: "#{@level.name} saved#{' and on sale' if @level.status == 'on_sale'}."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      if @level.update(level_params)
        redirect_to manage_ticket_memberships_path, notice: "#{@level.name} saved."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      if @level.memberships.exists?
        @level.update!(status: "closed")
        redirect_to manage_ticket_memberships_path, notice: "#{@level.name} has members, so it's closed rather than removed."
      else
        @level.destroy!
        redirect_to manage_ticket_memberships_path, notice: "#{@level.name} removed."
      end
    end

    # Ending a membership by hand (a refund, if any, is done from the
    # purchase in Orders).
    def cancel
      membership = Current.organization.ticket_memberships.find_by!(token: params[:token])
      membership.update!(status: "canceled")
      redirect_to manage_ticket_memberships_path, notice: "#{membership.holder_name.presence || membership.holder_email} is no longer a member."
    end

    private

    def set_level
      @level = Current.organization.ticket_membership_levels.find(params[:id])
    end

    def level_params
      raw = params.require(:ticket_membership_level).permit(:name, :description, :price, :period_months, :status, :discount_percent, :presale_days,
                                                            :free_exchanges, :better_seats, :section_upgrade, :extras)
      raw[:price_cents] = (raw.delete(:price).to_s.delete("$,").to_f * 100).round if raw.key?(:price)
      raw
    end
  end
end
