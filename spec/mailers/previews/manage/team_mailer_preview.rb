# Preview all emails at http://localhost:3000/rails/mailers/manage/team_mailer
class Manage::TeamMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/manage/team_mailer/invite
  def invite
    team_invitation = TeamInvitation.first || TeamInvitation.new(
      email: "team@example.com",
      production_company: ProductionCompany.first || ProductionCompany.new(name: "Example Theatre Company")
    )
    Manage::TeamMailer.invite(team_invitation)
  end
end
