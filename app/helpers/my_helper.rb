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

      # If invitations were never finalized, treat as not offered

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

      case audition_request.status
      when "accepted"
        return "Congratulations! You have been offered an audition for this production"
      else
        return "Unfortunately, you have not been offered an audition for this production"
      end

      # If invitations were never finalized, treat as not offered

    end

    # If audition invitations haven't been finalized, show "In Review"
    if cycle.finalize_audition_invitations != true
      return "Your sign-up is in review. Results will be shared once audition decisions have been finalized."
    end

    case audition_request.status
    when "pending"
      "Your sign-up is awaiting review"
    when "rejected"
      "Unfortunately, you have not been offered an audition for this production"
    when "approved"
      "Congratulations! You have been offered an audition for this production"
    end
  end

  def video_audition_status_name(audition_request)
    cycle = audition_request.audition_cycle

    # If cycle is archived (not active)
    unless cycle.active
      # If invitations were finalized before archiving, show the actual status
      unless cycle.finalize_audition_invitations == true
        return '<div class="bg-red-500 text-white px-2 py-1 text-sm rounded-lg">No Cast Spot Offered</div>'.html_safe
      end

      case audition_request.status
      when "approved"
        return '<div class="bg-pink-500 text-white px-2 py-1 text-sm rounded-lg">Cast Spot Offered</div>'.html_safe
      else
        # pending or rejected all become "No Cast Spot Offered"
        return '<div class="bg-red-500 text-white px-2 py-1 text-sm rounded-lg">No Cast Spot Offered</div>'.html_safe
      end

      # If invitations were never finalized, treat as not offered

    end

    # If audition invitations haven't been finalized, show "In Review"
    if cycle.finalize_audition_invitations != true
      return '<div class="bg-gray-500 text-white px-2 py-1 text-sm rounded-lg">In Review</div>'.html_safe
    end

    case audition_request.status
    when "pending"
      '<div class="bg-black text-white px-2 py-1 text-sm rounded-lg">Awaiting Review</div>'.html_safe
    when "rejected"
      '<div class="bg-red-500 text-white px-2 py-1 text-sm rounded-lg">No Cast Spot Offered</div>'.html_safe
    when "approved"
      '<div class="bg-pink-500 text-white px-2 py-1 text-sm rounded-lg">Cast Spot Offered</div>'.html_safe
    end
  end

  def video_audition_status_text(audition_request)
    cycle = audition_request.audition_cycle

    # If cycle is archived (not active)
    unless cycle.active
      # If invitations were finalized before archiving, show the actual status
      unless cycle.finalize_audition_invitations == true
        return "Unfortunately, you have not been offered a cast spot for this production"
      end

      case audition_request.status
      when "accepted"
        return "Congratulations! You have been offered a cast spot for this production"
      else
        return "Unfortunately, you have not been offered a cast spot for this production"
      end

      # If invitations were never finalized, treat as not offered

    end

    # If audition invitations haven't been finalized, show "In Review"
    if cycle.finalize_audition_invitations != true
      return "Your video audition is in review. Results will be shared once audition decisions have been finalized."
    end

    case audition_request.status
    when "pending"
      "Your video audition is awaiting review"
    when "rejected"
      "Unfortunately, you have not been offered a cast spot for this production"
    when "approved"
      "Congratulations! You have been offered a cast spot for this production"
    end
  end
end
