class SimplifyQuestionnaireInvitationTemplate < ActiveRecord::Migration[8.1]
  def up
    template = ContentTemplate.find_by(key: "questionnaire_invitation")
    return unless template

    template.update!(
      subject: "Please complete a questionnaire",
      body: <<~HTML
        <p>Hi {{person_name}},</p>
        <p>Please fill out the following questionnaire:</p>
        <p><a href="{{questionnaire_url}}">{{questionnaire_title}}</a></p>
      HTML
    )
  end

  def down
    template = ContentTemplate.find_by(key: "questionnaire_invitation")
    return unless template

    template.update!(
      subject: "{{production_name}}: Please complete this questionnaire",
      body: <<~HTML
        <p>Hi {{person_name}},</p>
        <p>You've been invited to complete a questionnaire for <strong>{{production_name}}</strong>.</p>
        {{#custom_message}}
        <p>{{custom_message}}</p>
        {{/custom_message}}
        <p><a href="{{questionnaire_url}}">Complete Questionnaire</a></p>
      HTML
    )
  end
end
