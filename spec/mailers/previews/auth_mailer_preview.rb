# Preview all emails at http://localhost:3000/rails/mailers/auth_mailer
class AuthMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/auth_mailer/signup
  def signup
    user = User.first || User.new(email_address: "user@example.com")
    AuthMailer.signup(user)
  end

  # Preview this email at http://localhost:3000/rails/mailers/auth_mailer/password
  def password
    user = User.first || User.new(email_address: "user@example.com")
    token = "sample_reset_token_123"
    AuthMailer.password(user, token)
  end
end
