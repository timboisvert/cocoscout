class UpdateAuditionInvitationTemplateBody < ActiveRecord::Migration[8.1]
  def up
    template = ContentTemplate.find_by(key: "audition_invitation")
    return unless template

    new_body = <<~HTML.strip
      <div>Dear {{recipient_name}},<br><br>Congratulations! You've been invited to audition for <strong>{{production_name}}</strong>.<br><br><strong>Your Audition Details:</strong><br>Date: {{audition_date}}<br>Time: {{audition_time}}<br>Location: {{audition_location}}<br><br>Please confirm your attendance by clicking the link below:<br><a href="{{audition_url}}">Confirm Your Audition</a><br><br>If you cannot attend, please let us know as soon as possible so we can offer your slot to someone else.<br><br>We look forward to seeing you!<br><br>Best regards,<br>The {{production_name}} Team</div>
    HTML

    template.update!(body: new_body)
  end

  def down
    template = ContentTemplate.find_by(key: "audition_invitation")
    return unless template

    old_body = <<~HTML.strip
      <div>Dear {{recipient_name}},&nbsp;<br><br>Congratulations! You've been invited to audition for {{production_name}}. Your audition schedule is now available.&nbsp;<br><br>Please log in to view your audition time and location details. We look forward to seeing you!&nbsp;<br><br>Best regards,&nbsp;<br>The {{production_name}} Team</div>
    HTML

    template.update!(body: old_body)
  end
end
