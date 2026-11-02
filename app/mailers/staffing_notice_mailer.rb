# frozen_string_literal: true

# The email half of a staffing notice that arrives rendered from its
# ContentTemplate (a shift vacancy: can't make it, covered, back on). The
# shape ShowChangeMailer#notice already has is exactly what
# ContentTemplateService's email channel calls, so this is that mailer under
# the name the email log should show.
class StaffingNoticeMailer < ShowChangeMailer
end
