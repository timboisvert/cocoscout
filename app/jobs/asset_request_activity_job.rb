# frozen_string_literal: true

# Tells a production's managers what arrived through its visual asset
# request, folded into one notification per sitting (Tim, 2026-11-19; fewer
# emails, more notifications). Every upload or saved word schedules this a
# few minutes out; only the run after the last change sends, and it names
# everything since the last notification. When that makes everything
# required complete, it says so instead, once.
#
# Nobody hears about their own change: a manager who uploads from the link
# while signed in is left out of the list.
class AssetRequestActivityJob < ApplicationJob
  queue_as :default

  WAIT = 10.minutes

  def perform(request_id)
    request = AssetRequest.find_by(id: request_id)
    return unless request&.last_activity_at
    # Something changed after this run was scheduled: that change's run sends.
    return if request.last_activity_at > WAIT.ago + 5.seconds

    since = request.notified_through_at || request.created_at
    rows = request.production_assets.where("changed_at > ?", since).includes(:asset_spec, :uploaded_by_user).to_a
    rows.select! { |row| row.asset_spec&.archived_at.nil? && row.asset_spec_id }
    return if rows.empty?

    production = request.production
    counts = ProductionAssets.new(production).counts
    complete_now = counts.complete? && request.completed_notified_at.nil?

    variables = { organization_name: production.organization.name, production_name: production.name,
                  arrived_words: arrived_words(rows), count_words: "#{counts.done} of #{counts.total} received." }
    template = complete_now ? "visual_assets_complete" : "visual_assets_arrived"
    path = Rails.application.routes.url_helpers.edit_manage_production_path(production, tab: 1)

    recipients(request, rows).each do |user|
      Notifier.deliver(user: user, category: "visual_assets", kind: template, template_key: template, variables: variables,
                       path: path, organization: production.organization, subject: request)
    end

    request.update_columns(notified_through_at: rows.filter_map(&:changed_at).max,
                           completed_notified_at: complete_now ? Time.current : request.completed_notified_at)
  end

  private

  def recipients(request, rows)
    uploaders = rows.filter_map(&:uploaded_by_user_id)
    users = ProductionNotificationSetting.users_to_notify(request.production) + [ request.created_by ]
    users.compact.uniq.reject { |user| uploaders.include?(user.id) }
  end

  # "Dana Whitfield added the Eventbrite banner and the Show description,
  # and replaced the Poster."
  def arrived_words(rows)
    names = rows.filter_map { |row| row.uploaded_by_name.presence || row.uploaded_by_user&.person&.name }.uniq
    who = names.any? ? names.to_sentence : "Someone with the link"
    added = rows.select { |row| row.last_change != "replaced" }.map { |row| "the #{row.asset_spec.name}" }
    replaced = rows.select { |row| row.last_change == "replaced" }.map { |row| "the #{row.asset_spec.name}" }
    parts = []
    parts << "added #{added.to_sentence}" if added.any?
    parts << "replaced #{replaced.to_sentence}" if replaced.any?
    "#{who} #{parts.join(', and ')}."
  end
end
