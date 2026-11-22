# frozen_string_literal: true

# Creating an account in request specs. The first step of the sign-in screen
# sits behind bot defenses (a signed form-age token and a honeypot,
# AuthController#signup_gate_passed?), and a new address then confirms itself
# with an emailed code before the person enters their name. Specs use these so
# they look like a person who loaded the form a moment ago, not a script
# posting cold.
module SignupHelpers
  # The first post's params: an email address from a form served a moment ago.
  def signup_params(email_address:, issued_at: 30.seconds.ago, **extra)
    { step: "start", email_address: email_address, signup_token: SignupFormToken.generate(issued_at) }.merge(extra)
  end

  # A new person through the whole screen: their email, the code we emailed,
  # their name. Leaves `response` as the last step that ran: the landing
  # redirect when it went through, or the refusal when the first step was
  # stopped (honeypot, throttle, blocked range).
  def complete_signup(email, first_name: "Maya", last_name: "Okafor", env: {}, **extra)
    post handle_signin_path, params: signup_params(email_address: email, **extra), env: env
    return unless response.redirect? && response.location == signin_url

    post handle_signin_path, params: { step: "code", code: emailed_code_for(email) }, env: env
    post handle_signin_path, params: { step: "create", first_name: first_name, last_name: last_name }, env: env
  end

  # The 6-digit code in the newest sign-in email queued for this address.
  def emailed_code_for(email)
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.reverse.find do |queued|
      args = queued[:args]
      args[0] == "AuthMailer" && args[1] == "sign_in_code" && args[3]["args"][0] == email.downcase
    end
    raise "no sign-in code was emailed to #{email}" unless job

    job[:args][3]["args"][1]
  end
end

RSpec.configure do |config|
  config.include SignupHelpers, type: :request
end
