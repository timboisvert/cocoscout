# frozen_string_literal: true

module MyHelper
  def in_person_signup_status_name(audition_request)
    cycle = audition_request.audition_cycle

    # If cycle is archived (not active)
    unless cycle.active
      # If invitations were finalized before archiving, show the actual status
      unless cycle.finalize_audition_invitations == true
        return '<div class="bg-red-500 text-white px-2 py-1 text-sm rounded-lg">No Audition Offered</div>'.html_safe
      end
      # Check if they were actually scheduled for an audition (have an Audition record)
      if audition_request.auditions.exists?
        return '<div class="bg-pink-500 text-white px-2 py-1 text-sm rounded-lg">Audition Offered</div>'.html_safe
      end

      return '<div class="bg-red-500 text-white px-2 py-1 text-sm rounded-lg">No Audition Offered</div>'.html_safe
    end

    # If audition invitations haven't been finalized, show "In Review"
    if cycle.finalize_audition_invitations != true
      return '<div class="bg-gray-500 text-white px-2 py-1 text-sm rounded-lg">In Review</div>'.html_safe
    end

    # Check if they were actually scheduled for an audition (have an Audition record)
    if audition_request.auditions.exists?
      '<div class="bg-pink-500 text-white px-2 py-1 text-sm rounded-lg">Audition Offered</div>'.html_safe
    else
      '<div class="bg-red-500 text-white px-2 py-1 text-sm rounded-lg">No Audition Offered</div>'.html_safe
    end
  end

  def in_person_signup_status_text(audition_request)
    cycle = audition_request.audition_cycle

    # If cycle is archived (not active)
    unless cycle.active
      # If invitations were finalized before archiving, show the actual status
      unless cycle.finalize_audition_invitations == true
        return "Unfortunately, you have not been offered an audition for this production"
      end

      # Check if they were actually scheduled for an audition
      if audition_request.auditions.exists?
        return "Congratulations! You have been offered an audition for this production"
      else
        return "Unfortunately, you have not been offered an audition for this production"
      end
    end

    # If audition invitations haven't been finalized, show "In Review"
    if cycle.finalize_audition_invitations != true
      return "Your sign-up is in review. Results will be shared once audition decisions have been finalized."
    end

    # Check if they were actually scheduled for an audition
    if audition_request.auditions.exists?
      "Congratulations! You have been offered an audition for this production"
    else
      "Unfortunately, you have not been offered an audition for this production"
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
        return '<div class="bg-red-500 text-white px-2 py-1 text-sm rounded-lg">No Cast Spot Offered</div>'.html_safe
      end

      if is_cast
        return '<div class="bg-pink-500 text-white px-2 py-1 text-sm rounded-lg">Cast Spot Offered</div>'.html_safe
      else
        return '<div class="bg-red-500 text-white px-2 py-1 text-sm rounded-lg">No Cast Spot Offered</div>'.html_safe
      end
    end

    # If casting hasn't been finalized, show "In Review"
    if cycle.casting_finalized_at.blank?
      return '<div class="bg-gray-500 text-white px-2 py-1 text-sm rounded-lg">In Review</div>'.html_safe
    end

    if is_cast
      '<div class="bg-pink-500 text-white px-2 py-1 text-sm rounded-lg">Cast Spot Offered</div>'.html_safe
    else
      '<div class="bg-red-500 text-white px-2 py-1 text-sm rounded-lg">No Cast Spot Offered</div>'.html_safe
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
        return "Unfortunately, you have not been offered a cast spot for this production"
      end

      if is_cast
        return "Congratulations! You have been offered a cast spot for this production"
      else
        return "Unfortunately, you have not been offered a cast spot for this production"
      end
    end

    # If casting hasn't been finalized, show "In Review"
    if cycle.casting_finalized_at.blank?
      return "Your video audition is in review. Results will be shared once casting decisions have been finalized."
    end

    if is_cast
      "Congratulations! You have been offered a cast spot for this production"
    else
      "Unfortunately, you have not been offered a cast spot for this production"
    end
  end
end
