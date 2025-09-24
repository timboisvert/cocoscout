module MyHelper
  def friendly_request_status_name(audition_request)
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

  def friendly_request_status_text(audition_request)
    case audition_request.status
    when "unreviewed"
      "Your audition request is awaiting review."
    when "undecided"
      "Your audition request has been reviewed, but no decision has been made yet."
    when "passed"
      "Unfortunately, you have not been offered an audition for this production."
    when "accepted"
      "Congratulations! You have been offered an audition for this production."
    end
  end
end
