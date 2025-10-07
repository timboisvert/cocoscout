module ManageHelper
  def manage_signup_status_name(status)
    case status
    when :all, "all"
      "All"
    when :unreviewed, "unreviewed"
      "Unreviewed"
    when :undecided, "undecided"
      "Revisit"
    when :passed, "passed"
      "Don't Offer"
    when :accepted, "accepted"
      "Offer Audition"
    end
  end
end
