class AuthMailerPreview < ActionMailer::Preview
  def signup
    AuthMailer.signup(User.take)
  end

  def password
    AuthMailer.password(User.take, "example-token")
  end
end
