# frozen_string_literal: true

# Superadmin Finances, Email: how much mail CocoScout has sent this month
# against its Mailgun plan, where the month is heading, how much of it is
# email to followers, and the blocks of extra follower emails organizations
# have bought (MailVolume, FollowerEmailBlock). The plan's size is set here,
# since CocoScout can count what it sends but not what Mailgun bills.
#
#   /superadmin/finances/email
module Superadmin
  class EmailVolumeController < FinancesController
    def index
      @volume = MailVolume.new
      @months = MailVolumeMonth.order(month: :desc).limit(12).to_a
      @blocks = FollowerEmailBlock.includes(:organization, :bought_by).order(created_at: :desc).limit(50).to_a
      @blocks_this_month = @volume.blocks_this_month
      # Who still holds paid emails they haven't sent.
      bought = FollowerEmailBlock.group(:organization_id).sum(:emails)
      used = FollowerEmail.where(organization_id: bought.keys).group(:organization_id).sum(:paid_emails_used)
      names = Organization.where(id: bought.keys).pluck(:id, :name).to_h
      @holding = bought.filter_map { |id, emails| (left = emails - used[id].to_i).positive? ? [ names[id], left ] : nil }.sort_by { |_, left| -left }
    end

    def update
      MailVolume.set!(plan_emails: params[:plan_emails], upgrade_at: params[:upgrade_at])
      redirect_to finances_email_path, notice: "Saved."
    end
  end
end
