module MyHelper
  def in_person_signup_status_name(audition_request)
    cycle = audition_request.audition_cycle

    # If cycle is archived (not active)
    if !cycle.active
      # If invitations were finalized before archiving, show the actual status
      if cycle.finalize_audition_invitations == true
        # Check if they were actually scheduled for an audition (have an Audition record)
        if audition_request.auditions.exists?
          return "<div class=\"bg-pink-500 text-white px-2 py-1 text-sm rounded-lg\">Audition Offered</div>".html_safe
        else
          return "<div class=\"bg-red-500 text-white px-2 py-1 text-sm rounded-lg\">No Audition Offered</div>".html_safe
        end
      else
        # If invitations were never finalized, treat as not offered
        return "<div class=\"bg-red-500 text-white px-2 py-1 text-sm rounded-lg\">No Audition Offered</div>".html_safe
      end
    end

    # If audition invitations haven't been finalized, show "In Review"
    if cycle.finalize_audition_invitations != true
      return "<div class=\"bg-gray-500 text-white px-2 py-1 text-sm rounded-lg\">In Review</div>".html_safe
    end

    # Check if they were actually scheduled for an audition (have an Audition record)
    if audition_request.auditions.exists?
      "<div class=\"bg-pink-500 text-white px-2 py-1 text-sm rounded-lg\">Audition Offered</div>".html_safe
    else
      "<div class=\"bg-red-500 text-white px-2 py-1 text-sm rounded-lg\">No Audition Offered</div>".html_safe
    end
  end

  def in_person_signup_status_text(audition_request)
    cycle = audition_request.audition_cycle

    # If cycle is archived (not active)
    if !cycle.active
      # If invitations were finalized before archiving, show the actual status
      if cycle.finalize_audition_invitations == true
        case audition_request.status
        when "accepted"
          return "Congratulations! You have been offered an audition for this production"
        else
          return "Unfortunately, you have not been offered an audition for this production"
        end
      else
        # If invitations were never finalized, treat as not offered
        return "Unfortunately, you have not been offered an audition for this production"
      end
    end

    # If audition invitations haven't been finalized, show "In Review"
    if cycle.finalize_audition_invitations != true
      return "Your sign-up is in review. Results will be shared once audition decisions have been finalized."
    end

    case audition_request.status
    when "unreviewed"
      "Your sign-up is awaiting review"
    when "undecided"
      "Your sign-up has been reviewed, but no decision has been made yet"
    when "passed"
      "Unfortunately, you have not been offered an audition for this production"
    when "accepted"
      "Congratulations! You have been offered an audition for this production"
    end
  end

  def video_audition_status_name(audition_request)
    cycle = audition_request.audition_cycle

    # If cycle is archived (not active)
    if !cycle.active
      # If invitations were finalized before archiving, show the actual status
      if cycle.finalize_audition_invitations == true
        case audition_request.status
        when "accepted"
          return "<div class=\"bg-pink-500 text-white px-2 py-1 text-sm rounded-lg\">Cast Spot Offered</div>".html_safe
        else
          # unreviewed, undecided, or passed all become "No Cast Spot Offered"
          return "<div class=\"bg-red-500 text-white px-2 py-1 text-sm rounded-lg\">No Cast Spot Offered</div>".html_safe
        end
      else
        # If invitations were never finalized, treat as not offered
        return "<div class=\"bg-red-500 text-white px-2 py-1 text-sm rounded-lg\">No Cast Spot Offered</div>".html_safe
      end
    end

    # If audition invitations haven't been finalized, show "In Review"
    if cycle.finalize_audition_invitations != true
      return "<div class=\"bg-gray-500 text-white px-2 py-1 text-sm rounded-lg\">In Review</div>".html_safe
    end

    case audition_request.status
    when "unreviewed"
      "<div class=\"bg-black text-white px-2 py-1 text-sm rounded-lg\">Awaiting Review</div>".html_safe
    when "undecided"
      "<div class=\"bg-black text-white px-2 py-1 text-sm rounded-lg\">In Review</div>".html_safe
    when "passed"
      "<div class=\"bg-red-500 text-white px-2 py-1 text-sm rounded-lg\">No Cast Spot Offered</div>".html_safe
    when "accepted"
      "<div class=\"bg-pink-500 text-white px-2 py-1 text-sm rounded-lg\">Cast Spot Offered</div>".html_safe
    end
  end

  def video_audition_status_text(audition_request)
    cycle = audition_request.audition_cycle

    # If cycle is archived (not active)
    if !cycle.active
      # If invitations were finalized before archiving, show the actual status
      if cycle.finalize_audition_invitations == true
        case audition_request.status
        when "accepted"
          return "Congratulations! You have been offered a cast spot for this production"
        else
          return "Unfortunately, you have not been offered a cast spot for this production"
        end
      else
        # If invitations were never finalized, treat as not offered
        return "Unfortunately, you have not been offered a cast spot for this production"
      end
    end

    # If audition invitations haven't been finalized, show "In Review"
    if cycle.finalize_audition_invitations != true
      return "Your video audition is in review. Results will be shared once audition decisions have been finalized."
    end

    case audition_request.status
    when "unreviewed"
      "Your video audition is awaiting review"
    when "undecided"
      "Your video audition has been reviewed, but no decision has been made yet"
    when "passed"
      "Unfortunately, you have not been offered a cast spot for this production"
    when "accepted"
      "Congratulations! You have been offered a cast spot for this production"
    end
  end
end
