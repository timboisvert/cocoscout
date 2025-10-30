# Preview all emails at http://localhost:3000/rails/mailers/manage/person_mailer
class Manage::PersonMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/manage/person_mailer/person_invitation
  def person_invitation
    person_invitation = PersonInvitation.first || PersonInvitation.new(
      email: "person@example.com",
      token: "sample_token_123",
      production_company: ProductionCompany.first || ProductionCompany.new(name: "Example Theatre Company")
    )
    Manage::PersonMailer.person_invitation(person_invitation)
  end
end
