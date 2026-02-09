# frozen_string_literal: true

module MyHelper
  # Status badge/label constants
  AUDITION_OFFERED_BADGE = '<div class="bg-pink-500 text-white px-2 py-1 text-sm rounded-lg">Audition Offered</div>'
  NO_AUDITION_OFFERED_BADGE = '<div class="bg-red-500 text-white px-2 py-1 text-sm rounded-lg">No Audition Offered</div>'
  IN_REVIEW_BADGE = '<div class="bg-gray-500 text-white px-2 py-1 text-sm rounded-lg">In Review</div>'
  CAST_SPOT_OFFERED_BADGE = '<div class="bg-pink-500 text-white px-2 py-1 text-sm rounded-lg">Cast Spot Offered</div>'
  NO_CAST_SPOT_OFFERED_BADGE = '<div class="bg-red-500 text-white px-2 py-1 text-sm rounded-lg">No Cast Spot Offered</div>'

  # Status text constants (used in explanatory messages)
  AUDITION_OFFERED_TEXT = "Congratulations! You have been offered an audition for this production"
  NO_AUDITION_OFFERED_TEXT = "Unfortunately, you have not been offered an audition for this production"
  AUDITION_IN_REVIEW_TEXT = "Your sign-up is in review. Results will be shared once audition decisions have been finalized."
  CAST_SPOT_OFFERED_TEXT = "Congratulations! You have been offered a cast spot for this production"
  NO_CAST_SPOT_OFFERED_TEXT = "Unfortunately, you have not been offered a cast spot for this production"
  CAST_IN_REVIEW_TEXT = "Your video audition is in review. Results will be shared once casting decisions have been finalized."

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

    # If audition invitations haven't been finalized, show "In Review"
    if cycle.finalize_audition_invitations != true
      return IN_REVIEW_BADGE.html_safe
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

    # If audition invitations haven't been finalized, show "In Review"
    if cycle.finalize_audition_invitations != true
      return AUDITION_IN_REVIEW_TEXT
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

    # If cycle is archived (not active)
    unless cycle.active
      # If casting was finalized before archiving, show the actual status
      unless cycle.casting_finalized_at.present?
        return NO_CAST_SPOT_OFFERED_BADGE.html_safe
      end

      if is_cast
        return CAST_SPOT_OFFERED_BADGE.html_safe
      else
        return NO_CAST_SPOT_OFFERED_BADGE.html_safe
      end
    end

    # If casting hasn't been finalized, show "In Review"
    if cycle.casting_finalized_at.blank?
      return IN_REVIEW_BADGE.html_safe
    end

    if is_cast
      CAST_SPOT_OFFERED_BADGE.html_safe
    else
      NO_CAST_SPOT_OFFERED_BADGE.html_safe
    end
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

    # If cycle is archived (not active)
    unless cycle.active
      # If casting was finalized before archiving, show the actual status
      unless cycle.casting_finalized_at.present?
        return NO_CAST_SPOT_OFFERED_TEXT
      end

      if is_cast
        return CAST_SPOT_OFFERED_TEXT
      else
        return NO_CAST_SPOT_OFFERED_TEXT
      end
    end

    # If casting hasn't been finalized, show "In Review"
    if cycle.casting_finalized_at.blank?
      return CAST_IN_REVIEW_TEXT
    end

    if is_cast
      CAST_SPOT_OFFERED_TEXT
    else
      NO_CAST_SPOT_OFFERED_TEXT
    end
  end

  # Check if current user can moderate (delete) posts for a given post
  def can_moderate_post?(post)
    production = post.production
    ProductionPermission.exists?(production: production, user: Current.user) ||
      OrganizationRole.exists?(organization: production.organization, user: Current.user)
  end
end
