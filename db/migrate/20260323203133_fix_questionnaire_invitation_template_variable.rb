class FixQuestionnaireInvitationTemplateVariable < ActiveRecord::Migration[8.1]
  def up
    template = ContentTemplate.find_by(key: "questionnaire_invitation")
    return unless template

    if template.body.include?("{{recipient_name}}")
      template.update!(body: template.body.gsub("{{recipient_name}}", "{{person_name}}"))
    end
  end

  def down
    template = ContentTemplate.find_by(key: "questionnaire_invitation")
    return unless template

    if template.body.include?("{{person_name}}")
      template.update!(body: template.body.gsub("{{person_name}}", "{{recipient_name}}"))
    end
  end
end
