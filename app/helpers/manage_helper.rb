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
      "No"
    when :accepted, "accepted"
      "Yes"
    end
  end
end
