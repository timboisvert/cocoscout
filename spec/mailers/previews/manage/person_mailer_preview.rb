# Preview all emails at http://localhost:3000/rails/mailers/manage/person_mailer
class Manage::PersonMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/manage/person_mailer/person_invitation
  def person_invitation
    person_invitation = PersonInvitation.first || PersonInvitation.new(
      email: "person@example.com",
      token: "sample_token_123",
      organization: Organization.first || Organization.new(name: "Example Theatre Company")
    )
    Manage::PersonMailer.person_invitation(person_invitation)
  end

  # Preview this email at http://localhost:3000/rails/mailers/manage/person_mailer/contact_email
  def contact_email
    person = Person.first || Person.new(
      name: "Jane Doe",
      email: "jane@example.com"
    )
    user = User.first || User.new(
      email_address: "manager@example.com"
    )
    # Create a person association for the user if it doesn't have one
    user.person ||= Person.new(name: "Manager Name")

    subject = "Audition Details for Our Upcoming Production"
    message = "Hi Jane,\n\nWe wanted to reach out regarding the audition process for our upcoming production. We were impressed with your audition and would like to discuss further opportunities.\n\nPlease let us know your availability for a callback audition.\n\nBest regards,\nThe Casting Team"

    Manage::PersonMailer.contact_email(person, subject, message, user)
  end
end
