# frozen_string_literal: true

module MyHelper
  # Status badge/label constants
  AUDITION_OFFERED_BADGE = '<span class="inline-flex items-center bg-pink-500 text-white px-2.5 py-1 text-sm font-medium rounded">Audition Offered</span>'
  NO_AUDITION_OFFERED_BADGE = '<span class="inline-flex items-center bg-red-500 text-white px-2.5 py-1 text-sm font-medium rounded">No Audition Offered</span>'
  IN_REVIEW_BADGE = '<span class="inline-flex items-center bg-amber-500 text-white px-2.5 py-1 text-sm font-medium rounded">In Review</span>'
  SIGNUP_RECEIVED_BADGE = '<span class="inline-flex items-center bg-gray-500 text-white px-2.5 py-1 text-sm font-medium rounded">Sign-up Received</span>'
  VIDEO_RECEIVED_BADGE = '<span class="inline-flex items-center bg-gray-500 text-white px-2.5 py-1 text-sm font-medium rounded">Video Audition Received</span>'
  CAST_SPOT_OFFERED_BADGE = '<span class="inline-flex items-center bg-pink-500 text-white px-2.5 py-1 text-sm font-medium rounded">Cast Spot Offered</span>'
  NO_CAST_SPOT_OFFERED_BADGE = '<span class="inline-flex items-center bg-red-500 text-white px-2.5 py-1 text-sm font-medium rounded">No Cast Spot Offered</span>'

  # Status text constants (used in explanatory messages)
  AUDITION_OFFERED_TEXT = "Congratulations! You have been offered an audition for this production"
  NO_AUDITION_OFFERED_TEXT = "Unfortunately, you have not been offered an audition for this production"
  AUDITION_IN_REVIEW_TEXT = "Your sign-up is being reviewed by the production team."
  SIGNUP_RECEIVED_TEXT = "Your sign-up has been received and will be reviewed soon."
  VIDEO_RECEIVED_TEXT = "Your video audition has been received and will be reviewed soon."
  CAST_SPOT_OFFERED_TEXT = "Congratulations! You have been offered a cast spot for this production"
  NO_CAST_SPOT_OFFERED_TEXT = "Unfortunately, you have not been offered a cast spot for this production"
  CAST_IN_REVIEW_TEXT = "Your video audition is being reviewed by the production team."

  def in_person_signup_status_name(audition_request)
    cycle = audition_request.audition_cycle

    # If cycle is archived (not active)
    unless cycle.active
      # If invitations were finalized before archiving, show the actual status
      unless cycle.finalize_audition_invitations == true
        return NO_AUDITION_OFFERED_BADGE.html_safe
      end
      # Check if they were actually scheduled for an audition (have an Audition record)
      if audition_request.auditions.exists?
        return AUDITION_OFFERED_BADGE.html_safe
      end

      return NO_AUDITION_OFFERED_BADGE.html_safe
    end

    # If audition invitations haven't been finalized, show review status
    if cycle.finalize_audition_invitations != true
      # Check if anyone has voted on this request - if so, show "In Review"
      if audition_request.audition_request_votes.exists?
        return IN_REVIEW_BADGE.html_safe
      else
        return SIGNUP_RECEIVED_BADGE.html_safe
      end
    end

    # Check if they were actually scheduled for an audition (have an Audition record)
    if audition_request.auditions.exists?
      AUDITION_OFFERED_BADGE.html_safe
    else
      NO_AUDITION_OFFERED_BADGE.html_safe
    end
  end

  def in_person_signup_status_text(audition_request)
    cycle = audition_request.audition_cycle

    # If cycle is archived (not active)
    unless cycle.active
      # If invitations were finalized before archiving, show the actual status
      unless cycle.finalize_audition_invitations == true
        return NO_AUDITION_OFFERED_TEXT
      end

      # Check if they were actually scheduled for an audition
      if audition_request.auditions.exists?
        return AUDITION_OFFERED_TEXT
      else
        return NO_AUDITION_OFFERED_TEXT
      end
    end

    # If audition invitations haven't been finalized, show review status
    if cycle.finalize_audition_invitations != true
      # Check if anyone has voted on this request
      if audition_request.audition_request_votes.exists?
        return AUDITION_IN_REVIEW_TEXT
      else
        return SIGNUP_RECEIVED_TEXT
      end
    end

    # Check if they were actually scheduled for an audition
    if audition_request.auditions.exists?
      AUDITION_OFFERED_TEXT
    else
      NO_AUDITION_OFFERED_TEXT
    end
  end

  def video_audition_status_name(audition_request)
    cycle = audition_request.audition_cycle
    requestable = audition_request.requestable

    # Check if they were added to talent pool via cast_assignment_stages
    is_cast = CastAssignmentStage.exists?(
      audition_cycle_id: cycle.id,
      assignable_type: requestable.class.name,
      assignable_id: requestable.id
    )

    # If already cast, show cast status immediately (regardless of finalization)
    if is_cast
      return CAST_SPOT_OFFERED_BADGE.html_safe
    end

    # If cycle is archived (not active)
    unless cycle.active
      # If casting was finalized before archiving, show the actual status
      unless cycle.casting_finalized_at.present?
        return NO_CAST_SPOT_OFFERED_BADGE.html_safe
      end

      return NO_CAST_SPOT_OFFERED_BADGE.html_safe
    end

    # If casting hasn't been finalized, show review status
    if cycle.casting_finalized_at.blank?
      # Check if anyone has voted on this request - if so, show "In Review"
      if audition_request.audition_request_votes.exists?
        return IN_REVIEW_BADGE.html_safe
      else
        return VIDEO_RECEIVED_BADGE.html_safe
      end
    end

    NO_CAST_SPOT_OFFERED_BADGE.html_safe
  end

  def video_audition_status_text(audition_request)
    cycle = audition_request.audition_cycle
    requestable = audition_request.requestable

    # Check if they were added to talent pool via cast_assignment_stages
    is_cast = CastAssignmentStage.exists?(
      audition_cycle_id: cycle.id,
      assignable_type: requestable.class.name,
      assignable_id: requestable.id
    )

    # If already cast, show cast status immediately (regardless of finalization)
    if is_cast
      return CAST_SPOT_OFFERED_TEXT
    end

    # If cycle is archived (not active)
    unless cycle.active
      # If casting was finalized before archiving, show the actual status
      unless cycle.casting_finalized_at.present?
        return NO_CAST_SPOT_OFFERED_TEXT
      end

      return NO_CAST_SPOT_OFFERED_TEXT
    end

    # If casting hasn't been finalized, show review status
    if cycle.casting_finalized_at.blank?
      # Check if anyone has voted on this request
      if audition_request.audition_request_votes.exists?
        return CAST_IN_REVIEW_TEXT
      else
        return VIDEO_RECEIVED_TEXT
      end
    end

    NO_CAST_SPOT_OFFERED_TEXT
  end

  # Check if current user can moderate (delete) posts for a given post
  def can_moderate_post?(post)
    production = post.production
    ProductionPermission.exists?(production: production, user: Current.user) ||
      OrganizationRole.exists?(organization: production.organization, user: Current.user)
  end
end
