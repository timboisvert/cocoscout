class Manage::QuestionnaireMailer < ApplicationMailer
  def invitation(person, questionnaire, production, message)
    @person = person
    @questionnaire = questionnaire
    @production = production
    @message = message

    mail(
      to: person.user.email_address,
      subject: "You're invited: #{questionnaire.title} - #{production.name}"
    )
  end
end
