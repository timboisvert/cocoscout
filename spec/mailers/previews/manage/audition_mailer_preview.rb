# Preview all emails at http://localhost:3000/rails/mailers/manage/audition_mailer
class Manage::AuditionMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/manage/audition_mailer/casting_notification_accepted
  def casting_notification_accepted
    person = Person.first || Person.new(
      name: "Jane Smith",
      email: "jane@example.com"
    )
    production = Production.first || Production.new(
      name: "The Importance of Being Earnest"
    )

    email_body = <<~EMAIL
      Dear Jane Smith,

      Congratulations! We're excited to invite you to join the Ensemble for The Importance of Being Earnest.

      Your audition impressed us, and we believe you'll be a great addition to the team. We look forward to working with you.

      Please confirm your acceptance by replying to this email.

      Best regards,
      The The Importance of Being Earnest Team
    EMAIL

    Manage::AuditionMailer.casting_notification(person, production, email_body)
  end

  # Preview this email at http://localhost:3000/rails/mailers/manage/audition_mailer/casting_notification_rejected
  def casting_notification_rejected
    person = Person.first || Person.new(
      name: "John Doe",
      email: "john@example.com"
    )
    production = Production.first || Production.new(
      name: "The Importance of Being Earnest"
    )

    email_body = <<~EMAIL
      Dear John Doe,

      Thank you so much for auditioning for The Importance of Being Earnest. We truly appreciate the time and effort you put into your audition.

      Unfortunately, we won't be able to offer you a role in this production at this time. We were impressed by your talent and encourage you to audition for future productions.

      We hope to work with you in the future.

      Best regards,
      The The Importance of Being Earnest Team
    EMAIL

    Manage::AuditionMailer.casting_notification(person, production, email_body)
  end

  # Preview this email at http://localhost:3000/rails/mailers/manage/audition_mailer/casting_notification_custom
  def casting_notification_custom
    person = Person.first || Person.new(
      name: "Emily Williams",
      email: "emily@example.com"
    )
    production = Production.first || Production.new(
      name: "Romeo and Juliet"
    )

    email_body = <<~EMAIL
      Dear Emily Williams,

      Thank you for auditioning for Romeo and Juliet!

      We'd like to invite you to join us as an understudy. While this isn't a primary cast role, we believe you have great potential and would love for you to be part of our production.

      Understudies attend all rehearsals and are prepared to step into the role if needed. This is an excellent opportunity to learn and grow as a performer.

      Please let us know if you're interested in this position.

      Best regards,
      The Production Team
    EMAIL

    Manage::AuditionMailer.casting_notification(person, production, email_body)
  end
end
