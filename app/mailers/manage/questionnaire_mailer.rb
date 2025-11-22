class Manage::QuestionnaireMailer < ApplicationMailer
  def invitation(person, questionnaire, production, subject, message)
    @person = person
    @questionnaire = questionnaire
    @production = production
    @message = message

    mail(
      to: person.user.email_address,
      subject: subject
    )
  end
end
