# frozen_string_literal: true

# Producers post short news items to a mic's detail page.
# The `notify_subscribers` checkbox is captured but email fan-out is
# intentionally OFF for now; re-enable by enqueueing
# MicAnnouncementBroadcastJob.
module Mics
  class AnnouncementsController < AuthedBaseController
    before_action :load_mic_and_authorize

    def create
      announcement = @mic.mic_announcements.build(
        title: params[:title].to_s.strip.presence,
        body:  params[:body].to_s.strip,
        notify_subscribers: !!ActiveModel::Type::Boolean.new.cast(params[:notify_subscribers]),
        posted_by_user_id: current_user.id,
        posted_at: Time.current
      )

      if announcement.save
        # Email fan-out OFF for now. The notify_subscribers flag is
        # preserved on the record so the producer's intent is recorded.
        @mic.mic_edits.create!(editor_user_id: current_user.id, source: :producer,
                                field: "announcement", new_value: announcement.title.presence || "posted")
        redirect_to mics_owner_mic_path(@mic.slug), notice: "Announcement posted."
      else
        redirect_to mics_owner_mic_path(@mic.slug), alert: announcement.errors.full_messages.to_sentence
      end
    end

    private

    def load_mic_and_authorize
      @mic = Mic.find_by!(slug: params[:slug].to_s.downcase)
      head :forbidden unless authorized?
    rescue ActiveRecord::RecordNotFound
      render plain: "Not found", status: :not_found
    end

    def authorized?
      @mic.manageable_by?(current_user)
    end
  end
end
