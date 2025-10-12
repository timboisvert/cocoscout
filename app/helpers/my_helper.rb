module MyHelper
  def in_person_signup_status_name(audition_request)
    case audition_request.status
    when "unreviewed"
      "<div class=\"bg-black text-white px-2 py-1 text-sm rounded-lg\">Awaiting Review</div>".html_safe
    when "undecided"
      "<div class=\"bg-black text-white px-2 py-1 text-sm rounded-lg\">In Review</div>".html_safe
    when "passed"
      "<div class=\"bg-red-500 text-white px-2 py-1 text-sm rounded-lg\">No Audition Offered</div>".html_safe
    when "accepted"
      "<div class=\"bg-pink-500 text-white px-2 py-1 text-sm rounded-lg\">Audition Offered</div>".html_safe
    end
  end

  def in_person_signup_status_text(audition_request)
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
